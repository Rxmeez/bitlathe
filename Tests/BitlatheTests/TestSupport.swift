import XCTest
import Foundation
import BitlatheCore
@testable import BitlatheTools

/// Shared helpers for the engine tests.
enum TT {
    static func tool(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> AnyTool {
        guard let t = ToolCatalog.all.first(where: { $0.id == id }) else {
            XCTFail("Tool \(id) missing from catalog", file: file, line: line)
            return ToolCatalog.all[0]
        }
        return t
    }

    static func run(_ id: String, _ text: String, _ options: OptionValues = [:]) async throws -> ToolOutput {
        try await tool(id).run(text: text, options: options)
    }

    static func meta(_ out: ToolOutput, _ label: String) -> String? {
        out.metadata.first { $0.label == label }?.value
    }

    static func facet(_ out: ToolOutput, _ title: String) -> String? {
        out.facets.first { $0.title == title }?.payload.text
    }

    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    static func fixture(_ path: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let base = Bundle.module.resourceURL?.appendingPathComponent("Fixtures"),
              let s = try? String(contentsOf: base.appendingPathComponent(path), encoding: .utf8) else {
            XCTFail("Missing fixture \(path)", file: file, line: line)
            return ""
        }
        return s
    }
}
