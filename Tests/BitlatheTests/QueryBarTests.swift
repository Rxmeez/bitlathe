import XCTest
@testable import BitlatheUI

@MainActor
final class QueryBarTests: XCTestCase {
    func testDrillDownStepsFollowTheDocument() {
        let json = """
        {
          "user": { "id": 42, "roles": ["admin", "dev"] },
          "active": true,
          "odd key": 1
        }
        """
        XCTAssertEqual(QueryBar.nextSteps(in: json), [".user", ".active"], "document order; keys that need quoting are left out")
        XCTAssertEqual(QueryBar.nextSteps(in: #"["admin", "dev"]"#), ["[0]", "[*]"])
        XCTAssertEqual(QueryBar.nextSteps(in: "[]"), [])
        XCTAssertEqual(QueryBar.nextSteps(in: "42"), [], "nothing further inside a number")
        XCTAssertEqual(QueryBar.nextSteps(in: "name: Bitlathe"), [], "not JSON")
        XCTAssertEqual(QueryBar.nextSteps(in: ""), [])
    }
}
