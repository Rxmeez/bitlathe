import XCTest
@testable import BitlatheCore
@testable import BitlatheTools

final class UIReviewRegressionTests: XCTestCase {
    @MainActor
    func testEverydayToolRanksFirstAmongEqualPrefixMatches() {
        let registry = ToolRegistry()
        for tool in ToolCatalog.all { registry.register(tool) }
        XCTAssertEqual(registry.search("base").first?.id, "base64.text")
        XCTAssertEqual(registry.search("json").first?.id, "json.format")
    }

    func testFieldConditionedOnMissingOptionIsVisible() {
        // ERB/SCSS/LESS/TS/GraphQL reuse "indent, only when mode = format" but have no mode option.
        let indent = OptionField.picker("indent", "Indent", [.init("2", "2")], default: "2", visibleWhen: ("mode", ["format"]))
        XCTAssertTrue(indent.isVisible(among: [indent]) { _ in "" })
        let mode = OptionField.picker("mode", "Mode", [.init("format", "F"), .init("minify", "M")], default: "format")
        XCTAssertTrue(indent.isVisible(among: [mode, indent]) { _ in "format" })
        XCTAssertFalse(indent.isVisible(among: [mode, indent]) { _ in "minify" })
    }
}
