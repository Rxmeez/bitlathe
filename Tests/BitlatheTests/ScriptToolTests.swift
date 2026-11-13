import XCTest
@testable import BitlatheCore
@testable import BitlatheTools

final class ScriptToolTests: XCTestCase {
    private func script(_ source: String, name: String = "t.js") -> UserScript {
        UserScript(url: URL(fileURLWithPath: "/tmp/\(name)"), source: source)!
    }
    private func run(_ s: UserScript, _ text: String, selection: Range<Int>? = nil) throws -> ToolOutput {
        try s.run(ToolInput(.text(text), selection: selection))
    }
    private func example(_ file: String) throws -> UserScript {
        let url = try XCTUnwrap(ScriptExamples.exampleURLs.first { $0.lastPathComponent == file }, file)
        return try XCTUnwrap(UserScript(url: url))
    }

    func testHeaderParsing() {
        let s = script("""
        /** @bitlathe { "name": "Shout", "description": "Upper", "icon": "speaker", "keywords": ["loud"], "detect": "^!" } */
        function main(input) { input.text = input.text.toUpperCase(); }
        """, name: "My Shout.js")
        XCTAssertEqual(s.name, "Shout")
        XCTAssertEqual(s.summary, "Upper")
        XCTAssertEqual(s.symbol, "speaker")
        XCTAssertTrue(s.keywords.contains("loud"))
        XCTAssertEqual(s.id, "script.my-shout")
        XCTAssertNotNil(s.detect("!hey"))
        XCTAssertNil(s.detect("hey"))
    }

    func testBoopHeaderAndDefaults() {
        let boop = script("/**\n{\"api\":1,\"name\":\"Boop One\",\"description\":\"d\",\"tags\":\"a, b\"}\n**/\nfunction main(i){}")
        XCTAssertEqual(boop.name, "Boop One")
        XCTAssertTrue(boop.keywords.contains("b"))
        let bare = script("function main(i){}", name: "plain.js")
        XCTAssertEqual(bare.name, "plain")
        XCTAssertEqual(bare.symbol, "scroll")
    }

    func testRun() throws {
        let s = script("function main(input) { input.text = input.text.split('').reverse().join(''); }")
        XCTAssertEqual(try run(s, "abc").text, "cba")
    }

    func testPostInfoBecomesWarningAndPostErrorThrows() throws {
        let info = script("function main(input) { input.postInfo('heads up'); }")
        XCTAssertEqual(try run(info, "x").warnings, ["heads up"])
        let err = script("function main(input) { input.postError('nope'); }")
        XCTAssertThrowsError(try run(err, "x")) { XCTAssertEqual(($0 as? ToolError)?.message, "nope") }
    }

    func testSyntaxAndRuntimeErrors() {
        XCTAssertThrowsError(try run(script("function main(input) {"), "x"))
        let boom = script("function main(input) {\n\n  null.x;\n}")
        XCTAssertThrowsError(try run(boom, "x")) { XCTAssertEqual(($0 as? ToolError)?.line, 3) }
        XCTAssertThrowsError(try run(script("var a = 1;"), "x")) { XCTAssertTrue(($0 as? ToolError)?.message.contains("main") == true) }
    }

