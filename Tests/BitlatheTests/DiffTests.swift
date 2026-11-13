import XCTest
import BitlatheCore
@testable import BitlatheTools

final class DiffTests: XCTestCase {
    private func lcsLength(_ a: [String], _ b: [String]) -> Int {
        var dp = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0..<a.count { for j in 0..<b.count { dp[i + 1][j + 1] = a[i] == b[j] ? dp[i][j] + 1 : max(dp[i][j + 1], dp[i + 1][j]) } }
        return dp[a.count][b.count]
    }

    /// Replays an edit script and checks it rebuilds both inputs with consistent indices.
    private func assertValid(_ edits: [DiffEngine.Edit<String>], _ a: [String], _ b: [String], file: StaticString = #filePath, line: UInt = #line) {
        var rebuiltA: [String] = [], rebuiltB: [String] = []
        var lastOld = -1, lastNew = -1
        for e in edits {
            switch e.op {
            case .equal:
                rebuiltA.append(e.token); rebuiltB.append(e.token)
                XCTAssertEqual(a[e.oldIndex!], e.token, file: file, line: line); XCTAssertEqual(b[e.newIndex!], e.token, file: file, line: line)
            case .delete: rebuiltA.append(e.token); XCTAssertEqual(a[e.oldIndex!], e.token, file: file, line: line)
            case .insert: rebuiltB.append(e.token); XCTAssertEqual(b[e.newIndex!], e.token, file: file, line: line)
            }
            if let o = e.oldIndex { XCTAssertGreaterThan(o, lastOld, "old indices increase", file: file, line: line); lastOld = o }
            if let n = e.newIndex { XCTAssertGreaterThan(n, lastNew, "new indices increase", file: file, line: line); lastNew = n }
        }
        XCTAssertEqual(rebuiltA, a, file: file, line: line)
        XCTAssertEqual(rebuiltB, b, file: file, line: line)
    }

    func testClassicMyersPaperExample() {
        // Myers 1986: A = ABCABBA, B = CBABAC has shortest edit script of length 5.
        let a = "ABCABBA".map(String.init), b = "CBABAC".map(String.init)
        let edits = DiffEngine.diff(a, b)
        assertValid(edits, a, b)
        XCTAssertEqual(edits.filter { $0.op != .equal }.count, 5)
    }

    func testSmallCases() {
        for (a, b, d) in [("", "", 0), ("abc", "", 3), ("", "abc", 3), ("abc", "abc", 0), ("abc", "abd", 2), ("abc", "xbz", 4), ("kitten", "sitting", 5), ("aaaa", "aa", 2), ("abcdef", "fedcba", 10)] {
            let ta = b.isEmpty && a.isEmpty ? [] : a.map(String.init), tb = b.map(String.init)
            let edits = DiffEngine.diff(a.map(String.init), tb)
            _ = ta
            assertValid(edits, a.map(String.init), tb)
            XCTAssertEqual(edits.filter { $0.op != .equal }.count, d, "\(a) -> \(b)")
        }
    }

    func testRandomisedMinimality() {
        var rng = TT.SplitMix64(seed: 20260101)
        for _ in 0..<300 {
            let n = Int.random(in: 0...25, using: &rng), m = Int.random(in: 0...25, using: &rng)
            let alphabet = Int.random(in: 1...4, using: &rng)
            let a = (0..<n).map { _ in String(Int.random(in: 0..<alphabet, using: &rng)) }
            let b = (0..<m).map { _ in String(Int.random(in: 0..<alphabet, using: &rng)) }
            let edits = DiffEngine.diff(a, b)
            assertValid(edits, a, b)
            XCTAssertEqual(edits.filter { $0.op != .equal }.count, n + m - 2 * lcsLength(a, b), "a=\(a) b=\(b)")
        }
    }

