import Foundation
import BitlatheCore

/// RFC 4180 CSV/TSV parser and writer with delimiter sniffing.
public enum CSV {
    public struct Table: Sendable, Equatable {
        public var header: [String]
        public var rows: [[String]]
        public var delimiter: Character
    }

    public static func sniffDelimiter(_ text: String) -> Character {
        let sample = text.prefix(4096)
        let firstLine = sample.split(separator: "\n").first.map(String.init) ?? String(sample)
        let candidates: [Character] = [",", "\t", ";", "|"]
        var best: Character = ","
        var bestCount = -1
        for c in candidates {
            let n = firstLine.filter { $0 == c }.count
            if n > bestCount { best = c; bestCount = n }
        }
        return best
    }

    public static func parse(_ text: String, delimiter: Character? = nil, hasHeader: Bool = true) throws -> Table {
        let delim = delimiter ?? sniffDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex
        var line = 1
        var lastWasCR = false
        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" { field.append("\""); i = next }
                    else { inQuotes = false }
                } else {
                    field.append(c)
                    if c == "\n" { line += 1 }
                }
            } else {
                if c == "\"" {
                    if field.isEmpty { inQuotes = true }
                    else { field.append(c) }
                } else if c == delim {
                    row.append(field)
                    field = ""
                } else if c == "\n" || c == "\r\n" {
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                    line += 1
                } else if c == "\r" {
                    lastWasCR = true
                    row.append(field); rows.append(row); row = []; field = ""; line += 1
                } else {
                    field.append(c)
                }
            }
            i = text.index(after: i)
        }
        _ = lastWasCR
        if inQuotes { throw ToolError("Unterminated quoted field", line: line) }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        rows = rows.filter { !($0.count == 1 && $0[0].isEmpty) }
        guard !rows.isEmpty else { return Table(header: [], rows: [], delimiter: delim) }
        let width = rows.map(\.count).max() ?? 0
        rows = rows.map { $0 + Array(repeating: "", count: width - $0.count) }
        if hasHeader {
            let header = rows.removeFirst()
            return Table(header: header.enumerated().map { $0.element.isEmpty ? "column\($0.offset + 1)" : $0.element }, rows: rows, delimiter: delim)
        }
        return Table(header: (0..<width).map { "column\($0 + 1)" }, rows: rows, delimiter: delim)
    }

    static func quote(_ s: String, delimiter: Character) -> String {
        if s.contains(delimiter) || s.contains("\"") || s.contains("\n") || s.contains("\r") || s.hasPrefix(" ") || s.hasSuffix(" ") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    public static func write(header: [String], rows: [[String]], delimiter: Character = ",") -> String {
        let d = String(delimiter)
        var out = header.map { quote($0, delimiter: delimiter) }.joined(separator: d)
        for r in rows { out += "\n" + r.map { quote($0, delimiter: delimiter) }.joined(separator: d) }
        return out
    }

    /// Infer a JSON value from a CSV cell.
    static func typed(_ s: String) -> JSONValue {
        if s.isEmpty { return .null }
        switch s.lowercased() {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default: break
        }
        if s.range(of: "^-?(0|[1-9]\\d*)(\\.\\d+)?([eE][+-]?\\d+)?$", options: .regularExpression) != nil, s.count < 18 { return .number(s) }
        return .string(s)
    }
}
