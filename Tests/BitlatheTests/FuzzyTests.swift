import XCTest
import BitlatheCore
@testable import BitlatheTools

@MainActor
final class FuzzyTests: XCTestCase {
    private func registry() -> ToolRegistry {
        let r = ToolRegistry()
        r.register(ToolCatalog.all)
        return r
    }

    // MARK: Fuzzy.score

    func testEmptyQueryAndNonMatches() {
        XCTAssertEqual(Fuzzy.score(query: "", in: "Anything"), 0)
        XCTAssertNil(Fuzzy.score(query: "xyz", in: "JSON Formatter"))
        XCTAssertNil(Fuzzy.score(query: "zz", in: "JSON Formatter", secondary: "format validate minify json"))
    }

    func testMatchTierOrdering() throws {
        let prefix = try XCTUnwrap(Fuzzy.score(query: "json", in: "JSON Formatter"))
        let contains = try XCTUnwrap(Fuzzy.score(query: "json", in: "Convert JSON to YAML"))
        let tight = try XCTUnwrap(Fuzzy.score(query: "jf", in: "JSON Formatter"))
        let secondary = try XCTUnwrap(Fuzzy.score(query: "minify", in: "Formatter", secondary: "format validate minify"))
        XCTAssertGreaterThan(prefix, contains)
        XCTAssertGreaterThan(contains, tight)
        XCTAssertGreaterThan(tight, secondary)
        XCTAssertGreaterThan(Fuzzy.score(query: "json", in: "JSON")!, Fuzzy.score(query: "json", in: "JSON Formatter and friends")!, "shorter names win")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(Fuzzy.score(query: "JSON", in: "json formatter"), Fuzzy.score(query: "json", in: "JSON FORMATTER"))
    }

    func testTightSubsequencesOnly() {
        XCTAssertNotNil(Fuzzy.score(query: "jf", in: "JSON Formatter"), "initials")
        XCTAssertNotNil(Fuzzy.score(query: "b64", in: "Base64 Text"), "b64 → Base64")
        XCTAssertNotNil(Fuzzy.score(query: "jwt", in: "JWT Debugger"))
        XCTAssertNil(Fuzzy.score(query: "base", in: "SCSS Formatter"), "scattered letters must not match")
        XCTAssertNil(Fuzzy.score(query: "sf", in: "Unix Timestamp Converter"))
    }

    func testSecondaryTextNeedsWholeWordsOrSubstrings() {
        XCTAssertNotNil(Fuzzy.score(query: "yaml", in: "Data Converter", secondary: "convert.yaml-json yaml json"))
        XCTAssertNotNil(Fuzzy.score(query: "conv", in: "Data", secondary: "convert things"))
        XCTAssertNil(Fuzzy.score(query: "cv", in: "Data", secondary: "convert things"), "no scattered matches in secondary text")
        XCTAssertNil(Fuzzy.score(query: "am", in: "Data", secondary: "yaml json"), "two-letter queries only match word prefixes, not substrings")
        XCTAssertNotNil(Fuzzy.score(query: "ya", in: "Data", secondary: "yaml json"), "word prefix")
        XCTAssertNotNil(Fuzzy.score(query: "aml", in: "Data", secondary: "yaml json"), "three letters or more may match inside a word")
    }

    func testMatchIndices() {
        XCTAssertEqual(Fuzzy.matchIndices(query: "jf", in: "JSON Formatter"), [0, 5])
        XCTAssertEqual(Fuzzy.matchIndices(query: "json", in: "JSON Formatter"), [0, 1, 2, 3])
        XCTAssertEqual(Fuzzy.matchIndices(query: "xyz", in: "JSON Formatter"), [])
        XCTAssertEqual(Fuzzy.matchIndices(query: "", in: "abc"), [])
    }

    // MARK: registry search

    func testJSONRanksTheJSONFormatterFirst() {
        let r = registry().search("json")
        XCTAssertEqual(r.first?.id, "json.format")
        XCTAssertGreaterThan(r.count, 3, "other JSON tools follow")
        XCTAssertTrue(r.contains { $0.id == "convert.yaml-json" })
    }

