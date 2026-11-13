import XCTest
import BitlatheCore
@testable import BitlatheTools

final class RegexTests: XCTestCase {
    private func opts(_ pattern: String, flags: String = "g", engine: String = "icu", replacement: String = "") -> RegexTool.Options {
        var o = RegexTool.Options()
        o.pattern = pattern; o.flags = flags; o.engine = engine; o.replacement = replacement
        return o
    }

    private func matches(_ text: String, _ pattern: String, flags: String = "g", engine: String) throws -> [String] {
        try RegexTool.test(text, options: opts(pattern, flags: flags, engine: engine)).matches.map(\.text)
    }

    // MARK: behaviour that must be identical in both engines

    func testCommonBehaviourMatchesAcrossEngines() throws {
        let cases: [(String, String, String, [String])] = [
            ("a1b22c333", "\\d+", "g", ["1", "22", "333"]),
            ("a1b22c333", "\\d+", "", ["1"]),
            ("Hello hello HELLO", "hello", "gi", ["Hello", "hello", "HELLO"]),
            ("l1\nl2\nl3", "^l\\d$", "gm", ["l1", "l2", "l3"]),
            ("l1\nl2", "^l\\d$", "g", []),
            ("a\nb", "a.b", "s", ["a\nb"]),
            ("a\nb", "a.b", "", []),
            ("baaac", "a*", "g", ["", "aaa", "", ""]),
            ("foo.bar", "\\w+(?=\\.)", "g", ["foo"]),
            ("price: $42, cost: $7", "(?<=\\$)\\d+", "g", ["42", "7"]),
            ("abcabc", "(abc)\\1", "g", ["abcabc"]),
            ("aaa", "a+?", "g", ["a", "a", "a"]),
            ("x@y.com, z@w.org", "[\\w.]+@[\\w.]+", "g", ["x@y.com", "z@w.org"]),
        ]
        for (text, pattern, flags, expected) in cases {
            for engine in ["icu", "js"] {
                XCTAssertEqual(try matches(text, pattern, flags: flags, engine: engine), expected, "\(engine): /\(pattern)/\(flags) on \(text.debugDescription)")
            }
        }
    }

    func testCaptureGroupsAndNamedGroupsBothEngines() throws {
        for engine in ["icu", "js"] {
            let r = try RegexTool.test("2026-01-15 and 2027-12-31", options: opts("(?<y>\\d{4})-(?<m>\\d{2})-(?<d>\\d{2})", engine: engine))
            XCTAssertEqual(r.matches.count, 2, engine)
            XCTAssertEqual(r.groupNames.compactMap { $0 }, ["y", "m", "d"], engine)
            XCTAssertEqual(r.matches[0].groups.map { $0.text }, ["2026", "01", "15"], engine)
            XCTAssertEqual(r.matches[0].groups.map { $0.name }, ["y", "m", "d"], engine)
            XCTAssertEqual(r.matches[1].groups[2].text, "31", engine)
            XCTAssertEqual(r.matches[0].range, 0..<10, engine)
            XCTAssertEqual(r.matches[1].range, 15..<25, engine)
        }
    }

    func testOptionalGroupThatDidNotParticipate() throws {
        for engine in ["icu", "js"] {
            let r = try RegexTool.test("ac", options: opts("a(b)?c", engine: engine))
            XCTAssertEqual(r.matches.first?.groups.count, 1, engine)
            XCTAssertNil(r.matches.first?.groups.first?.text, engine)
            XCTAssertNil(r.matches.first?.groups.first?.range, engine)
        }
    }

    func testReplacement() throws {
        for engine in ["icu", "js"] {
            let r = try RegexTool.test("Released 2026-01-15, patched 2026-02-01", options: opts("(\\d{4})-(\\d{2})-(\\d{2})", engine: engine, replacement: "$3/$2/$1"))
            XCTAssertEqual(r.replaced, "Released 15/01/2026, patched 01/02/2026", engine)
            let single = try RegexTool.test("a-a-a", options: opts("a", flags: "", engine: engine, replacement: "X"))
            XCTAssertEqual(single.replaced, "X-a-a", "non-global replaces first only (\(engine))")
            let none = try RegexTool.test("zzz", options: opts("a", engine: engine, replacement: "X"))
            XCTAssertEqual(none.replaced, "zzz", engine)
        }
    }

