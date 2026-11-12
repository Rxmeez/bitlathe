import Foundation
import BitlatheCore

public struct LineToolsTool: DevTool {
    public static let id = "text.lines"
    public static let name = "Line Tools"
    public static let summary = "Sort, dedupe, reverse, shuffle, trim, number, prefix and join lines"
    public static let category = ToolCategory.format
    public static let symbol = "list.number"
    public static let keywords = ["lines", "sort", "unique", "dedupe", "reverse", "shuffle", "trim", "join", "split", "prefix", "suffix", "number"]
    public static let samples = [ToolSample("Unsorted", "banana\napple\nCherry\napple\nfile10\nfile2\n\nfile1")]
    public static let optionFields: [OptionField] = [
        .picker("operation", "Operation", [
            .init("sort", "Sort"), .init("dedupe", "Remove duplicates"), .init("reverse", "Reverse"), .init("shuffle", "Shuffle"),
            .init("trim", "Trim whitespace"), .init("removeEmpty", "Remove empty lines"), .init("number", "Number lines"),
            .init("affix", "Add prefix / suffix"), .init("join", "Join lines"), .init("split", "Split by delimiter"),
            .init("stats", "Count"),
        ], default: "sort"),
        .picker("sortMode", "Order", [.init("alpha", "A → Z"), .init("alphaDesc", "Z → A"), .init("natural", "Natural"), .init("numeric", "Numeric"), .init("length", "By length"), .init("lengthDesc", "By length ↓")], default: "alpha", visibleWhen: ("operation", ["sort"])),
        .toggle("caseInsensitive", "Ignore case", default: true, visibleWhen: ("operation", ["sort", "dedupe"])),
        .toggle("keepFirstBlank", "Keep blanks", visibleWhen: ("operation", ["sort"])),
        .text("prefix", "Prefix", placeholder: "- ", visibleWhen: ("operation", ["affix"])),
        .text("suffix", "Suffix", placeholder: ",", visibleWhen: ("operation", ["affix"])),
        .text("delimiter", "Delimiter", placeholder: ", ", default: ", ", visibleWhen: ("operation", ["join", "split"])),
        .stepper("startAt", "Start", min: 0, max: 100000, default: 1, visibleWhen: ("operation", ["number"])),
    ]
    public struct Options: ToolOptions {
        public var operation = "sort"
        public var sortMode = "alpha"
        public var caseInsensitive = true
        public var keepFirstBlank = false
        public var prefix = ""
        public var suffix = ""
        public var delimiter = ", "
        public var startAt = 1
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.isEmpty else { throw ToolError.emptyInput }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).removingSuffix("\r") }
        if lines.last == "" && text.hasSuffix("\n") { lines.removeLast() }
        let original = lines.count
        var meta: [MetaRow] = []
        switch options.operation {
        case "sort":
            let blanks = lines.filter(\.isEmpty)
            var items = options.keepFirstBlank ? lines : lines.filter { !$0.isEmpty }
            switch options.sortMode {
            case "alpha", "alphaDesc":
                items.sort { a, b in
                    let r = options.caseInsensitive ? a.caseInsensitiveCompare(b) : a.compare(b)
                    return r == .orderedAscending
                }
                if options.sortMode == "alphaDesc" { items.reverse() }
            case "natural":
                items.sort { a, b in a.compare(b, options: [.numeric, options.caseInsensitive ? .caseInsensitive : []]) == .orderedAscending }
            case "numeric":
                items.sort { a, b in
                    let x = Self.leadingNumber(a) ?? .greatestFiniteMagnitude
                    let y = Self.leadingNumber(b) ?? .greatestFiniteMagnitude
                    return x == y ? a < b : x < y
                }
            case "length": items.sort { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
            case "lengthDesc": items.sort { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
            default: break
            }
            lines = items
            if !options.keepFirstBlank, !blanks.isEmpty { meta.append(MetaRow("Blank lines removed", "\(blanks.count)")) }
        case "dedupe":
            var seen = Set<String>()
            lines = lines.filter { l in
                let key = options.caseInsensitive ? l.lowercased() : l
                return seen.insert(key).inserted
            }
            meta.append(MetaRow("Duplicates removed", "\(original - lines.count)"))
        case "reverse": lines.reverse()
        case "shuffle": lines.shuffle()
        case "trim": lines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        case "removeEmpty":
            lines = lines.filter { !$0.trimmed().isEmpty }
            meta.append(MetaRow("Removed", "\(original - lines.count)"))
        case "number":
            let width = String(options.startAt + lines.count - 1).count
            lines = lines.enumerated().map { i, l in String(options.startAt + i).padding(toLength: width, withPad: " ", startingAt: 0).replacingOccurrences(of: " ", with: " ") + "  " + l }
            lines = lines.enumerated().map { i, _ in
                let n = String(options.startAt + i)
                return String(repeating: " ", count: width - n.count) + n + "  " + lines[i].drop { $0 != " " }.dropFirst(2)
            }
        case "affix": lines = lines.map { options.prefix + $0 + options.suffix }
        case "join":
            let delim = options.delimiter.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
            return ToolOutput(text: lines.joined(separator: delim), metadata: [MetaRow("Lines joined", "\(lines.count)")])
        case "split":
            let delim = options.delimiter.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
            guard !delim.isEmpty else { throw ToolError("Delimiter is empty") }
            lines = text.components(separatedBy: delim).map { $0.trimmingCharacters(in: .whitespaces) }
        case "stats":
            let words = text.split { $0.isWhitespace || $0.isNewline }.count
            let chars = text.count
            let nonEmpty = lines.filter { !$0.trimmed().isEmpty }.count
            let unique = Set(lines).count
            let longest = lines.map(\.count).max() ?? 0
            let rows = [MetaRow("Lines", "\(original)"), MetaRow("Non-empty lines", "\(nonEmpty)"), MetaRow("Unique lines", "\(unique)"),
                        MetaRow("Words", "\(words)"), MetaRow("Characters", "\(chars)"), MetaRow("Bytes (UTF-8)", "\(text.utf8.count)"),
                        MetaRow("Longest line", "\(longest) chars")]
            return ToolOutput(text: "", metadata: rows)
        default: break
        }
        meta.insert(MetaRow("Lines", "\(original) → \(lines.count)"), at: 0)
        return ToolOutput(text: lines.joined(separator: "\n"), metadata: meta)
    }

    static func leadingNumber(_ s: String) -> Double? {
        guard let r = s.range(of: "-?\\d+(\\.\\d+)?", options: .regularExpression) else { return nil }
        return Double(s[r])
    }
}