    func testLargeInputWithScatteredChanges() {
        // 20,000 lines, 40 single-line edits spread across the file, including the very first and last lines.
        var rng = TT.SplitMix64(seed: 7)
        let a = (0..<20_000).map { "line \($0) \(UInt32.random(in: 0..<1000, using: &rng))" }
        var b = a
        var changed = Set<Int>([0, 19_999])
        while changed.count < 40 { changed.insert(Int.random(in: 0..<20_000, using: &rng)) }
        for i in changed { b[i] = "CHANGED " + b[i] }
        let start = Date()
        let edits = DiffEngine.diff(a, b)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "large diff must stay fast")
        assertValid(edits, a, b)
        XCTAssertEqual(edits.filter { $0.op != .equal }.count, 80, "40 replaced lines = 40 deletes + 40 inserts, not a whole-file rewrite")
    }

    func testLargeInsertAndDelete() {
        let a = (0..<5_000).map { "row \($0)" }
        var b = a
        b.removeSubrange(1_000..<1_050)
        b.insert(contentsOf: (0..<30).map { "new \($0)" }, at: 3_000)
        b[0] = "first changed"
        b[b.count - 1] = "last changed"
        let edits = DiffEngine.diff(a, b)
        assertValid(edits, a, b)
        XCTAssertEqual(edits.filter { $0.op != .equal }.count, 50 + 30 + 4)
    }

    func testTokenisers() {
        XCTAssertEqual(DiffEngine.lines("a\nb\n"), ["a", "b"])
        XCTAssertEqual(DiffEngine.lines("a\r\nb"), ["a", "b"])
        XCTAssertEqual(DiffEngine.lines("a\n\nb"), ["a", "", "b"])
        XCTAssertEqual(DiffEngine.words("foo bar_baz, qux"), ["foo", " ", "bar_baz", ",", " ", "qux"])
        XCTAssertEqual(DiffEngine.characters("héy"), ["h", "é", "y"])
    }

    func testUnifiedFormat() {
        let a = "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n"
        let b = "one\ntwo\nthree\nFOUR\nfive\nsix\nseven\neight\nnine\nten\n"
        let u = DiffEngine.unified(a, b, nameA: "a.txt", nameB: "b.txt", context: 2)
        XCTAssertEqual(u, "--- a.txt\n+++ b.txt\n@@ -2,5 +2,5 @@\n two\n three\n-four\n+FOUR\n five\n six\n")
        XCTAssertEqual(DiffEngine.unified(a, a), "")
        // Ignore flags.
        XCTAssertEqual(DiffEngine.unified("Hello  World\n", "hello world\n", ignoreWhitespace: true, ignoreCase: true), "")
        XCTAssertNotEqual(DiffEngine.unified("Hello\n", "hello\n"), "")
    }

    func testUnifiedHunkSplitting() {
        let a = (1...40).map(String.init).joined(separator: "\n") + "\n"
        var lines = (1...40).map(String.init)
        lines[1] = "two"; lines[37] = "thirty-eight"
        let u = DiffEngine.unified(a, lines.joined(separator: "\n") + "\n", context: 3)
        XCTAssertEqual(u.components(separatedBy: "\n@@").count, 3, "two distant changes produce two hunks (matches `diff -U3`)")
        XCTAssertTrue(u.contains("@@ -1,5 +1,5 @@"))
        XCTAssertTrue(u.contains("@@ -35,6 +35,6 @@"))
    }

    func testJSONStructuralDiff() throws {
        let a = try JSONParser.parse(#"{"a":1,"b":[1,2,3],"c":{"d":"x"},"e":true}"#)
        let b = try JSONParser.parse(#"{"a":2,"b":[1,2,4],"c":{"d":"x","f":null},"g":1}"#)
        let described = Set(DiffEngine.jsonDiff(a, b).map { "\($0.kind.rawValue) \($0.path)" })
        XCTAssertEqual(described, ["changed $.a", "removed $.b[2]", "added $.b[2]", "added $.c.f", "removed $.e", "added $.g"])
        XCTAssertTrue(DiffEngine.jsonDiff(a, a).isEmpty)
        let t = DiffEngine.jsonDiff(try JSONParser.parse(#"{"a":1}"#), try JSONParser.parse(#"{"a":"1"}"#))
        XCTAssertEqual(t.first?.kind, .typeChanged)
    }

    func testJSONArrayRemovalFollowedByEqualElement() throws {
        // Regression: [1,2,3] -> [1,3] used to report no change because the pending delete was dropped.
        let changes = DiffEngine.jsonDiff(try JSONParser.parse("[1,2,3]"), try JSONParser.parse("[1,3]"))
        XCTAssertEqual(changes.map { "\($0.kind.rawValue) \($0.path) \($0.before ?? "")" }, ["removed $[1] 2"])
        let objs = DiffEngine.jsonDiff(try JSONParser.parse(#"{"l":[{"id":1},{"id":2},{"id":3}]}"#), try JSONParser.parse(#"{"l":[{"id":1},{"id":3}]}"#))
        XCTAssertEqual(objs.map { "\($0.kind.rawValue) \($0.path)" }, ["removed $.l[1]"])
    }

    func testToolModes() async throws {
        let tool = TT.tool("text.diff")
        let line = try await tool.run(ToolInput(.text("a\nb\nc"), secondary: .text("a\nB\nc")), options: [:])
        XCTAssertEqual(TT.meta(line, "Added"), "1"); XCTAssertEqual(TT.meta(line, "Removed"), "1")
        XCTAssertTrue(line.text.contains("-b") && line.text.contains("+B"))
        let same = try await tool.run(ToolInput(.text("same"), secondary: .text("same")), options: [:])
        XCTAssertEqual(same.text, "No differences"); XCTAssertEqual(same.isValid, true)
        let word = try await tool.run(ToolInput(.text("the quick fox"), secondary: .text("the slow fox")), options: ["granularity": .string("word")])
        XCTAssertEqual(word.text, "the [-quick-]{+slow+} fox")
        let chr = try await tool.run(ToolInput(.text("cat"), secondary: .text("cut")), options: ["granularity": .string("char")])
        XCTAssertEqual(chr.text, "c[-a-]{+u+}t")
        let json = try await tool.run(ToolInput(.text(#"{"a":1,"b":2}"#), secondary: .text(#"{"b":3}"#)), options: ["granularity": .string("json")])
        XCTAssertEqual(TT.meta(json, "Changes"), "2")
        let ic = try await tool.run(ToolInput(.text("Hello"), secondary: .text("hello")), options: ["ignoreCase": .bool(true)])
        XCTAssertEqual(ic.text, "No differences")
    }
}
