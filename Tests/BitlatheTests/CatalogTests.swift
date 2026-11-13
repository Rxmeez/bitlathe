import XCTest
import AppKit
import BitlatheCore
@testable import BitlatheTools

final class CatalogTests: XCTestCase {
    /// Samples that are broken on purpose (they demonstrate the error display).
    private let intentionallyBroken: Set<String> = ["json.format/Broken JSON"]

    func testEveryToolHasUniqueIDAndMetadata() {
        let all = ToolCatalog.all
        XCTAssertGreaterThan(all.count, 80)
        var seen = Set<String>()
        for t in all {
            XCTAssertTrue(seen.insert(t.id).inserted, "duplicate tool id \(t.id)")
            XCTAssertFalse(t.id.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(t.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(t.id) has an empty name")
            XCTAssertFalse(t.summary.trimmingCharacters(in: .whitespaces).isEmpty, "\(t.id) has an empty summary")
            XCTAssertFalse(t.keywords.isEmpty, "\(t.id) has no keywords")
        }
        XCTAssertEqual(Set(all.map(\.name)).count, all.count, "tool names should be unique")
    }

    func testEverySymbolIsAValidSFSymbol() {
        for t in ToolCatalog.all {
            XCTAssertNotNil(NSImage(systemSymbolName: t.symbol, accessibilityDescription: nil), "\(t.id): invalid SF Symbol '\(t.symbol)'")
        }
    }

    func testCategoriesAreCoveredAndTargetCategoriesPopulated() {
        let cats = Dictionary(grouping: ToolCatalog.all, by: \.category)
        for c in ToolCategory.allCases where c != .scripting {   // scripting is filled by user scripts at runtime
            XCTAssertFalse(cats[c, default: []].isEmpty, "category \(c) has no tools") }
        XCTAssertTrue(cats[.format, default: []].contains { $0.id == "json.format" })
        XCTAssertTrue(cats[.convert, default: []].contains { $0.id == "convert.yaml-json" })
        XCTAssertTrue(cats[.encode, default: []].contains { $0.id == "base64.text" })
    }

    func testOptionFieldsAreConsistent() {
        for t in ToolCatalog.all {
            var keys = Set<String>()
            for f in t.optionFields {
                XCTAssertTrue(keys.insert(f.key).inserted, "\(t.id): duplicate option key \(f.key)")
            }
        }
    }

    /// Every sample's declared options must be accepted by the tool, and the sample must run.
    func testEverySampleRunsWithoutThrowing() async throws {
        for t in ToolCatalog.all {
            for s in t.samples {
                let key = "\(t.id)/\(s.title)"
                // Image / OCR tools have no text samples worth running here.
                if t.category == .media { continue }
                // bcrypt / scrypt cost factors take several seconds in debug builds; covered by the password-hash tests.
                if t.id == "password.hash" { continue }
                do {
                    let out = try await t.run(text: s.input, options: s.options)
                    if intentionallyBroken.contains(key) { XCTFail("\(key) was expected to throw") }
                    _ = out
                } catch {
                    if !intentionallyBroken.contains(key) { XCTFail("sample \(key) threw: \(error)") }
                }
            }
        }
    }

    func testBrokenJSONSampleThrowsWithLocation() async throws {
        let sample = try XCTUnwrap(JSONFormatTool.samples.first { $0.title == "Broken JSON" })
        let e = await T.error(JSONFormatTool.self, sample.input, sample.options)
        XCTAssertNotNil(e?.line)
        XCTAssertNotNil(e?.column)
    }
}
