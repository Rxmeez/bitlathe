import Foundation
import BitlatheCore

/// JSONPath (Goessner-style) evaluator with jq-style sugar (`.items[].id`, `.[0]`, `keys`, `length`).
public enum JSONPath {
    indirect enum Segment {
        case key(String)
        case index(Int)
        case wildcard
        case recursive
        case slice(Int?, Int?, Int?)
        case union([Segment])
        case filter(String)
    }

    public static func evaluate(_ expression: String, in root: JSONValue) throws -> [JSONValue] {
        let expr = expression.trimmingCharacters(in: .whitespaces)
        if expr.isEmpty || expr == "$" || expr == "." { return [root] }
        // jq-style post functions
        var pipeline = expr.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let pathExpr = pipeline.removeFirst()
        var current = try evaluatePath(normalize(pathExpr), in: root)
        for fn in pipeline {
            switch fn {
            case "keys": current = current.map { v in .array(v.objectValue?.map { .string($0.key) } ?? (v.arrayValue.map { Array(0..<$0.count).map { .number($0) } } ?? [])) }
            case "length": current = current.map { v in
                switch v {
                case .string(let s): .number(s.count)
                case .array, .object: .number(v.count)
                case .null: .number(0)
                default: .number(1)
                }
            }
            case "values": current = current.flatMap { v in v.objectValue?.map(\.value) ?? (v.arrayValue ?? [v]) }
            case "first": current = current.compactMap { $0.arrayValue?.first }
            case "last": current = current.compactMap { $0.arrayValue?.last }
            case "unique": current = current.map { v in
                var seen: [JSONValue] = []
                for i in v.arrayValue ?? [] where !seen.contains(i) { seen.append(i) }
                return .array(seen)
            }
            case "sort": current = current.map { v in .array((v.arrayValue ?? []).sorted { Self.compare($0, $1) < 0 }) }
            case "reverse": current = current.map { v in .array((v.arrayValue ?? []).reversed()) }
            case "flatten": current = current.map { v in .array((v.arrayValue ?? []).flatMap { $0.arrayValue ?? [$0] }) }
            case "add":
                current = current.map { v in
                    let items = v.arrayValue ?? []
                    if items.allSatisfy({ $0.doubleValue != nil }) { return .number(items.compactMap(\.doubleValue).reduce(0, +)) }
                    if items.allSatisfy({ $0.stringValue != nil }) { return .string(items.compactMap(\.stringValue).joined()) }
                    return .array(items.flatMap { $0.arrayValue ?? [$0] })
                }
            case "tostring": current = current.map { .string(JSONSerializer.string($0, options: .minified)) }
            case "type": current = current.map { .string($0.typeName) }
            default:
                if fn.hasPrefix(".") || fn.hasPrefix("$") || fn.hasPrefix("[") {
                    current = try current.flatMap { try evaluatePath(normalize(fn), in: $0) }
                } else {
                    throw ToolError("Unknown function \"\(fn)\"", hint: "Supported: keys, values, length, first, last, unique, sort, reverse, flatten, add, type")
                }
            }
        }
        return current
    }

    /// Turn jq-ish paths into JSONPath: `.a.b[]` → `$.a.b[*]`, `.[0]` → `$[0]`.
    static func normalize(_ s: String) -> String {
        var e = s
        if e.hasPrefix("$") { return e }
        if e.hasPrefix(".") { e = "$" + e }
        else if e.hasPrefix("[") { e = "$" + e }
        else { e = "$." + e }
        e = e.replacingOccurrences(of: "[]", with: "[*]")
        e = e.replacingOccurrences(of: "$.[", with: "$[")
        return e
    }

    static func evaluatePath(_ path: String, in root: JSONValue) throws -> [JSONValue] {
        let segments = try parse(path)
        var current = [root]
        for seg in segments {
            current = try apply(seg, to: current, root: root)
        }
        return current
    }

