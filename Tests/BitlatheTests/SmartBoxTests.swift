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

    // MARK: Typed instructions

    func run(_ s: String) async throws -> (SmartBox.Analysis, String) {
        let a = try analyse(s)
        let action = try XCTUnwrap(a.actions.first)
        let out = try await action.tool.run(text: action.inputOverride ?? s, options: action.options)
        return (a, out.text)
    }

    func testInstructionsRunOnTheRestOfTheText() async throws {
        let (hash, digest) = try await run("sha256 hello")
        XCTAssertEqual(hash.kind, .command)
        XCTAssertEqual(hash.formatKey, "intent:hash")
        XCTAssertEqual(hash.actions.first?.title, "SHA-256")
        XCTAssertTrue(digest.contains("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"), digest)

        let (_, encoded) = try await run("base64 encode hello")
        XCTAssertEqual(encoded.trimmingCharacters(in: .whitespacesAndNewlines), "aGVsbG8=")
        let (_, decoded) = try await run("url decode a%20b%26c")
        XCTAssertEqual(decoded.trimmingCharacters(in: .whitespacesAndNewlines), "a b&c")
        let (_, upper) = try await run("uppercase hello world")
        XCTAssertEqual(upper.trimmingCharacters(in: .whitespacesAndNewlines), "HELLO WORLD")
        let (_, snake) = try await run("snake_case: helloWorld")
        XCTAssertEqual(snake.trimmingCharacters(in: .whitespacesAndNewlines), "hello_world")
    }

    func testInstructionsPickTheToolFromTheData() async throws {
        let (yaml, text) = try await run(#"to yaml {"name":"Bitlathe","n":2}"#)
        XCTAssertEqual(yaml.actions.first?.tool.id, "convert.yaml-json")
        XCTAssertEqual(yaml.actions.first?.options["direction"], .string("json2yaml"))
        XCTAssertTrue(text.contains("name: Bitlathe"), text)

        let (json, back) = try await run("to json\nname: Bitlathe\nn: 2")
        XCTAssertEqual(json.actions.first?.options["direction"], .string("yaml2json"))
        XCTAssertTrue(back.contains("\"name\""), back)

        let (minify, small) = try await run("minify {\n  \"a\": 1\n}")
        XCTAssertEqual(minify.actions.first?.tool.id, "json.format")
        XCTAssertEqual(small.trimmingCharacters(in: .whitespacesAndNewlines), #"{"a":1}"#)
    }

    func testProseIsNotMistakenForAnInstruction() throws {
        // Everyday words need a colon or a new line before the data.
        for prose in ["sort the list by name before you send it", "title of the next release", "format is not known yet",
                      "lower bound on the result", "check the logs tomorrow morning"] {
            XCTAssertNotEqual(try analyse(prose).kind, .command, prose)
        }
        XCTAssertEqual(try analyse("sort:\nb\na").actions.first?.options["operation"], .string("sort"))
        XCTAssertEqual(try analyse("sort\nb\na").actions.first?.tool.id, "text.lines")
        // A phrase with nothing after it is a tool search, and longer words are not phrases.
        XCTAssertNotEqual(try analyse("sha256").kind, .command)
        XCTAssertNotEqual(try analyse("sha256sum output").kind, .command)
    }

    func testAnInstructionKeepsWhatTheDataWouldGetOneKeyAway() throws {
        let a = try analyse(#"to yaml {"name":"Bitlathe"}"#)
        XCTAssertGreaterThan(a.actions.count, 1)
        XCTAssertEqual(a.actions[1].tool.id, "json.format", "the data is JSON, so its formatter is the next choice")
        XCTAssertEqual(a.actions[1].inputOverride, #"{"name":"Bitlathe"}"#, "alternatives run on the data, not on the instruction")
        // A choice remembered for another instruction of the same kind does not leak in.
        let learned: SmartBox.Learned = ["intent:hash": ["hash.generate|algorithm=md5": 9]]
        let b = try analyse("sha256 hello", learned: learned)
        XCTAssertFalse(b.actions.contains { $0.options["algorithm"] == .string("md5") })
    }

    func testRequestsInWordsFindTheTool() throws {
        let a = try analyse("convert this to yaml")
        XCTAssertEqual(a.kind, .words)
        XCTAssertEqual(a.actions.first?.tool.id, "convert.yaml-json", a.actions.map(\.title).joined(separator: ", "))
        let prose = try analyse("The quick brown fox jumps over the lazy dog.")
        XCTAssertEqual(prose.actions.first?.tool.id, "string.inspect")
    }

    func testLookAlikeActionsAreMerged() throws {
        // Remembered with other options, the same tool would show as a second identical chip.
        let learned: SmartBox.Learned = ["json.format": ["json.format|sortKeys=true": 1]]
        let a = try analyse(#"{"name":"Bitlathe","tags":["mac","dev"]}"#, learned: learned)
        let labels = a.actions.map { $0.title + "|" + ($0.detail ?? "") }
        XCTAssertEqual(Set(labels).count, labels.count, labels.joined(separator: ", "))
    }

    func testBrokenJSONIsOfferedARepairAndTheFormatter() async throws {
        let broken = #"{"name": "Bitlathe", "tags": ["a" "b"]"#
        let a = try analyse(broken)
        XCTAssertEqual(a.kind, .data)
        XCTAssertEqual(a.formatName, "JSON with a mistake")
        XCTAssertEqual(a.actions.map(\.title).prefix(2), ["Repair JSON", "JSON Formatter"])
        XCTAssertEqual(a.actions.first?.reason, "Added 1 missing comma, closed 1 bracket")
        XCTAssertFalse(a.actions.contains { $0.title == "Minify" }, "no point offering modes that cannot run")
        let repair = try XCTUnwrap(a.actions.first)
        let out = try await repair.tool.run(text: broken, options: repair.options)
        XCTAssertEqual(out.text, "{\n  \"name\": \"Bitlathe\",\n  \"tags\": [\n    \"a\",\n    \"b\"\n  ]\n}")
        XCTAssertTrue(out.warnings.first?.hasPrefix("Repaired: added 1 missing comma") == true, out.warnings.joined())
        // Balanced but wrong ("looks like JSON with errors" at 55 %) must not lose to a script's regex either.
        XCTAssertEqual(try analyse(#"{"a": 1 "b": 2}"#).actions.first?.title, "Repair JSON")
        // Valid JSON is unaffected, and text that merely starts with a bracket is not JSON.
        XCTAssertEqual(try analyse(#"{"a":1}"#).formatName.contains("mistake"), false)
        XCTAssertNotEqual(try analyse("[draft] release notes for Friday").actions.first?.tool.id, "json.format")
    }

    func testJSONRepair() throws {
        func fix(_ s: String) -> String? { JSONRepair.repair(s)?.json }
        XCTAssertEqual(fix(#"{"a": 1 "b": 2}"#), #"{"a":1,"b":2}"#)                                   // missing comma
        XCTAssertEqual(fix(#"{"a": [1, 2, {"b": tru"#), #"{"a":[1,2,{"b":true}]}"#)                    // cut off
        XCTAssertEqual(fix("{'name': 'O\\'Brien', active: True, n: None,}"), #"{"name":"O'Brien","active":true,"n":null}"#)
        XCTAssertEqual(fix(#"{"a": "unterminated"#), #"{"a":"unterminated"}"#)
        XCTAssertEqual(fix(#"[1, 2,, 3,]"#), "[1,2,3]")
        XCTAssertEqual(fix("{\n  // note\n  \"a\": 0x1F, /* c */ \"b\": .5\n}"), #"{"a":31,"b":0.5}"#)
        XCTAssertEqual(fix(#"{"a": }"#), #"{"a":null}"#)
        XCTAssertEqual(fix(#"{"a" 1}"#), #"{"a":1}"#)
        XCTAssertEqual(fix(#"{“a”: “b”}"#), #"{"a":"b"}"#)                                             // smart quotes
        XCTAssertEqual(fix(#"{"when": 2024-01-05, "ok": yes}"#), #"{"when":"2024-01-05","ok":"yes"}"#)
        XCTAssertEqual(fix("{\"a\": \"line one\nline two\"}"), #"{"a":"line one\nline two"}"#)
        XCTAssertEqual(fix(#"{"a": [1, 2}"#), #"{"a":[1,2]}"#)                                         // wrong closer
        XCTAssertEqual(fix(#"{"a": 1} trailing words"#), #"{"a":1}"#)
        // Nothing to do, or not JSON at all: no result.
        XCTAssertNil(fix(#"{"a": 1, "b": [true, null]}"#))
        XCTAssertNil(fix("hello world"))
        XCTAssertNil(fix(""))
        // Strings are left alone: brackets and commas inside them are data.
        XCTAssertEqual(fix(#"{"a": "x, [y] {z}" "b": "it's"}"#), #"{"a":"x, [y] {z}","b":"it's"}"#)
        XCTAssertEqual(JSONRepair.repair(#"{'a': 1, 'b': 2"#)?.summary, "Closed 1 bracket, changed 2 strings to double quotes")
    }

    func testListsGetTheFixTheyNeed() async throws {
        let a = try analyse("banana\napple\ncherry\napple\nbanana\ndate")
        XCTAssertEqual(a.formatKey, "lines")
        XCTAssertEqual(a.actions.first?.title, "Remove duplicates")
        XCTAssertEqual(a.actions.first?.reason, "2 lines are repeated")
        XCTAssertEqual(a.actions.dropFirst().first?.title, "Sort lines")
        let out = try await XCTUnwrap(a.actions.first).tool.run(text: "b\na\nb", options: XCTUnwrap(a.actions.first).options)
        XCTAssertEqual(out.text.trimmingCharacters(in: .whitespacesAndNewlines), "b\na")
        // Already tidy: nothing to fix, so the general text tools lead. Wrapped prose is not a list.
        XCTAssertEqual(try analyse("apple\nbanana\ncherry").actions.first?.tool.id, "string.inspect")
        let prose = "It was a bright cold day in April, and the clocks\nwere striking thirteen. Winston Smith, his chin nuzzled\ninto his breast in an effort to escape the vile wind."
        XCTAssertEqual(try analyse(prose).formatKey, "words")
    }

    // MARK: On-device model routing (the model's reply is canned here; only the checks are under test)

    func advisorQuery(_ text: String) throws -> SmartBox.Advisor.Query {
        try XCTUnwrap(SmartBox.Advisor.query(for: text, analysis: try analyse(text), tools: tools), text)
    }

    func testTheModelIsOnlyAskedAboutRequestsInWords() throws {
        let q = try advisorQuery("what is 1700000000 in tokyo time")
        XCTAssertTrue(q.shortlist.contains("time.unix"), q.shortlist.joined(separator: ", "))
        XCTAssertLessThanOrEqual(q.shortlist.count, 14)
        XCTAssertTrue(q.instructions.contains("time.unix:"))
        XCTAssertLessThan(q.instructions.count + q.prompt.count, 6000, "fits a small context window")
        func asked(_ s: String) throws -> Bool { SmartBox.Advisor.query(for: s, analysis: try analyse(s), tools: tools) != nil }
        XCTAssertFalse(try asked(#"{"a":1}"#), "recognised data")
        XCTAssertFalse(try asked("sha256 hello"), "an instruction the rules handle")
        XCTAssertFalse(try asked("3 uuid v7"), "a command")
        XCTAssertFalse(try asked("hello"), "one word")
        XCTAssertFalse(try asked("decode this password=hunter2secret"), "never a secret")
        let long = String(repeating: "word ", count: 40)
        XCTAssertFalse(try asked(long), "a paragraph is not a request")
    }

    func testModelRepliesAreChecked() async throws {
        let q = try advisorQuery("what is 1700000000 in tokyo time")
        let pick = try XCTUnwrap(SmartBox.Advisor.action(fromReply: "TOOL: time.unix timeZone=Asia/Tokyo\nINPUT: 1700000000", query: q, tools: tools))
        XCTAssertEqual(pick.tool.id, "time.unix")
        XCTAssertEqual(pick.inputOverride, "1700000000")
        XCTAssertEqual(pick.options["timeZone"], .string("Asia/Tokyo"))
        XCTAssertEqual(pick.reason, "Suggested by the on-device model")
        let out = try await pick.tool.run(text: try XCTUnwrap(pick.inputOverride), options: pick.options)
        XCTAssertTrue(out.metadata.contains { $0.value.contains("2023") }, "the tool, not the model, produces the result")

        // A tool that was not on the list, or no tool: no suggestion.
        XCTAssertNil(SmartBox.Advisor.action(fromReply: "TOOL: shell.exec rm=-rf\nINPUT: x", query: q, tools: tools))
        XCTAssertNil(SmartBox.Advisor.action(fromReply: "TOOL: none", query: q, tools: tools))
        XCTAssertNil(SmartBox.Advisor.action(fromReply: "The answer is 9am.", query: q, tools: tools))
        // Input the person never typed is refused: with no data of their own, the tool is only offered to open.
        let invented = try XCTUnwrap(SmartBox.Advisor.action(fromReply: "TOOL: time.unix\nINPUT: 1234567890", query: q, tools: tools))
        XCTAssertTrue(invented.opensTool)
        XCTAssertNil(invented.inputOverride)
        // Unknown options and values are dropped, the rest kept.
        let sloppy = try XCTUnwrap(SmartBox.Advisor.action(fromReply: "TOOL: `time.unix` unit=fortnights bogus=1 unit=ms\nINPUT: 1700000000", query: q, tools: tools))
        XCTAssertEqual(sloppy.options, ["unit": .string("ms")])
    }

    func testModelRequestsUseTheLinesBelowAsData() throws {
        let text = "turn these into a typescript interface please\nsome text that is not json at all"
        let q = try advisorQuery(text)
        let id = try XCTUnwrap(q.shortlist.first)
        let pick = try XCTUnwrap(SmartBox.Advisor.action(fromReply: "TOOL: \(id)\nINPUT:", query: q, tools: tools))
        if !pick.opensTool, pick.tool.io.input == .text {
            XCTAssertEqual(pick.inputOverride, "some text that is not json at all")
        }
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

    func testOldChoicesFade() async throws {
        let store = try DataStore.inMemory()
        let now = Date()
        let day: TimeInterval = 24 * 3600
        for _ in 0..<8 { try await store.recordChoice(format: "json.format", action: "old", at: now.addingTimeInterval(-65 * day)) }
        for _ in 0..<3 { try await store.recordChoice(format: "json.format", action: "new", at: now.addingTimeInterval(-day)) }
        try await store.recordChoice(format: "json.format", action: "ancient", at: now.addingTimeInterval(-400 * day))
        let all = try await store.choices(now: now)
        XCTAssertEqual(all["json.format"]?["old"], 2, "8 choices, two half-lives ago")
        XCTAssertEqual(all["json.format"]?["new"], 3)
        XCTAssertNil(all["json.format"]?["ancient"], "a single choice from over a year ago no longer counts")
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