    func testCanonicalToolsRankFirstForTheirName() {
        let expected: [String: String] = [
            "json": "json.format", "yaml": "yaml.format", "jwt": "jwt.debug", "cron": "cron.parse", "regex": "regex.test", "sql": "sql.format",
            "hash": "hash.generate", "diff": "text.diff", "color": "color.convert", "qr": "qr.code", "barcode": "barcode",
            "chmod": "chmod.calc", "cidr": "cidr.calc", "semver": "semver.compare", "toml": "toml.format", "xml": "xml.format",
            "css": "css.format", "curl": "curl.to-code", "ssh": "ssh.fingerprint", "bcrypt": "password.hash", "ocr": "ocr.text",
        ]
        let expectedNearTop: [String: String] = [
            "base64": "base64.text",
        ]
        let reg = registry()
        for (query, id) in expected {
            XCTAssertEqual(reg.search(query).first?.id, id, "search(\"\(query)\") → \(reg.search(query).prefix(3).map(\.id))")
        }
        // Families with several equally named siblings: the main tool must still be in the first three results.
        for (query, id) in expectedNearTop {
            XCTAssertTrue(reg.search(query).prefix(3).contains { $0.id == id }, "search(\"\(query)\") → \(reg.search(query).prefix(3).map(\.id))")
        }
    }

    func testFuzzyAbbreviationsAndPartialNames() {
        let reg = registry()
        XCTAssertEqual(reg.search("jwt").first?.id, "jwt.debug")
        XCTAssertTrue(reg.search("jsonf").contains { $0.id == "json.format" })
        XCTAssertEqual(reg.search("JSON").first?.id, "json.format", "case-insensitive")
        XCTAssertEqual(reg.search("  json  ").first?.id, "json.format", "surrounding spaces are trimmed")
        XCTAssertTrue(reg.search("timestamp").contains { $0.id == "time.unix" })
        XCTAssertTrue(reg.search("epoch").contains { $0.id == "time.unix" } || reg.search("unix").contains { $0.id == "time.unix" })
        XCTAssertTrue(reg.search("uuid").contains { $0.id == "id.generate" })
    }

    func testEmptyAndNoMatchQueries() {
        let reg = registry()
        XCTAssertEqual(reg.search("").count, ToolCatalog.all.count)
        XCTAssertEqual(reg.search("   ").count, ToolCatalog.all.count)
        XCTAssertTrue(reg.search("zzqqxxww").isEmpty)
    }

    func testLimit() {
        XCTAssertEqual(registry().search("a", limit: 5).count, 5)
        XCTAssertLessThanOrEqual(registry().search("json", limit: 2).count, 2)
        XCTAssertEqual(registry().search("json", limit: 2).first?.id, "json.format")
    }

    func testSearchIsFast() {
        let reg = registry()
        let clock = ContinuousClock()
        let d = clock.measure { for q in ["j", "js", "json", "b64", "hash", "unix time", "color", "x"] { _ = reg.search(q) } }
        XCTAssertLessThan(d, .milliseconds(100), "eight searches over the full catalogue")
    }

    func testRegistryBasics() {
        let reg = registry()
        XCTAssertEqual(reg.tools.count, ToolCatalog.all.count)
        XCTAssertEqual(reg.tool("json.format")?.name, ToolCatalog.all.first { $0.id == "json.format" }?.name)
        XCTAssertNil(reg.tool("nope"))
        // Re-registering replaces in place instead of duplicating.
        reg.register(ToolCatalog.all.first { $0.id == "json.format" }!)
        XCTAssertEqual(reg.tools.count, ToolCatalog.all.count)
        let script = AnyTool(id: "script.x", name: "Script X", summary: "", category: .scripting, symbol: "bolt", kind: .script, run: { _, _ in .empty })
        reg.register(script)
        XCTAssertEqual(reg.scripts.map(\.id), ["script.x"])
        XCTAssertEqual(reg.native.count, ToolCatalog.all.count)
        reg.unregister(kind: .script)
        XCTAssertTrue(reg.scripts.isEmpty); XCTAssertNil(reg.tool("script.x"))
        reg.unregister(id: "json.format")
        XCTAssertNil(reg["json.format"])
    }

    func testToolIDsAreUniqueAndCatalogComplete() {
        let ids = ToolCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate tool ids")
        for t in ToolCatalog.all { XCTAssertFalse(t.name.isEmpty, t.id); XCTAssertFalse(t.summary.isEmpty, t.id) }
    }
}