    func testNamedGroupReplacement() throws {
        let r = try RegexTool.test("2026-01-15", options: opts("(?<y>\\d{4})-(?<m>\\d{2})-(?<d>\\d{2})", engine: "icu", replacement: "${d}.${m}.${y}"))
        XCTAssertEqual(r.replaced, "15.01.2026")
    }

    func testOffsetsAreUTF16() throws {
        // The emoji is two UTF-16 units; annotations use UTF-16 offsets in both engines.
        for engine in ["icu", "js"] {
            let r = try RegexTool.test("😀 abc", options: opts("abc", engine: engine))
            XCTAssertEqual(r.matches.first?.range, 3..<6, engine)
        }
    }

    // MARK: engine differences (ICU vs JavaScript)

    func testUnicodeDigitsDifferBetweenEngines() throws {
        // ICU's \d is Unicode-aware (Nd); JavaScript's \d is ASCII-only.
        let arabicIndic = "٣٤"
        XCTAssertEqual(try matches(arabicIndic, "\\d+", engine: "icu"), ["٣٤"])
        XCTAssertEqual(try matches(arabicIndic, "\\d+", engine: "js"), [])
    }

    func testICUOnlySyntax() throws {
        // Possessive quantifiers and atomic groups exist in ICU but are a syntax error in JavaScript.
        XCTAssertEqual(try matches("aaa", "a++", engine: "icu"), ["aaa"])
        XCTAssertThrowsError(try matches("aaa", "a++", engine: "js"))
        XCTAssertEqual(try matches("foo", "(?i)FOO", flags: "g", engine: "icu"), ["foo"])
    }

    func testJSOnlySyntax() throws {
        // \k<name> named backreference; both engines accept it, but the JS $<name> replacement form is JS-only.
        for engine in ["icu", "js"] {
            XCTAssertEqual(try matches("abab", "(?<x>ab)\\k<x>", engine: engine), ["abab"], engine)
        }
        let r = try RegexTool.test("john smith", options: opts("(?<first>\\w+) (?<last>\\w+)", engine: "js", replacement: "$<last>, $<first>"))
        XCTAssertEqual(r.replaced, "smith, john")
    }

    func testInvalidPatternsThrow() {
        for engine in ["icu", "js"] {
            for bad in ["(unclosed", "[a-", "*abc", "a{2,1}"] {
                XCTAssertThrowsError(try RegexTool.test("x", options: opts(bad, engine: engine)), "\(engine) /\(bad)/") { XCTAssertTrue($0 is ToolError) }
            }
        }
        XCTAssertThrowsError(try RegexTool.test("x", options: opts("")))
    }

    func testCatastrophicPatternDoesNotHangTheICUEngineOnSmallInput() throws {
        // Sanity check: a nested quantifier on a short non-matching string completes promptly.
        let start = Date()
        _ = try matches(String(repeating: "a", count: 22) + "!", "(a+)+$", engine: "icu")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    // MARK: tool & helpers

    func testToolOutput() async throws {
        let out = try await TT.run("regex.test", "a1 b22", ["pattern": .string("([a-z])(\\d+)")])
        XCTAssertEqual(TT.meta(out, "Matches"), "2")
        XCTAssertTrue(out.text.contains("Match 1"))
        XCTAssertEqual(TT.facet(out, "Matches only"), "a1\nb22")
        XCTAssertFalse(out.annotations.isEmpty)
        let none = try await TT.run("regex.test", "zzz", ["pattern": .string("\\d")])
        XCTAssertEqual(none.text, "No matches")
        let js = try await TT.run("regex.test", "a1", ["pattern": .string("\\d"), "engine": .string("js")])
        XCTAssertEqual(TT.meta(js, "Matches"), "1")
    }

    func testGroupNameScanner() {
        XCTAssertEqual(RegexTool.groupNames("(a)(?<n>b)(?:c)(?=d)(?<!e)[(]\\(f(g)").map { $0 ?? "-" }, ["-", "n", "-"])
    }

    func testExplainerAndDetect() {
        XCTAssertFalse(RegexExplainer.explain("^\\d{3}-[a-z]+$").isEmpty)
        XCTAssertNotNil(RegexTool.detect("/^[a-z]+$/gi"))
        XCTAssertNil(RegexTool.detect("just a sentence"))
    }
}
