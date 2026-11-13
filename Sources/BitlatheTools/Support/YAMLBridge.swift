import Foundation
import Yams
import BitlatheCore

/// Conversions between Yams nodes and our ordered JSONValue.
enum YAMLBridge {
    static func parse(_ text: String) throws -> [JSONValue] {
        do {
            // YamlSequence swallows parse errors during iteration and exposes them via `.error`.
            var nodes = try Yams.compose_all(yaml: text)
            var out: [JSONValue] = []
            while let n = nodes.next() { out.append(convert(n)) }
            if let err = nodes.error { throw err }
            return out
        } catch let e as YamlError {
            throw translate(e)
        }
    }

    static func parseOne(_ text: String) throws -> JSONValue {
        let docs = try parse(text)
        guard let first = docs.first else { throw ToolError("YAML document is empty") }
        return docs.count == 1 ? first : .array(docs)
    }

    static func convert(_ node: Yams.Node) -> JSONValue {
        switch node {
        case .scalar(let s):
            let v = s.string
            if s.tag.description == Tag.Name.str.rawValue { return .string(v) }
            if s.style == .doubleQuoted || s.style == .singleQuoted { return .string(v) }
            switch v {
            case "null", "Null", "NULL", "~", "": return .null
            case "true", "True", "TRUE": return .bool(true)
            case "false", "False", "FALSE": return .bool(false)
            default: break
            }
            if v.range(of: "^[-+]?(0|[1-9][0-9_]*)$", options: .regularExpression) != nil, let i = Int(v.replacingOccurrences(of: "_", with: "")) { return .number(String(i)) }
            if v.range(of: "^[-+]?(\\.[0-9]+|[0-9]+(\\.[0-9]*)?)([eE][-+]?[0-9]+)?$", options: .regularExpression) != nil, Double(v) != nil { return .number(v) }
            if v.hasPrefix("0x"), let i = Int(v.dropFirst(2), radix: 16) { return .number(String(i)) }
            if v == ".inf" || v == ".Inf" { return .number("Infinity") }
            if v == "-.inf" { return .number("-Infinity") }
            if v == ".nan" || v == ".NaN" { return .number("NaN") }
            return .string(v)
        case .sequence(let seq):
            return .array(seq.map(convert))
        case .mapping(let map):
            return .object(map.map { (key: $0.key.string ?? "", value: convert($0.value)) })
        case .alias:
            return .null
        }
    }

    static func node(from v: JSONValue) -> Yams.Node {
        switch v {
        case .null: return Yams.Node.scalar(.init("null", Tag(.null)))
        case .bool(let b): return Yams.Node.scalar(.init(b ? "true" : "false", Tag(.bool)))
        case .number(let s): return Yams.Node.scalar(.init(s, s.contains(".") || s.contains("e") || s.contains("E") || s.contains("Inf") || s.contains("NaN") ? Tag(.float) : Tag(.int)))
        case .string(let s):
            let needsQuotes = s.isEmpty || ["null", "true", "false", "yes", "no", "on", "off", "~", "Null", "True", "False"].contains(s)
                || Double(s) != nil || s.hasPrefix("0x") || s.first == " " || s.last == " " || s.contains(": ") || s.hasPrefix("#") || s.hasPrefix("- ")
                || s.hasPrefix("*") || s.hasPrefix("&") || s.hasPrefix("!") || s.hasPrefix("@") || s.hasPrefix("`") || s.hasPrefix("[") || s.hasPrefix("{")
                || s.hasPrefix("\"") || s.hasPrefix("'") || s.contains(" #") || s.hasSuffix(":") || s.hasPrefix("%") || s.hasPrefix("|") || s.hasPrefix(">") || s.hasPrefix("?")
            if s.contains("\n") { return Yams.Node.scalar(.init(s, Tag(.str), .literal)) }
            return Yams.Node.scalar(.init(s, Tag(.str), needsQuotes ? .doubleQuoted : .plain))
        case .array(let a): return Yams.Node.sequence(.init(a.map(node)))
        case .object(let o): return Yams.Node.mapping(.init(o.map { (Yams.Node.scalar(.init($0.key, Tag(.str), $0.key.isEmpty || Double($0.key) != nil || ["true", "false", "null", "yes", "no"].contains($0.key) ? .doubleQuoted : .plain)), node(from: $0.value)) }))
        }
    }

    static func serialize(_ v: JSONValue, indent: Int = 2, width: Int = 80, sortKeys: Bool = false) throws -> String {
        let n = node(from: sortKeys ? v.sortedKeys() : v)
        let out = try Yams.serialize(node: n, indent: indent, width: width == 0 ? -1 : width, allowUnicode: true, sortKeys: false)
        if out.hasSuffix("\n") {
            // A literal block scalar at the very end of the document needs its final newline ("|" keeps one line break),
            // so only strip when the stripped text still parses to the same value.
            let stripped = String(out.dropLast())
            if !out.contains("|") { return stripped }
            if let docs = try? parse(stripped), docs.count == 1, docs[0] == v { return stripped }
        }
        return out
    }

    static func translate(_ e: YamlError) -> ToolError {
        switch e {
        case .parser(let context, let problem, let mark, _):
            return ToolError(clean(problem), line: mark.line, column: mark.column, hint: context?.text)
        case .scanner(let context, let problem, let mark, _):
            return ToolError(clean(problem), line: mark.line, column: mark.column, hint: context?.text)
        case .reader(let problem, _, let offset, _):
            return ToolError(clean(problem), hint: "At byte offset \(offset)")
        case .composer(let context, let problem, let mark, _):
            return ToolError(clean(problem), line: mark.line, column: mark.column, hint: context?.text)
        case .emitter(let problem):
            return ToolError(clean(problem))
        default:
            return ToolError(String(describing: e).split(separator: "\n").first.map(String.init) ?? "Invalid YAML")
        }
    }

    private static func clean(_ s: String) -> String { s.capitalizedFirst() }
}
