import XCTest
import BitlatheCore
@testable import BitlatheTools

final class DetectionTests: XCTestCase {
    private let tools = ToolCatalog.all

    private let gzipBase64 = "H4sIAAAAAAAAA8tIzcnJVyjPL8pJAQCFEUoNCwAAAA=="   // gzip("Hello world") as Base64

    /// (label, input, expected first tool id — nil means "nothing detected")
    private var corpus: [(String, String, String?)] {
        [
            ("JWT", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkFkYSJ9.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", "jwt.debug"),
            ("JWT with Bearer", "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkFkYSJ9.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", "jwt.debug"),
            ("UUID v5", "cfbff0d1-9375-5685-968c-48ce8b15ae17", "id.generate"),
            ("ULID", "01ARZ3NDEKTSV4RRFFQ69G5FAV", "id.generate"),
            ("Unix seconds", "1700000000", "time.unix"),
            ("Unix milliseconds", "1700000000000", "time.unix"),
            ("ISO 8601", "2023-11-14T22:13:20Z", "time.unix"),
            ("Cron every 15", "*/15 * * * *", "cron.parse"),
            ("Cron weekdays", "30 9 * * 1-5", "cron.parse"),
            ("curl", "curl -X POST https://api.example.com/v1/users -H 'Content-Type: application/json' -d '{\"name\":\"Ada\"}'", "curl.to-code"),
            ("Hex colour", "#3D7BFF", "color.convert"),
            ("CSS rgb()", "rgb(61, 123, 255)", "color.convert"),
            ("PEM certificate", TT.fixture("cert/rsa-selfsigned.pem"), "cert.x509"),
            ("PEM CSR", TT.fixture("cert/request.csr"), "cert.x509"),
            ("PEM private key", TT.fixture("keys/p256.pem"), "cert.x509"),
            ("Base64 text", "SGVsbG8sIFdvcmxkISBUaGlzIGlzIGJhc2U2NA==", "base64.text"),
            ("Gzip + Base64", gzipBase64, "compress.text"),
            ("JSON object", "{\"a\":1,\"b\":[1,2,3],\"c\":{\"d\":null}}", "json.format"),
            ("JSON array", "[1,2,3]", "json.format"),
            ("YAML", "name: Ada\nage: 36\ntags:\n  - a\n  - b\n", "yaml.format"),
            ("SQL", "SELECT id, name FROM users WHERE age > 30 ORDER BY name;", "sql.format"),
            ("XML", "<?xml version=\"1.0\"?><root><a>1</a></root>", "xml.format"),
            ("HTML", "<!DOCTYPE html><html><body><p>Hi</p></body></html>", "html.format"),
            ("CSS", "body { color: red; margin: 0 }", "css.format"),
            ("TOML", "[server]\nport = 8080\nhost = \"x\"\n", "toml.format"),
            ("CSV", "id,name,age\n1,Ada,36\n2,Alan,41\n", "csv.viewer"),
            ("Markdown", "# Title\n\n- item\n- item2\n\n**bold**", "markdown.preview"),
            ("Unified diff", "--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b", "text.diff"),
            ("URL", "https://example.com/path?a=1&b=2#frag", "url.parse"),
            ("URL-encoded", "hello%20world%21%20foo%3Dbar", "url.encode"),
            ("IPv4 CIDR", "192.168.1.0/24", "cidr.calc"),
            ("IPv6", "2001:db8::1", "cidr.calc"),
            ("Semver range", "^1.2.3", "semver.compare"),
            ("SHA-256 digest", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "hash.generate"),
            ("bcrypt hash", "$2y$04$BbWsgGsURH8ePGFLLyQlh../rQntQoj02S.wfSvOiYYqjp2eZYSYm", "password.hash"),
            ("SSH public key", TT.fixture("ssh/id_ed25519.pub").trimmingCharacters(in: .whitespacesAndNewlines), "ssh.fingerprint"),
            (".env file", "A=1\nB=two\nC=3", "env.inspect"),
            ("chmod octal", "755", "chmod.calc"),
            ("chmod symbolic", "rwxr-xr-x", "chmod.calc"),
            ("Unicode escapes", "\\u0048\\u0065\\u006c\\u006c\\u006f", "unicode.escape"),
            ("PHP serialize", "a:2:{i:0;s:1:\"a\";i:1;i:5;}", "php.serialize"),
            ("Hex bytes", "48 65 6c 6c 6f 20 57 6f 72 6c 64", "hex.text"),
            ("Plain prose", "hello world, this is just a sentence", nil),
        ]
    }

    func testCorpusRanksTheRightToolFirst() {
        XCTAssertGreaterThanOrEqual(corpus.count, 30)
        for (label, input, expected) in corpus {
            let report = DetectionEngine.detect(input, tools: tools)
            XCTAssertEqual(report.best?.tool.id, expected, "\(label): got \(report.results.prefix(3).map { "\($0.tool.id) \($0.score.confidence)" })")
        }
    }

    func testDetectionIsFastForTheTypicalCorpus() {
        // Warm up once (lazy regex / formatter setup), then take the best of three runs per input.
        for (_, input, _) in corpus { _ = DetectionEngine.detect(input, tools: tools) }
        var worst: (String, Duration) = ("", .zero)
        var total: Duration = .zero
        for (label, input, _) in corpus {
            let best = (0..<3).map { _ in DetectionEngine.detect(input, tools: tools).duration }.min()!
            total += best
            if best > worst.1 { worst = (label, best) }
        }
        XCTAssertLessThan(worst.1, .milliseconds(20), "slowest input: \(worst.0)")
        XCTAssertLessThan(total / corpus.count, .milliseconds(5), "mean per input")
    }

    func testReportedDurationMatchesWallClock() {
        let clock = ContinuousClock()
        var report: DetectionReport?
        let wall = clock.measure { report = DetectionEngine.detect("{\"a\":1}", tools: tools) }
        XCTAssertNotNil(report)
        XCTAssertLessThanOrEqual(report!.duration, wall + .milliseconds(1))
    }

    func testAlsoTryAndScoreOrdering() throws {
        let yaml = DetectionEngine.detect("name: Ada\nage: 36\n", tools: tools)
        XCTAssertEqual(yaml.best?.tool.id, "yaml.format")
        XCTAssertTrue(yaml.alsoTry.contains { $0.tool.id == "convert.yaml-json" })
        XCTAssertLessThanOrEqual(yaml.alsoTry.count, 4)
        XCTAssertFalse(yaml.alsoTry.contains { $0.tool.id == yaml.best?.tool.id })
        for report in [yaml, DetectionEngine.detect("{\"a\":1}", tools: tools)] {
            let scores = report.results.map(\.score.confidence)
            XCTAssertEqual(scores, scores.sorted(by: >), "results sorted by confidence")
        }
    }

    func testScoresCarryOptionsForTheTool() {
        let b64 = DetectionEngine.detect("SGVsbG8sIFdvcmxkISBUaGlzIGlzIGJhc2U2NA==", tools: tools)
        XCTAssertEqual(b64.best?.score.options["mode"], .string("decode"))
        let bcrypt = DetectionEngine.detect("$2y$04$BbWsgGsURH8ePGFLLyQlh../rQntQoj02S.wfSvOiYYqjp2eZYSYm", tools: tools)
        XCTAssertEqual(bcrypt.best?.score.options["mode"], .string("verify"))
    }

    func testEmptyAndWhitespaceInput() {
        for s in ["", "   ", "\n\n\t"] {
            let r = DetectionEngine.detect(s, tools: tools)
            XCTAssertTrue(r.results.isEmpty); XCTAssertNil(r.best); XCTAssertFalse(r.truncated)
        }
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(DetectionEngine.detect("\n  cfbff0d1-9375-5685-968c-48ce8b15ae17  \n", tools: tools).best?.tool.id, "id.generate")
        XCTAssertEqual(DetectionEngine.detect("\t1700000000\n", tools: tools).best?.tool.id, "time.unix")
    }

    func testIgnoredToolsAndMinimumConfidence() {
        let input = "{\"a\":1}"
        let all = DetectionEngine.detect(input, tools: tools)
        XCTAssertEqual(all.best?.tool.id, "json.format")
        let ignored = DetectionEngine.detect(input, tools: tools, ignoring: ["json.format"])
        XCTAssertFalse(ignored.results.contains { $0.tool.id == "json.format" })
        let strict = DetectionEngine.detect("SGVsbG8sIFdvcmxkISBUaGlzIGlzIGJhc2U2NA==", tools: tools, minimumConfidence: 0.99)
        XCTAssertTrue(strict.results.isEmpty)
    }

    func testSideEffectToolsAreNeverAutoSuggested() {
        let risky = AnyTool(id: "test.risky", name: "Risky", summary: "", category: .scripting, symbol: "bolt", sideEffects: true, kind: .script,
                            detect: { _ in DetectionScore(1.0, "always") }, run: { _, _ in .empty })
        let safe = AnyTool(id: "test.safe", name: "Safe", summary: "", category: .scripting, symbol: "bolt", kind: .script,
                           detect: { _ in DetectionScore(0.5, "sometimes") }, run: { _, _ in .empty })
        let r = DetectionEngine.detect("anything", tools: [risky, safe])
        XCTAssertEqual(r.results.map(\.tool.id), ["test.safe"])
    }

    func testTiesAreBrokenByNameDeterministically() {
        func tool(_ id: String, _ name: String) -> AnyTool {
            AnyTool(id: id, name: name, summary: "", category: .scripting, symbol: "bolt", kind: .script, detect: { _ in DetectionScore(0.7, "x") }, run: { _, _ in .empty })
        }
        let r = DetectionEngine.detect("x", tools: [tool("c", "Charlie"), tool("a", "Alpha"), tool("b", "Bravo")])
        XCTAssertEqual(r.results.map(\.tool.name), ["Alpha", "Bravo", "Charlie"])
    }

    func testLargeInputIsTruncatedAndStillFast() {
        let big = "[" + String(repeating: "{\"id\":1,\"name\":\"abc\"},", count: 300_000) + "{}]"   // ~7 MB
        XCTAssertGreaterThan(big.utf8.count, DetectionEngine.sampleLimit)
        let clock = ContinuousClock()
        var report: DetectionReport?
        let elapsed = clock.measure { report = DetectionEngine.detect(big, tools: tools) }
        XCTAssertEqual(report?.truncated, true)
        XCTAssertLessThan(elapsed, .milliseconds(500))
        XCTAssertEqual(report?.best?.tool.id, "json.format", "truncated sample still detected as JSON-like")
    }

    func testToolDetectorsNeverCrashOnHostileInput() {
        let inputs = ["\u{0}", String(repeating: "(", count: 5000), String(repeating: "a", count: 100_000), "\u{FFFD}\u{FFFD}", "💥👩‍👩‍👧‍👦", String(repeating: "\n", count: 1000) + "x",
                      "-----BEGIN CERTIFICATE-----", "$2", "eyJ.eyJ.", "::", "1e999999999", "0x", "{", "[", "<", "---\n---\n---"]
        for s in inputs { _ = DetectionEngine.detect(s, tools: tools) }
    }

    func testBinaryDecodersRejectDeepNesting() {
        // Regression: a long run of hex digits such as "aaaa…" decodes as CBOR maps nested inside maps and overflowed the stack.
        XCTAssertNil(BinaryDecodeTool.detect(String(repeating: "a", count: 100_000)))
        XCTAssertThrowsError(try CBOR.decode(Data(repeating: 0xA1, count: 5000)))
        XCTAssertThrowsError(try MessagePack.decode(Data(repeating: 0x91, count: 5000)))
        XCTAssertThrowsError(try CBOR.decode(Data(repeating: 0x81, count: 200) + Data([0x01])), "deeper than the supported 128 levels")
        XCTAssertNoThrow(try CBOR.decode(Data(repeating: 0x81, count: 50) + Data([0x01])), "ordinary nesting still decodes")
    }

    func testPathologicalLargeInputsStayResponsive() {
        // Regressions: `[0-9]*\.?[0-9]+` made a long run of digits take minutes in the unit detectors, and the semver detector
        // parsed an entire 64 KB paste as a version range.
        let inputs: [(String, String)] = [
            ("digits", String(repeating: "9", count: 60_000)), ("digits+unit", "1" + String(repeating: "0", count: 60_000) + "ms"),
            ("nested json", String(repeating: "{\"a\":", count: 30_000)), ("words", String(repeating: "x ", count: 30_000)),
            ("stars", String(repeating: "* ", count: 30_000)), ("many lines", String(repeating: "[a]\n", count: 15_000)),
            ("parens", String(repeating: "(", count: 60_000)), ("tags", String(repeating: "<a>", count: 20_000)), ("dashes", String(repeating: "- ", count: 30_000)),
            ("dots", String(repeating: "1.", count: 30_000)), ("escapes", String(repeating: "\\u00", count: 15_000)), ("percent", String(repeating: "%2", count: 30_000)),
            ("hex", String(repeating: "b", count: 60_000)),
        ]
        for (label, input) in inputs {
            let report = DetectionEngine.detect(input, tools: tools)
            XCTAssertLessThan(report.duration, .milliseconds(500), label)
        }
    }

    func testUnitDetectorsStillRecogniseRealValues() {
        XCTAssertNotNil(ByteSizeTool.detect("1.5 GB")); XCTAssertNotNil(ByteSizeTool.detect("512MiB")); XCTAssertNotNil(ByteSizeTool.detect(".5 KB"))
        XCTAssertNil(ByteSizeTool.detect("5. GB")); XCTAssertNil(ByteSizeTool.detect("GB"))
        XCTAssertNotNil(UnitConverterTool.detect("1500 ms")); XCTAssertNotNil(UnitConverterTool.detect("-2.5h".replacingOccurrences(of: "h", with: " hours")))
        XCTAssertNotNil(UnitConverterTool.detect("100 Mbps")); XCTAssertNil(UnitConverterTool.detect("100"))
    }
}
