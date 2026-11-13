import XCTest
@testable import BitlatheTools

final class PerformanceDiffTests: XCTestCase {
    private struct LCG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func lcsLength(_ a: [Int], _ b: [Int]) -> Int {
        var prev = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var cur = [Int](repeating: 0, count: b.count + 1)
            for (j, y) in b.enumerated() {
                cur[j + 1] = x == y ? prev[j] + 1 : max(prev[j + 1], cur[j])
            }
            prev = cur
        }
        return prev[b.count]
    }

    /// Replays the edit script and checks it turns `a` into `b`; returns the number of non-equal edits.
    @discardableResult
    private func verify(_ edits: [DiffEngine.Edit<Int>], _ a: [Int], _ b: [Int], file: StaticString = #filePath, line: UInt = #line) -> Int {
        var rebuilt: [Int] = [], old: [Int] = [], changes = 0
        for e in edits {
            switch e.op {
            case .equal: rebuilt.append(e.token); old.append(e.token)
            case .insert: rebuilt.append(e.token); changes += 1
            case .delete: old.append(e.token); changes += 1
            }
        }
        XCTAssertEqual(rebuilt, b, file: file, line: line)
        XCTAssertEqual(old, a, file: file, line: line)
        return changes
    }

    func testRandomSmallCasesAreMinimalAndCorrect() {
        var rng = LCG(state: 42)
        for _ in 0..<600 {
            let n = Int.random(in: 0...30, using: &rng), m = Int.random(in: 0...30, using: &rng)
            let alphabet = Int.random(in: 1...6, using: &rng)
            let a = (0..<n).map { _ in Int.random(in: 0..<alphabet, using: &rng) }
            let b = (0..<m).map { _ in Int.random(in: 0..<alphabet, using: &rng) }
            let changes = verify(DiffEngine.diff(a, b), a, b)
            XCTAssertEqual(changes, n + m - 2 * lcsLength(a, b), "a=\(a) b=\(b)")
        }
    }

    private func scatteredFixture(lines: Int, edits: Int) -> ([String], [String]) {
        let a = (0..<lines).map { "line \($0) payload \($0 * 7919 % 10007)" }
        var b = a
        // Replace every (lines/edits)-th line, starting near the top and ending near the bottom.
        let step = lines / edits
        for k in 0..<edits { b[3 + k * step] = "CHANGED \(k)" }
        return (a, b)
    }

    func testTenThousandLineScatteredEditsIsExactAndFast() {
        let (a, b) = scatteredFixture(lines: 10_000, edits: 100)
        let start = ContinuousClock.now
        let edits = DiffEngine.diff(a, b)
        let elapsed = ContinuousClock.now - start
        XCTAssertEqual(edits.filter { $0.op == .delete }.count, 100)
        XCTAssertEqual(edits.filter { $0.op == .insert }.count, 100)
        XCTAssertEqual(edits.filter { $0.op == .equal }.count, 9_900)
        XCTAssertLessThan(elapsed, .seconds(1), "diff took \(elapsed)")
        print("PERF diff 10k x 10k, 100 scattered edits: \(elapsed)")
    }

    func testInsertionsAndDeletionsNearBothEnds() {
        let a = (0..<6_000).map { "row \($0)" }
        var b = a
        b.removeSubrange(10..<20)
        b.insert(contentsOf: (0..<7).map { "new \($0)" }, at: 3_000)
        b.removeLast(5)
        b.append(contentsOf: ["tail A", "tail B"])
        let edits = DiffEngine.diff(a, b)
        XCTAssertEqual(edits.filter { $0.op == .delete }.count, 10 + 5)
        XCTAssertEqual(edits.filter { $0.op == .insert }.count, 7 + 2)
    }

    func testCompletelyDifferentTenThousandLinesStaysBounded() {
        let a = (0..<10_000).map { "a\($0)" }, b = (0..<10_000).map { "b\($0)" }
        let start = ContinuousClock.now
        let edits = DiffEngine.diff(a, b)
        let elapsed = ContinuousClock.now - start
        XCTAssertEqual(edits.filter { $0.op == .equal }.count, 0)
        XCTAssertEqual(edits.count, 20_000)
        XCTAssertLessThan(elapsed, .seconds(2), "diff took \(elapsed)")
        print("PERF diff 10k x 10k fully different: \(elapsed)")
    }
}
