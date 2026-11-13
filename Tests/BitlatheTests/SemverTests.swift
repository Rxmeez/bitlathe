import XCTest
import BitlatheCore
@testable import BitlatheTools

final class SemverTests: XCTestCase {
    private func v(_ s: String) -> Semver { Semver(s)! }

    private func sat(_ range: String, _ version: String, pre: Bool = false) throws -> Bool {
        try SemverRange(range).satisfies(v(version), includePrerelease: pre)
    }

    func testSemverOrgPrecedenceChain() {
        // The exact precedence example from semver.org section 11.
        let chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "2.0.0", "2.1.0", "2.1.1"]
        for (a, b) in zip(chain, chain.dropFirst()) { XCTAssertLessThan(v(a), v(b), "\(a) < \(b)") }
        XCTAssertEqual(chain.shuffled().compactMap(Semver.init).sorted().map(\.description), chain)
    }

    func testNumericNotLexicographic() {
        XCTAssertLessThan(v("1.2.0"), v("1.10.0"))
        XCTAssertLessThan(v("1.9.9"), v("1.10.0"))
        XCTAssertLessThan(v("2.0.0"), v("10.0.0"))
    }

    func testBuildMetadataIgnoredForPrecedence() {
        XCTAssertEqual(v("1.0.0+build.1"), v("1.0.0+build.2"))
        XCTAssertFalse(v("1.0.0+a") < v("1.0.0+b"))
    }

    func testParsing() {
        let p = v("v1.2.3-beta.4+exp.sha.5114f85")
        XCTAssertEqual([p.major, p.minor, p.patch], [1, 2, 3])
        XCTAssertEqual(p.prerelease, ["beta", "4"])
        XCTAssertEqual(p.build, ["exp", "sha", "5114f85"])
        XCTAssertNil(Semver("1.2"))
        XCTAssertNil(Semver("not.a.version"))
        XCTAssertNil(Semver("1.2.3.4"))
    }

    func testBumps() {
        XCTAssertEqual(v("1.2.3").bumped(.patch).description, "1.2.4")
        XCTAssertEqual(v("1.2.3").bumped(.minor).description, "1.3.0")
        XCTAssertEqual(v("1.2.3").bumped(.major).description, "2.0.0")
    }

    // MARK: npm range semantics (node-semver README)

    func testCaret() throws {
        XCTAssertTrue(try sat("^1.2.3", "1.2.3")); XCTAssertTrue(try sat("^1.2.3", "1.9.0")); XCTAssertFalse(try sat("^1.2.3", "2.0.0")); XCTAssertFalse(try sat("^1.2.3", "1.2.2"))
        XCTAssertTrue(try sat("^0.2.3", "0.2.9")); XCTAssertFalse(try sat("^0.2.3", "0.3.0"))
        XCTAssertTrue(try sat("^0.0.3", "0.0.3")); XCTAssertFalse(try sat("^0.0.3", "0.0.4"))
        XCTAssertTrue(try sat("^1.2.x", "1.9.9")); XCTAssertFalse(try sat("^1.2.x", "2.0.0")); XCTAssertFalse(try sat("^1.2.x", "1.1.9"))
        XCTAssertTrue(try sat("^0.0.x", "0.0.9")); XCTAssertFalse(try sat("^0.0.x", "0.1.0"))
        XCTAssertTrue(try sat("^1.x", "1.5.0")); XCTAssertFalse(try sat("^1.x", "2.0.0"))
        XCTAssertTrue(try sat("^0.x", "0.9.0")); XCTAssertFalse(try sat("^0.x", "1.0.0"))
    }

    func testTilde() throws {
        XCTAssertTrue(try sat("~1.2.3", "1.2.9")); XCTAssertFalse(try sat("~1.2.3", "1.3.0")); XCTAssertFalse(try sat("~1.2.3", "1.2.2"))
        XCTAssertTrue(try sat("~1.2", "1.2.0")); XCTAssertFalse(try sat("~1.2", "1.3.0"))
        XCTAssertTrue(try sat("~1", "1.9.9")); XCTAssertFalse(try sat("~1", "2.0.0"))
        XCTAssertTrue(try sat("~0.2.3", "0.2.4")); XCTAssertFalse(try sat("~0.2.3", "0.3.0"))
        XCTAssertTrue(try sat("~0", "0.9.0")); XCTAssertFalse(try sat("~0", "1.0.0"))
    }

    func testXRangesAndStar() throws {
        XCTAssertTrue(try sat("1.2.x", "1.2.9")); XCTAssertFalse(try sat("1.2.x", "1.3.0"))
        XCTAssertTrue(try sat("1.2.*", "1.2.0"))
        XCTAssertTrue(try sat("1.x", "1.99.0")); XCTAssertFalse(try sat("1.x", "2.0.0"))
        XCTAssertTrue(try sat("*", "9.9.9")); XCTAssertTrue(try sat("", "0.0.1")); XCTAssertTrue(try sat("x", "3.2.1"))
        XCTAssertTrue(try sat("1", "1.5.5")); XCTAssertFalse(try sat("1", "2.0.0"))
    }

    func testComparatorsAndHyphen() throws {
        XCTAssertTrue(try sat(">=1.2.3 <2.0.0", "1.5.0")); XCTAssertFalse(try sat(">=1.2.3 <2.0.0", "2.0.0"))
        XCTAssertTrue(try sat(">1.2.3", "1.2.4")); XCTAssertFalse(try sat(">1.2.3", "1.2.3"))
        XCTAssertTrue(try sat("<=1.2.3", "1.2.3")); XCTAssertFalse(try sat("<1.2.3", "1.2.3"))
        XCTAssertTrue(try sat("=1.2.3", "1.2.3")); XCTAssertFalse(try sat("1.2.3", "1.2.4"))
        // Hyphen ranges.
        XCTAssertTrue(try sat("1.2.3 - 2.3.4", "2.3.4")); XCTAssertFalse(try sat("1.2.3 - 2.3.4", "2.3.5"))
        XCTAssertTrue(try sat("1.2 - 2.3.4", "1.2.0")); XCTAssertFalse(try sat("1.2 - 2.3.4", "1.1.9"))
        XCTAssertTrue(try sat("1.2.3 - 2.3", "2.3.99")); XCTAssertFalse(try sat("1.2.3 - 2.3", "2.4.0"))
        XCTAssertTrue(try sat("1 - 2", "2.9.9")); XCTAssertFalse(try sat("1 - 2", "3.0.0"))
    }

    func testUnion() throws {
        XCTAssertTrue(try sat("^1.0.0 || ^3.0.0", "3.4.0")); XCTAssertTrue(try sat("^1.0.0 || ^3.0.0", "1.4.0"))
        XCTAssertFalse(try sat("^1.0.0 || ^3.0.0", "2.0.0"))
    }

    func testPrereleaseRules() throws {
        // A prerelease only satisfies a range if a comparator on the same [major,minor,patch] tuple has a prerelease tag.
        XCTAssertTrue(try sat(">=1.2.3-beta.2 <2.0.0", "1.2.3-beta.4"))
        XCTAssertFalse(try sat(">=1.2.3-beta.2 <2.0.0", "1.2.4-beta.2"))
        XCTAssertFalse(try sat("^1.2.3", "1.3.0-alpha"))
        XCTAssertTrue(try sat("^1.2.3", "1.3.0-alpha", pre: true))
        XCTAssertFalse(try sat("^1.2.3", "1.2.3-alpha"))
        XCTAssertFalse(try sat("*", "1.0.0-rc.1"))
    }

    func testPrereleaseTagContainingXIsNotAWildcard() throws {
        // Regression: a tag such as "-next" contains an "x" and used to be treated as an x-range.
        XCTAssertTrue(try sat("1.2.3-next", "1.2.3-next"))
        XCTAssertFalse(try sat("1.2.3-next", "1.2.4"))
        XCTAssertFalse(try sat("1.2.3-next", "1.2.3"))
    }

    func testInvalidRange() {
        XCTAssertThrowsError(try SemverRange("^^banana"))
    }

    // MARK: tool

    func testToolSortAndRange() async throws {
        let sorted = try await TT.run("semver.compare", "1.10.0\n1.2.0\n1.2.0-beta.2\n1.2.0-beta.11\n2.0.0-rc.1\n1.2.0+build.5")
        let lines = sorted.text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "1.2.0-beta.2")
        XCTAssertEqual(lines.last, "2.0.0-rc.1")
        XCTAssertLessThan(lines.firstIndex(of: "1.2.0-beta.11")!, lines.firstIndex(of: "1.10.0")!)
        XCTAssertEqual(TT.meta(sorted, "Highest stable"), "1.10.0")

        let r = try await TT.run("semver.compare", "1.2.3\n1.9.0\n2.0.0\n0.9.0", ["mode": .string("range"), "range": .string("^1.2.3")])
        XCTAssertEqual(TT.meta(r, "1.2.3"), "satisfies")
        XCTAssertEqual(TT.meta(r, "2.0.0"), "does not satisfy")
        XCTAssertEqual(TT.meta(r, "Max satisfying"), "1.9.0")
    }
}