    func testTimeout() {
        let s = script("function main(input) { while (true) {} }")
        let start = Date()
        XCTAssertThrowsError(try run(s, "x")) { XCTAssertTrue(($0 as? ToolError)?.message.contains("timed out") == true) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func testSelection() throws {
        let s = script("function main(input) { input.text = '[' + input.text + '|' + input.selection + '|' + input.fullText.length + ']'; }")
        XCTAssertEqual(try run(s, "hello world", selection: 6..<11).text, "[world|world|11]")
        XCTAssertEqual(try run(s, "hello world").text, "[hello world||11]")
    }

    func testAsToolIsScriptKind() async throws {
        let tool = script("/** @bitlathe {\"name\":\"X\"} */ function main(i){ i.text = 'ok'; }").asTool
        XCTAssertEqual(tool.kind, .script)
        let out = try await tool.run(text: "in")
        XCTAssertEqual(out.text, "ok")
    }

    func testLoaderReportsProblems() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bl-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "function main(i){}".write(to: dir.appendingPathComponent("good.js"), atomically: true, encoding: .utf8)
        try "var nothing = 1;".write(to: dir.appendingPathComponent("nomain.js"), atomically: true, encoding: .utf8)
        try "/** @bitlathe { name: } */ function main(i){}".write(to: dir.appendingPathComponent("badheader.js"), atomically: true, encoding: .utf8)
        try "ignored".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let report = ScriptLoader.loadReport(folder: dir)
        XCTAssertEqual(report.scripts.map(\.slug).sorted(), ["badheader", "good"])
        XCTAssertTrue(report.issues(for: dir.appendingPathComponent("nomain.js")).first?.isFatal == true)
        XCTAssertTrue(report.issues(for: dir.appendingPathComponent("badheader.js")).first?.isFatal == false)
    }

    func testBundledExamplesLoadAndWork() throws {
        XCTAssertGreaterThanOrEqual(ScriptExamples.exampleURLs.count, 10)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bl-examples-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(try ScriptExamples.install(into: dir), ScriptExamples.exampleURLs.count)
        XCTAssertEqual(try ScriptExamples.install(into: dir), 0)
        let report = ScriptLoader.loadReport(folder: dir)
        XCTAssertEqual(report.issues, [])
        XCTAssertEqual(report.scripts.count, ScriptExamples.exampleURLs.count)
        let template = script(ScriptExamples.template)
        XCTAssertEqual(template.name, "My Script")
        XCTAssertEqual(try run(template, "abc").text, "ABC")
    }

    func testExamples() throws {
        XCTAssertEqual(try run(example("sort-json-keys.js"), #"{"b":1,"a":{"d":1,"c":2}}"#).text,
                       "{\n  \"a\" : {\n    \"c\" : 2,\n    \"d\" : 1\n  },\n  \"b\" : 1\n}".replacingOccurrences(of: " : ", with: ": "))
        XCTAssertThrowsError(try run(example("sort-json-keys.js"), "nope"))
        XCTAssertEqual(try run(example("url-slug.js"), "Café Déjà Vu & Co's  Menu!").text, "cafe-deja-vu-and-cos-menu")
        XCTAssertTrue(try run(example("count-words.js"), "One two three. Four!").text.contains("Words:          4"))
        XCTAssertEqual(try run(example("reverse-lines.js"), "a\nb\nc").text, "c\nb\na")
        XCTAssertEqual(try run(example("camel-to-snake.js"), "userId parseHTTPResponse X").text, "user_id parse_http_response x")
        XCTAssertEqual(try run(example("strip-ansi.js"), "\u{1B}[31mred\u{1B}[0m ok").text, "red ok")
        let wrapped = try run(example("wrap-80.js"), String(repeating: "word ", count: 40)).text
        XCTAssertTrue(wrapped.split(separator: "\n").allSatisfy { $0.count <= 80 })
        XCTAssertEqual(wrapped.split(separator: "\n").count, 3)
        let emails = try run(example("extract-emails.js"), "a@x.io, B@y.com; a@X.io").text
        XCTAssertEqual(emails, "a@x.io\nB@y.com")
        XCTAssertEqual(try run(example("json-to-markdown-table.js"), #"[{"a":1,"b":"x|y"},{"a":2}]"#).text,
                       "| a | b |\n| --- | --- |\n| 1 | x\\|y |\n| 2 |  |")
        XCTAssertEqual(try run(example("add-line-numbers.js"), "a\nb").text, "1  a\n2  b")
        XCTAssertNotNil(try example("sort-json-keys.js").detect(#"{"a":1}"#))
        XCTAssertNotNil(try example("strip-ansi.js").detect("\u{1B}[1mx"))
    }
}
