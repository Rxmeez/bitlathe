import XCTest
@testable import BitlatheCore
@testable import BitlatheTools

final class MCPServerTests: XCTestCase {
    let server = MCPServer(tools: ToolCatalog.all, version: "test")

    func send(_ json: String) async throws -> [String: Any] {
        let reply = await server.handle(line: json)
        let line = try XCTUnwrap(reply)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    func call(_ tool: String, _ args: [String: Any]) async throws -> (text: String, isError: Bool) {
        let req: [String: Any] = ["jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": tool, "arguments": args]]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: req), as: UTF8.self)
        let response = try await send(line)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let blocks = result["content"] as? [[String: Any]] ?? []
        return (blocks.compactMap { $0["text"] as? String }.joined(separator: "\n"), result["isError"] as? Bool ?? false)
    }

    func testHandshakeAndToolList() async throws {
        let initResult = try await send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)["result"] as? [String: Any]
        XCTAssertEqual(initResult?["protocolVersion"] as? String, "2025-03-26", "echoes a supported version")
        let unknown = try await send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)["result"] as? [String: Any]
        XCTAssertEqual(unknown?["protocolVersion"] as? String, MCPServer.supportedVersions[0])
        let notification = await server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(notification, "notifications get no reply")
        let tools = try await send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)["result"] as? [String: Any]
        let names = (tools?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, ["detect", "smart_run", "run_tool", "list_tools", "run_pipeline"])
    }

    func testProtocolErrors() async throws {
        let parse = try await send("not json")["error"] as? [String: Any]
        XCTAssertEqual(parse?["code"] as? Int, -32700)
        let missing = try await send(#"{"jsonrpc":"2.0","id":3,"method":"nope"}"#)["error"] as? [String: Any]
        XCTAssertEqual(missing?["code"] as? Int, -32601)
    }

    func testRunToolIsExactAndValidatesOptions() async throws {
        let decoded = try await call("run_tool", ["tool": "base64.text", "input": "SGVsbG8gd29ybGQ=", "options": ["mode": "decode"]])
        XCTAssertFalse(decoded.isError)
        XCTAssertTrue(decoded.text.hasPrefix("Hello world"), decoded.text)

        let badKey = try await call("run_tool", ["tool": "json.format", "input": "{}", "options": ["nope": 1]])
        XCTAssertTrue(badKey.isError)
        XCTAssertTrue(badKey.text.contains("indent"), "lists the real options")

        let badChoice = try await call("run_tool", ["tool": "base64.text", "input": "x", "options": ["mode": "explode"]])
        XCTAssertTrue(badChoice.isError)
        XCTAssertTrue(badChoice.text.contains("decode"))

        let unknown = try await call("run_tool", ["tool": "jsn.format", "input": "{}"])
        XCTAssertTrue(unknown.isError)
        XCTAssertTrue(unknown.text.contains("json.format"), "suggests the near miss: \(unknown.text)")

        let numbers = try await call("run_tool", ["tool": "json.format", "input": #"{"b":1,"a":2}"#, "options": ["indent": "4", "sortKeys": true]])
        XCTAssertTrue(numbers.text.hasPrefix("{\n    \"a\": 2"), numbers.text)
    }

    func testSmartRunDetectAndPipelines() async throws {
        let b64 = Data(#"{"user":{"id":42}}"#.utf8).base64EncodedString()
        let smart = try await call("smart_run", ["input": b64])
        XCTAssertTrue(smart.text.contains("then json.format"), smart.text)
        XCTAssertTrue(smart.text.contains("\"id\": 42"), smart.text)

        let hashed = try await call("smart_run", ["input": "sha256 hello"])
        XCTAssertTrue(hashed.text.contains("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"), hashed.text)

        let request = try await call("smart_run", ["input": "json to yaml"])
        XCTAssertTrue(request.isError, "words without data are not run through a string inspector")
        XCTAssertTrue(request.text.contains("convert.yaml-json"), request.text)

        let ids = try await call("smart_run", ["input": "2 uuid v7"])
        XCTAssertEqual(ids.text.split(separator: "\n").filter { $0.count == 36 }.count, 2, ids.text)

        let detect = try await call("detect", ["input": "1700000000"])
        XCTAssertTrue(detect.text.contains("time.unix"))

        let piped = try await call("run_pipeline", ["expression": "base64.text mode=decode | json.format", "input": "eyJhIjoxfQ=="])
        XCTAssertTrue(piped.text.hasPrefix("{\n  \"a\": 1\n}"), piped.text)

        let listed = try await call("list_tools", ["query": "jwt"])
        XCTAssertTrue(listed.text.contains("jwt.debug"))
    }
}