    static func parse(_ path: String) throws -> [Segment] {
        var segs: [Segment] = []
        let chars = Array(path)
        var i = 0
        guard chars.first == "$" else { throw ToolError("Path must start with $ or .") }
        i = 1
        while i < chars.count {
            let c = chars[i]
            if c == "." {
                if i + 1 < chars.count, chars[i + 1] == "." {
                    segs.append(.recursive)
                    i += 2
                    if i < chars.count, chars[i] == "[" { continue }
                    if i < chars.count, chars[i] == "*" { segs.append(.wildcard); i += 1; continue }
                    let start = i
                    while i < chars.count, chars[i] != ".", chars[i] != "[" { i += 1 }
                    if i > start { segs.append(.key(String(chars[start..<i]))) }
                    continue
                }
                i += 1
                if i < chars.count, chars[i] == "*" { segs.append(.wildcard); i += 1; continue }
                let start = i
                while i < chars.count, chars[i] != ".", chars[i] != "[" { i += 1 }
                let name = String(chars[start..<i])
                if name.isEmpty { throw ToolError("Empty path segment at position \(i)") }
                segs.append(.key(name))
            } else if c == "[" {
                var depth = 1
                var j = i + 1
                var inQuote: Character?
                while j < chars.count {
                    let cj = chars[j]
                    if let q = inQuote { if cj == q { inQuote = nil } }
                    else if cj == "'" || cj == "\"" { inQuote = cj }
                    else if cj == "[" { depth += 1 }
                    else if cj == "]" { depth -= 1; if depth == 0 { break } }
                    j += 1
                }
                guard j < chars.count else { throw ToolError("Unterminated '[' in path") }
                let inner = String(chars[(i + 1)..<j]).trimmingCharacters(in: .whitespaces)
                segs.append(try parseBracket(inner))
                i = j + 1
            } else {
                throw ToolError("Unexpected '\(c)' in path at position \(i)")
            }
        }
        return segs
    }

    static func parseBracket(_ inner: String) throws -> Segment {
        if inner == "*" { return .wildcard }
        if inner.hasPrefix("?") {
            var f = inner.dropFirst()
            if f.hasPrefix("("), f.hasSuffix(")") { f = f.dropFirst().dropLast() }
            return .filter(String(f))
        }
        if inner.contains(",") {
            let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return .union(try parts.map { try parseBracket($0) })
        }
        if inner.contains(":") {
            let parts = inner.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            func num(_ s: String) -> Int? { s.isEmpty ? nil : Int(s) }
            return .slice(num(parts[0]), parts.count > 1 ? num(parts[1]) : nil, parts.count > 2 ? num(parts[2]) : nil)
        }
        if let n = Int(inner) { return .index(n) }
        if (inner.hasPrefix("'") && inner.hasSuffix("'")) || (inner.hasPrefix("\"") && inner.hasSuffix("\"")) {
            return .key(String(inner.dropFirst().dropLast()))
        }
        return .key(inner)
    }

    static func apply(_ seg: Segment, to values: [JSONValue], root: JSONValue) throws -> [JSONValue] {
        var out: [JSONValue] = []
        for v in values {
            switch seg {
            case .key(let k):
                if let x = v[k] { out.append(x) }
            case .index(let n):
                if let a = v.arrayValue {
                    let idx = n < 0 ? a.count + n : n
                    if a.indices.contains(idx) { out.append(a[idx]) }
                }
            case .wildcard:
                out += children(v)
            case .recursive:
                out += descendants(v)
            case .slice(let s, let e, let st):
                guard let a = v.arrayValue else { continue }
                let step = st ?? 1
                guard step != 0 else { throw ToolError("Slice step cannot be 0") }
                var start = s ?? (step > 0 ? 0 : a.count - 1)
                var end = e ?? (step > 0 ? a.count : -a.count - 1)
                if start < 0 { start += a.count }
                if end < 0 { end += a.count }
                start = max(min(start, a.count), step > 0 ? 0 : -1)
                end = max(min(end, a.count), -1)
                var i = start
                while step > 0 ? i < end : i > end {
                    if a.indices.contains(i) { out.append(a[i]) }
                    i += step
                }
            case .union(let segs):
                for s in segs { out += try apply(s, to: [v], root: root) }
            case .filter(let expr):
                for child in children(v) where try Filter.evaluate(expr, item: child, root: root) { out.append(child) }
            }
        }
        return out
    }

    static func children(_ v: JSONValue) -> [JSONValue] {
        switch v {
        case .array(let a): a
        case .object(let o): o.map(\.value)
        default: []
        }
    }

    static func descendants(_ v: JSONValue) -> [JSONValue] {
        var out = [v]
        for c in children(v) { out += descendants(c) }
        return out
    }

    static func compare(_ a: JSONValue, _ b: JSONValue) -> Int {
        if let x = a.doubleValue, let y = b.doubleValue { return x < y ? -1 : (x > y ? 1 : 0) }
        if let x = a.stringValue, let y = b.stringValue { return x < y ? -1 : (x > y ? 1 : 0) }
        let x = JSONSerializer.string(a, options: .minified)
        let y = JSONSerializer.string(b, options: .minified)
        return x < y ? -1 : (x > y ? 1 : 0)
    }

