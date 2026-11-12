import Foundation
import BitlatheCore

/// Engine: parses CSV and reports column statistics. The custom view renders a sortable, filterable table.
public struct CSVViewerTool: DevTool {
    public static let id = "csv.viewer"
    public static let name = "CSV Viewer"
    public static let summary = "View CSV/TSV as a sortable, filterable table with column statistics"
    public static let category = ToolCategory.convert
    public static let symbol = "tablecells.badge.ellipsis"
    public static let keywords = ["csv", "tsv", "table", "spreadsheet", "columns", "stats", "viewer"]
    public static let io = ToolIO.text(.csv, .plain)
    public static let samples = [ToolSample("Sales", "region,product,units,price,date\nNorth,Widget,12,9.99,2026-01-03\nSouth,Gadget,7,24.5,2026-01-04\nNorth,Gadget,3,24.5,2026-01-05\nEast,Widget,20,9.99,2026-01-06\nWest,Doohickey,1,99,2026-01-07")]
    public static let optionFields: [OptionField] = [
        .picker("delimiter", "Delimiter", [.init("auto", "Auto"), .init(",", "Comma"), .init("\t", "Tab"), .init(";", "Semicolon"), .init("|", "Pipe")], default: "auto"),
        .toggle("header", "First row is header", default: true),
    ]
    public struct Options: ToolOptions {
        public var delimiter = "auto"
        public var header = true
        public init() {}
    }
    public init() {}

    public struct ColumnStats: Sendable, Equatable {
        public var name: String
        public var kind: String
        public var nonEmpty: Int
        public var unique: Int
        public var min: String?
        public var max: String?
        public var mean: Double?
        public var sum: Double?
    }

    public static func parse(_ text: String, options: Options) throws -> CSV.Table {
        try CSV.parse(text, delimiter: options.delimiter == "auto" ? nil : Character(options.delimiter), hasHeader: options.header)
    }

    public static func stats(_ table: CSV.Table) -> [ColumnStats] {
        table.header.indices.map { c in
            let values = table.rows.map { c < $0.count ? $0[c] : "" }
            let nonEmpty = values.filter { !$0.isEmpty }
            let numbers = nonEmpty.compactMap { Double($0.replacingOccurrences(of: ",", with: "")) }
            let isNumeric = !nonEmpty.isEmpty && numbers.count == nonEmpty.count
            let isDate = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.range(of: "^\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil }
            let isBool = !nonEmpty.isEmpty && nonEmpty.allSatisfy { ["true", "false", "yes", "no", "0", "1"].contains($0.lowercased()) }
            let kind = isNumeric ? (numbers.allSatisfy { $0 == $0.rounded() } ? "integer" : "number") : (isDate ? "date" : (isBool ? "boolean" : "text"))
            var s = ColumnStats(name: table.header[c], kind: kind, nonEmpty: nonEmpty.count, unique: Set(nonEmpty).count)
            if isNumeric {
                s.min = numbers.min().map(format)
                s.max = numbers.max().map(format)
                s.sum = numbers.reduce(0, +)
                s.mean = numbers.isEmpty ? nil : s.sum! / Double(numbers.count)   // swiftlint:disable:this force_unwrapping
            } else {
                s.min = nonEmpty.min()
                s.max = nonEmpty.max()
            }
            return s
        }
    }

    static func format(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.4g", d) }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let table = try Self.parse(text, options: options)
        let stats = Self.stats(table)
        var rows: [MetaRow] = [MetaRow("Rows", "\(table.rows.count)"), MetaRow("Columns", "\(table.header.count)"), MetaRow("Delimiter", table.delimiter == "\t" ? "tab" : String(table.delimiter))]
        for s in stats {
            var desc = "\(s.kind) · \(s.nonEmpty) filled · \(s.unique) unique"
            if let mn = s.min, let mx = s.max { desc += " · \(mn) … \(mx)" }
            if let mean = s.mean { desc += " · mean \(Self.format(mean))" }
            if let sum = s.sum { desc += " · sum \(Self.format(sum))" }
            rows.append(MetaRow(s.name, desc))
        }
        // Text output: aligned table for CLI / copy.
        let widths = table.header.indices.map { c in max(table.header[c].count, table.rows.prefix(500).map { c < $0.count ? $0[c].count : 0 }.max() ?? 0) }
        func line(_ cells: [String]) -> String { cells.enumerated().map { $0.element.padding(toLength: min(widths[$0.offset], 40), withPad: " ", startingAt: 0) }.joined(separator: " │ ") }
        var out = line(table.header) + "\n" + widths.map { String(repeating: "─", count: min($0, 40)) }.joined(separator: "─┼─")
        for r in table.rows.prefix(500) { out += "\n" + line(r) }
        if table.rows.count > 500 { out += "\n… \(table.rows.count - 500) more rows" }
        return ToolOutput(text: out, metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard let csv = JSONCSVTool.detect(s), csv.confidence >= 0.65, s.split(separator: "\n").count >= 3 else { return nil }
        return DetectionScore(0.7, "Tabular data")
    }
}
