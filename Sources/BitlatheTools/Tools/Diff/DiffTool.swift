import Foundation
import BitlatheCore

public struct DiffTool: DevTool {
    public static let id = "text.diff"
    public static let name = "Text Diff"
    public static let summary = "Compare two texts line by line, by word or by character — plus a structural JSON diff"
    public static let category = ToolCategory.inspect
    public static let symbol = "arrow.left.and.right.text.vertical"
    public static let keywords = ["diff", "compare", "difference", "patch", "unified", "json diff", "merge", "changes"]
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: true, dualInput: true, inputLanguage: .plain, outputLanguage: .diff)
    public static let samples = [ToolSample("Config change", "server:\n  host: localhost\n  port: 8080\n  debug: true\nfeatures:\n  - auth\n  - search")]
    public static let optionFields: [OptionField] = [
        .segmented("granularity", "Compare", [.init("line", "Lines"), .init("word", "Words"), .init("char", "Characters"), .init("json", "JSON")], default: "line"),
        .toggle("ignoreWhitespace", "Ignore whitespace"),
        .toggle("ignoreCase", "Ignore case"),
        .toggle("ignoreOrder", "Ignore array order", visibleWhen: ("granularity", ["json"])),
        .stepper("context", "Context", min: 0, max: 20, default: 3, visibleWhen: ("granularity", ["line"]), advanced: true),
    ]
    public struct Options: ToolOptions {
        public var granularity = "line"
        public var ignoreWhitespace = false
        public var ignoreCase = false
        public var ignoreOrder = false
        public var context = 3
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let a = input.text
        let b = input.secondary?.text ?? ""
        guard !a.isEmpty || !b.isEmpty else { throw ToolError.emptyInput }
        if options.granularity == "json" {
            let ja = try JSONParser.parse(a.isEmpty ? "null" : a, options: .json5)
            let jb = try JSONParser.parse(b.isEmpty ? "null" : b, options: .json5)
            let changes = DiffEngine.jsonDiff(ja, jb, ignoreOrder: options.ignoreOrder)
            let rows = changes.map { c -> MetaRow in
                let style: MetaRow.Style = switch c.kind {
                case .added: .success
                case .removed: .danger
                case .typeChanged: .warning
                default: .plain
                }
                let value: String = switch c.kind {
                case .added: "+ \(c.after ?? "")"
                case .removed: "− \(c.before ?? "")"
                case .moved: c.before ?? ""
                default: "\(c.before ?? "") → \(c.after ?? "")"
                }
                return MetaRow("\(c.kind.rawValue)  \(c.path)", value, style: style)
            }
            let text = changes.isEmpty ? "No differences" : changes.map { c in
                switch c.kind {
                case .added: "+ \(c.path) = \(c.after ?? "")"
                case .removed: "- \(c.path) = \(c.before ?? "")"
                case .moved: "~ \(c.path): \(c.before ?? "")"
                default: "~ \(c.path): \(c.before ?? "") → \(c.after ?? "")"
                }
            }.joined(separator: "\n")
            let summary = [MetaRow("Changes", "\(changes.count)"), MetaRow("Added", "\(changes.filter { $0.kind == .added }.count)"), MetaRow("Removed", "\(changes.filter { $0.kind == .removed }.count)"), MetaRow("Changed", "\(changes.filter { $0.kind == .changed || $0.kind == .typeChanged }.count)")]
            return ToolOutput(text: text, language: .diff, metadata: summary + rows, isValid: changes.isEmpty ? true : nil)
        }
        func norm(_ s: String) -> String {
            var t = s
            if options.ignoreWhitespace { t = t.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression) }
            if options.ignoreCase { t = t.lowercased() }
            return t
        }
        switch options.granularity {
        case "word", "char":
            let ta = options.granularity == "word" ? DiffEngine.words(a) : DiffEngine.characters(a)
            let tb = options.granularity == "word" ? DiffEngine.words(b) : DiffEngine.characters(b)
            let edits = DiffEngine.diff(ta.map(norm), tb.map(norm))
            var out = ""
            var annotationsA: [Annotation] = []
            var offsetA = 0
            var added = 0, removed = 0
            for e in edits {
                let tokA = e.oldIndex.map { ta[$0] }
                let tokB = e.newIndex.map { tb[$0] }
                switch e.op {
                case .equal: out += tokA ?? ""; offsetA += (tokA ?? "").utf16.count
                case .delete:
                    let t = tokA ?? ""
                    out += "[-\(t)-]"
                    annotationsA.append(Annotation(.input, range: offsetA..<(offsetA + t.utf16.count), style: .removed))
                    offsetA += t.utf16.count
                    removed += 1
                case .insert: out += "{+\(tokB ?? "")+}"; added += 1
                }
            }
            let rows = [MetaRow("Inserted", "\(added) \(options.granularity == "word" ? "words" : "characters")", style: .success), MetaRow("Deleted", "\(removed)", style: .danger)]
            return ToolOutput(text: added + removed == 0 ? "No differences" : out, language: .plain, metadata: rows, annotations: annotationsA, isValid: added + removed == 0 ? true : nil)
        default:
            let unified = DiffEngine.unified(a, b, nameA: input.fileName ?? "Input A", nameB: "Input B", context: options.context, ignoreWhitespace: options.ignoreWhitespace, ignoreCase: options.ignoreCase)
            let added = unified.split(separator: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
            let removed = unified.split(separator: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
            let la = DiffEngine.lines(a), lb = DiffEngine.lines(b)
            let rows = [MetaRow("Lines", "\(la.count) → \(lb.count)"), MetaRow("Added", "\(added)", style: .success), MetaRow("Removed", "\(removed)", style: .danger)]
            var annotations: [Annotation] = []
            let edits = DiffEngine.diff(la.map(norm), lb.map(norm))
            for e in edits where e.op == .delete {
                if let i = e.oldIndex {
                    let start = a.utf16Offset(line: i + 1)
                    annotations.append(Annotation(.input, range: start..<(start + la[i].utf16.count), style: .removed))
                }
            }
            return ToolOutput(text: unified.isEmpty ? "No differences" : unified, language: .diff, metadata: rows, annotations: annotations, isValid: unified.isEmpty ? true : nil)
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        // A unified-diff header is very specific; it must outrank YAML, which also starts with "---".
        let isUnified = (s.hasPrefix("--- ") || s.hasPrefix("diff --git ")) && s.contains("\n+++ ") && s.contains("\n@@")
        return isUnified ? DetectionScore(0.9, "Unified diff") : nil
    }
}