    /// Filter expressions: `@.price < 10`, `@.name == 'x'`, `@.tags`, `@.a && @.b`, `@.x =~ /re/`.
    enum Filter {
        static func evaluate(_ expr: String, item: JSONValue, root: JSONValue) throws -> Bool {
            let e = expr.trimmingCharacters(in: .whitespaces)
            if let parts = splitTop(e, on: "||") { return try parts.contains { try evaluate($0, item: item, root: root) } }
            if let parts = splitTop(e, on: "&&") { return try parts.allSatisfy { try evaluate($0, item: item, root: root) } }
            if e.hasPrefix("!") { return try !evaluate(String(e.dropFirst()), item: item, root: root) }
            if e.hasPrefix("("), e.hasSuffix(")") { return try evaluate(String(e.dropFirst().dropLast()), item: item, root: root) }
            for op in ["==", "!=", ">=", "<=", "=~", ">", "<", " in ", " nin "] {
                if let r = e.range(of: op) {
                    let lhs = try operand(String(e[..<r.lowerBound]), item: item, root: root)
                    let rhsText = String(e[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if op == "=~" {
                        var pattern = rhsText
                        var opts: String.CompareOptions = [.regularExpression]
                        if pattern.hasPrefix("/"), let last = pattern.lastIndex(of: "/"), last != pattern.startIndex {
                            let flags = pattern[pattern.index(after: last)...]
                            if flags.contains("i") { opts.insert(.caseInsensitive) }
                            pattern = String(pattern[pattern.index(after: pattern.startIndex)..<last])
                        }
                        guard let s = lhs?.stringValue else { return false }
                        return s.range(of: pattern, options: opts) != nil
                    }
                    let rhs = try operand(rhsText, item: item, root: root)
                    switch op.trimmingCharacters(in: .whitespaces) {
                    case "==": return lhs == rhs
                    case "!=": return lhs != rhs
                    case "in": return rhs?.arrayValue?.contains(where: { $0 == lhs }) ?? false
                    case "nin": return !(rhs?.arrayValue?.contains(where: { $0 == lhs }) ?? false)
                    default:
                        guard let l = lhs, let r = rhs else { return false }
                        let c = compare(l, r)
                        switch op {
                        case ">": return c > 0
                        case "<": return c < 0
                        case ">=": return c >= 0
                        case "<=": return c <= 0
                        default: return false
                        }
                    }
                }
            }
            // existence
            let v = try operand(e, item: item, root: root)
            if let v { if case .bool(let b) = v { return b }; return !v.isNull }
            return false
        }

        static func splitTop(_ s: String, on op: String) -> [String]? {
            var parts: [String] = []
            var depth = 0
            var inQuote: Character?
            var current = ""
            let chars = Array(s)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if let q = inQuote { current.append(c); if c == q { inQuote = nil }; i += 1; continue }
                if c == "'" || c == "\"" { inQuote = c; current.append(c); i += 1; continue }
                if c == "(" || c == "[" { depth += 1 }
                if c == ")" || c == "]" { depth -= 1 }
                if depth == 0, i + op.count <= chars.count, String(chars[i..<i + op.count]) == op {
                    parts.append(current)
                    current = ""
                    i += op.count
                    continue
                }
                current.append(c)
                i += 1
            }
            guard !parts.isEmpty else { return nil }
            parts.append(current)
            return parts
        }

        static func operand(_ raw: String, item: JSONValue, root: JSONValue) throws -> JSONValue? {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("@") {
                let path = "$" + s.dropFirst()
                return try evaluatePath(path == "$" ? "$" : path, in: item).first
            }
            if s.hasPrefix("$") { return try evaluatePath(s, in: root).first }
            if (s.hasPrefix("'") && s.hasSuffix("'")) || (s.hasPrefix("\"") && s.hasSuffix("\"")) { return .string(String(s.dropFirst().dropLast())) }
            if s == "true" { return .bool(true) }
            if s == "false" { return .bool(false) }
            if s == "null" { return .null }
            if Double(s) != nil { return .number(s) }
            if s.hasPrefix("["), s.hasSuffix("]") {
                return try JSONParser.parse(s, options: .json5)
            }
            throw ToolError("Cannot understand \"\(s)\" in filter")
        }
    }
}
