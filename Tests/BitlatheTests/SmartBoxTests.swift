import XCTest
@testable import BitlatheCore
@testable import BitlatheTools

final class SmartBoxTests: XCTestCase {
    let tools = ToolCatalog.all
    var byID: [String: AnyTool] { Dictionary(tools.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    func analyse(_ s: String, learned: SmartBox.Learned = [:]) throws -> SmartBox.Analysis {
        try XCTUnwrap(SmartBox.analyse(s, tools: tools, learned: learned))
    }

    func testEmptyInputHasNoAnalysis() {
        XCTAssertNil(SmartBox.analyse("  \n ", tools: tools))
    }

    func testJSONLeadsWithTheFormatterAndOffersItsModes() throws {
        let a = try analyse(#"{"name":"Bitlathe","tags":["mac","dev"]}"#)
        XCTAssertEqual(a.kind, .data)
        XCTAssertEqual(a.formatKey, "json.format")
        XCTAssertEqual(a.actions.first?.tool.id, "json.format")
        XCTAssertTrue(a.actions.contains { $0.tool.id == "json.format" && $0.title == "Minify" && $0.options["mode"] == .string("minify") }, "mode variants are offered")
        XCTAssertFalse(a.isSensitive)
        XCTAssertLessThanOrEqual(a.actions.count, 6)
        XCTAssertEqual(Set(a.actions.map(\.key)).count, a.actions.count, "no duplicate actions")
    }

    func testJWTIsDetectedAndMarkedSensitive() throws {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let a = try analyse(jwt)
        XCTAssertEqual(a.actions.first?.tool.id, "jwt.debug")
        XCTAssertTrue(a.isSensitive)
    }

    func testLearningPromotesTheUsualChoiceAndCanAddUndetectedTools() throws {
        let json = #"{"a":1,"b":[true,null]}"#
        let plain = try analyse(json)
        let second = try XCTUnwrap(plain.actions.dropFirst().first)
        let learned = try analyse(json, learned: ["json.format": [second.key: 5]])
        XCTAssertEqual(learned.actions.first?.key, second.key, "five accepts outrank the detection order")
        XCTAssertEqual(learned.actions.first?.learned, 5)

        // A remembered action that detection would not offer still appears.
        let remembered = try analyse(json, learned: ["json.format": ["text.case": 3]])
        XCTAssertTrue(remembered.actions.contains { $0.tool.id == "text.case" })
    }

    func testBase64HidingJSONChainsIntoTheFormatter() async throws {
        let b64 = Data(#"{"user":{"id":42},"active":true}"#.utf8).base64EncodedString()
        let a = try analyse(b64)
        let first = try XCTUnwrap(a.actions.first)
        XCTAssertEqual(first.tool.id, "base64.text")
        let out = try await first.tool.run(text: b64, options: first.options)
        let chain = try XCTUnwrap(SmartBox.chain(after: first, output: out.text, tools: tools))
        XCTAssertEqual(chain.then?.tool.id, "json.format")
        XCTAssertEqual(chain.key, first.key + ">json.format")
        // Already formatted output needs no second step.
        XCTAssertNil(SmartBox.chain(after: first, output: "{\n  \"a\": 1\n}", tools: tools))
    }

    func testTypedCommandsRunGenerators() async throws {
        let a = try analyse("3 uuid v7")
        XCTAssertEqual(a.kind, .command)
        let first = try XCTUnwrap(a.actions.first)
        XCTAssertEqual(first.tool.id, "id.generate")
        XCTAssertEqual(first.options["kind"], .string("uuid7"))
        XCTAssertEqual(first.options["count"], .int(3))
        let out = try await first.tool.run(text: first.inputOverride ?? "", options: first.options)
        let lines = out.text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.allSatisfy { $0.count == 36 && $0.dropFirst(14).hasPrefix("7") }, out.text)

        let pw = try XCTUnwrap(try analyse("password 32").actions.first)
        let pwOut = try await pw.tool.run(text: "", options: pw.options)
        XCTAssertEqual(pwOut.text.trimmingCharacters(in: .whitespacesAndNewlines).count, 32)

        let now = try XCTUnwrap(try analyse("now").actions.first)
        XCTAssertEqual(now.tool.id, "time.unix")
        XCTAssertEqual(now.inputOverride, "now")
        XCTAssertNoThrow(try analyse("lorem 2 sentences"))
        XCTAssertEqual(try analyse("lorem 2 sentences").actions.first?.options["unit"], .string("sentences"))
    }

    func testWordsFindToolsAndProseFallsBackToTextTools() throws {
        let a = try analyse("regex")
        XCTAssertEqual(a.kind, .words)
        XCTAssertTrue(a.actions.contains { $0.tool.id == "regex.test" && $0.opensTool })
        let prose = try analyse("The quick brown fox jumps over the lazy dog.\nTwice.")
        XCTAssertEqual(prose.kind, .words)
        XCTAssertTrue(prose.actions.contains { $0.tool.id == "string.inspect" })
    }

    func testLearningKeysRoundTrip() throws {
        let key = SmartBox.key("json.format", ["mode": .string("minify"), "indent": .string("4")])
        XCTAssertEqual(key, "json.format|indent=4&mode=minify")
        let a = try XCTUnwrap(SmartBox.action(fromKey: key, tools: byID))
        XCTAssertEqual(a.options["mode"], .string("minify"))
        XCTAssertNil(SmartBox.action(fromKey: "nope.tool", tools: byID))
    }

    func testSecretsAreRecognised() {
        XCTAssertTrue(SmartBox.looksSecret("curl -H 'Authorization: Bearer abc123def' https://x"))
        XCTAssertTrue(SmartBox.looksSecret("-----BEGIN RSA PRIVATE KEY-----\nMIIE"))
        XCTAssertTrue(SmartBox.looksSecret("API_KEY=sk_live_abcdef123456"))
        XCTAssertFalse(SmartBox.looksSecret(#"{"name":"Bitlathe"}"#))
    }

    func testTypicalInputsAnalyseQuickly() throws {
        let inputs = [#"{"a":1}"#, "1700000000", "*/15 9-17 * * 1-5", "#3D7BFF", "https://example.com/?q=1", "SGVsbG8gd29ybGQ=", "3 uuid", "regex"]
        let clock = ContinuousClock()
        for input in inputs {
            let elapsed = clock.measure { _ = SmartBox.analyse(input, tools: tools) }
            XCTAssertLessThan(elapsed, .milliseconds(60), input)
        }
    }
}

final class SmartBoxStoreTests: XCTestCase {
    func testChoicesAccumulateAndClear() async throws {
        let store = try DataStore.inMemory()
        try await store.recordChoice(format: "json.format", action: "convert.yaml-json")
        try await store.recordChoice(format: "json.format", action: "convert.yaml-json")
        try await store.recordChoice(format: "jwt.debug", action: "jwt.debug")
        let all = try await store.choices()
        XCTAssertEqual(all["json.format"]?["convert.yaml-json"], 2)
        XCTAssertEqual(all["jwt.debug"]?["jwt.debug"], 1)
        try await store.clearChoices()
        let none = try await store.choices()
        XCTAssertTrue(none.isEmpty)
    }

    func testLatestInputsAreNewestFirstAndDistinct() async throws {
        let store = try DataStore.inMemory()
        try await store.addHistory(toolID: "json.format", input: "{\"a\":1}", options: [:])
        try await store.addHistory(toolID: "time.unix", input: "1700000000", options: [:])
        try await store.addHistory(toolID: "json.format", input: "{\"a\":1}", options: [:])
        let latest = try await store.latestInputs(limit: 5)
        XCTAssertEqual(latest.map(\.input), ["{\"a\":1}", "1700000000"])
    }
}
