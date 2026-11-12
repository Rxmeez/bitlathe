import Foundation
import BitlatheCore

public struct PHPArrayJSONTool: DevTool {
    public static let id = "php.array-json"
    public static let name = "PHP Array ⇄ JSON"
    public static let summary = "Convert PHP array literals to JSON and back"
    public static let category = ToolCategory.convert
    public static let symbol = "p.square"
    public static let keywords = ["php", "array", "json", "convert", "laravel"]
    public static let io = ToolIO.text(.php, .json)
    public static let samples = [ToolSample("PHP → JSON", "[\n  'name' => 'Bitlathe',\n  'tags' => ['mac', 'dev'],\n  'meta' => array('version' => 1.5, 'stable' => true, 'next' => null),\n]"),
                                 ToolSample("JSON → PHP", #"{"name":"Bitlathe","tags":["mac","dev"],"count":3}"#, options: ["direction": .string("json2php")])]
    public static let optionFields: [OptionField] = [
        .segmented("direction", "Direction", [.init("auto", "Auto"), .init("php2json", "PHP → JSON"), .init("json2php", "JSON → PHP")], default: "auto"),
        .segmented("syntax", "Syntax", [.init("short", "[ ]"), .init("long", "array( )")], default: "short", visibleWhen: ("direction", ["auto", "json2php"])),
    ]
    public struct Options: ToolOptions {
        public var direction = "auto"
        public var syntax = "short"
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        var text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let toJSON: Bool = switch options.direction {
        case "php2json": true
        case "json2php": false
        default: text.contains("=>") || text.lowercased().hasPrefix("array(") || text.hasPrefix("<?php")
        }
        if toJSON {
            text = text.removingPrefix("<?php").trimmed()
            if let eq = text.firstIndex(of: "="), text[..<eq].trimmed().hasPrefix("$") { text = String(text[text.index(after: eq)...]).trimmed() }
            if text.hasSuffix(";") { text.removeLast() }
            var p = PHPLiteralParser(text)
            let v = try p.parse()
            return ToolOutput(text: JSONSerializer.string(v), language: .json)
        }
        let v = try JSONParser.parse(text, options: .json5)
        return ToolOutput(text: Self.php(v, long: options.syntax == "long", level: 0) + ";", language: .php)
    }

    static func php(_ v: JSONValue, long: Bool, level: Int) -> String {
        let pad = String(repeating: "    ", count: level + 1)
        let end = String(repeating: "    ", count: level)
        let open = long ? "array(" : "["
        let close = long ? ")" : "]"
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let s): return s
        case .string(let s): return "'" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
        case .array(let a):
            if a.isEmpty { return open + close }
            return open + "\n" + a.map { pad + php($0, long: long, level: level + 1) + "," }.joined(separator: "\n") + "\n" + end + close
        case .object(let o):
            if o.isEmpty { return open + close }
            return open + "\n" + o.map { pad + "'\($0.key.replacingOccurrences(of: "'", with: "\\'"))' => " + php($0.value, long: long, level: level + 1) + "," }.joined(separator: "\n") + "\n" + end + close
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.contains("=>"), (s.hasPrefix("[") || s.lowercased().hasPrefix("array(") || s.hasPrefix("$") || s.hasPrefix("<?php")) { return DetectionScore(0.85, "PHP array literal") }
        return nil
    }
}

/// Parses PHP array literals: [ 'k' => v, ... ], array(...), strings, numbers, true/false/null.
struct PHPLiteralParser {
    let chars: [Character]
    var pos = 0
    init(_ s: String) { chars = Array(s) }

    mutating func parse() throws -> JSONValue {
        skip()
        let v = try value()
        skip()
        if pos < chars.count { throw error("Unexpected '\(chars[pos])'") }
        return v
    }

    func error(_ m: String) -> ToolError {
        let consumed = String(chars[0..<min(pos, chars.count)])
        let (l, c) = consumed.lineAndColumn(utf16Offset: consumed.utf16.count)
        return ToolError(m, line: l, column: c)
    }

    mutating func skip() {
        while pos < chars.count {
            if chars[pos].isWhitespace { pos += 1; continue }
            if chars[pos] == "/", pos + 1 < chars.count, chars[pos + 1] == "/" { while pos < chars.count, chars[pos] != "\n" { pos += 1 }; continue }
            if chars[pos] == "#" { while pos < chars.count, chars[pos] != "\n" { pos += 1 }; continue }
            if chars[pos] == "/", pos + 1 < chars.count, chars[pos + 1] == "*" {
                pos += 2
                while pos + 1 < chars.count, !(chars[pos] == "*" && chars[pos + 1] == "/") { pos += 1 }
                pos += 2
                continue
            }
            break
        }
    }

    mutating func value() throws -> JSONValue {
        guard pos < chars.count else { throw error("Unexpected end of input") }
        let c = chars[pos]
        if c == "[" { pos += 1; return try array(close: "]") }
        if String(chars[pos..<min(pos + 6, chars.count)]).lowercased() == "array(" { pos += 6; return try array(close: ")") }
        if c == "'" || c == "\"" { return .string(try string()) }
        if c == "-" || c == "+" || c.isNumber || c == "." {
            let start = pos
            pos += 1
            while pos < chars.count, chars[pos].isNumber || chars[pos] == "." || chars[pos] == "e" || chars[pos] == "E" || chars[pos] == "_" || ((chars[pos] == "-" || chars[pos] == "+") && (chars[pos - 1] == "e" || chars[pos - 1] == "E")) { pos += 1 }
            var s = String(chars[start..<pos]).replacingOccurrences(of: "_", with: "")
            if s.hasPrefix("+") { s.removeFirst() }
            if Double(s) == nil { throw error("Invalid number \(s)") }
            return .number(s)
        }
        let word = String(chars[pos...].prefix { $0.isLetter || $0 == "_" }).lowercased()
        switch word {
        case "true": pos += 4; return .bool(true)
        case "false": pos += 5; return .bool(false)
        case "null": pos += 4; return .null
        default: throw error("Unexpected '\(c)'")
        }
    }

    mutating func string() throws -> String {
        let q = chars[pos]
        pos += 1
        var out = ""
        while pos < chars.count {
            let c = chars[pos]
            if c == q { pos += 1; return out }
            if c == "\\", pos + 1 < chars.count {
                let n = chars[pos + 1]
                if q == "'" {
                    if n == "'" || n == "\\" { out.append(n); pos += 2; continue }
                    out.append(c); pos += 1; continue
                }
                switch n {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                case "$": out.append("$")
                case "0": out.append("\0")
                default: out.append(c); out.append(n)
                }
                pos += 2
                continue
            }
            out.append(c)
            pos += 1
        }
        throw error("Unterminated string")
    }

    mutating func array(close: Character) throws -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = []
        var items: [JSONValue] = []
        var isMap = false
        var nextIndex = 0
        while true {
            skip()
            guard pos < chars.count else { throw error("Unterminated array") }
            if chars[pos] == close { pos += 1; break }
            let first = try value()
            skip()
            if pos + 1 < chars.count, chars[pos] == "=", chars[pos + 1] == ">" {
                pos += 2
                skip()
                let v = try value()
                isMap = true
                let key: String = switch first {
                case .string(let s): s
                case .number(let n): n
                case .bool(let b): b ? "1" : "0"
                default: String(nextIndex)
                }
                if let i = Int(key) { nextIndex = max(nextIndex, i + 1) }
                if !items.isEmpty { pairs = items.enumerated().map { (key: String($0.offset), value: $0.element) }; items = [] }
                pairs.append((key: key, value: v))
            } else {
                if isMap { pairs.append((key: String(nextIndex), value: first)); nextIndex += 1 } else { items.append(first); nextIndex += 1 }
            }
            skip()
            if pos < chars.count, chars[pos] == "," { pos += 1; continue }
            if pos < chars.count, chars[pos] == close { pos += 1; break }
            throw error("Expected ',' or '\(close)'")
        }
        if isMap { return .object(pairs) }
        return .array(items)
    }
}

public struct PHPSerializeTool: DevTool {
    public static let id = "php.serialize"
    public static let name = "PHP Serialize / Unserialize"
    public static let summary = "Convert between PHP serialize() format and JSON"
    public static let category = ToolCategory.convert
    public static let symbol = "shippingbox"
    public static let keywords = ["php", "serialize", "unserialize", "session", "json"]
    public static let samples = [ToolSample("Unserialize", "a:3:{s:4:\"name\";s:8:\"Bitlathe\";s:5:\"count\";i:3;s:4:\"tags\";a:2:{i:0;s:3:\"mac\";i:1;s:3:\"dev\";}}"),
                                 ToolSample("Serialize", #"{"name":"Bitlathe","ok":true,"ratio":0.5,"items":[1,2]}"#, options: ["mode": .string("serialize")])]
    public static let optionFields: [OptionField] = [
        .mode([.init("auto", "Auto"), .init("unserialize", "Unserialize"), .init("serialize", "Serialize")], default: "auto"),
    ]
    public struct Options: ToolOptions {
        public var mode = "auto"
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let unserialize: Bool = switch options.mode {
        case "unserialize": true
        case "serialize": false
        default: text.range(of: "^[aOsibdN]:", options: .regularExpression) != nil
        }
        if unserialize {
            var p = PHPUnserializer(text)
            let v = try p.parse()
            return ToolOutput(text: JSONSerializer.string(v), language: .json)
        }
        let v = try JSONParser.parse(text, options: .json5)
        return ToolOutput(text: Self.serialize(v), language: .php)
    }

    static func serialize(_ v: JSONValue) -> String {
        switch v {
        case .null: return "N;"
        case .bool(let b): return "b:\(b ? 1 : 0);"
        case .number(let s): return Int(s) != nil ? "i:\(s);" : "d:\(s);"
        case .string(let s): return "s:\(s.utf8.count):\"\(s)\";"
        case .array(let a): return "a:\(a.count):{" + a.enumerated().map { "i:\($0.offset);" + serialize($0.element) }.joined() + "}"
        case .object(let o): return "a:\(o.count):{" + o.map { (Int($0.key).map { "i:\($0);" } ?? "s:\($0.key.utf8.count):\"\($0.key)\";") + serialize($0.value) }.joined() + "}"
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        s.range(of: "^(a:\\d+:\\{|O:\\d+:\"|s:\\d+:\"[\\s\\S]*\";$|i:-?\\d+;$|b:[01];$|N;$)", options: .regularExpression) != nil ? DetectionScore(0.9, "PHP serialized data") : nil
    }
}

struct PHPUnserializer {
    let bytes: [UInt8]
    var pos = 0
    init(_ s: String) { bytes = Array(s.utf8) }

    func error(_ m: String) -> ToolError { ToolError(m, hint: "At byte offset \(pos)") }

    mutating func parse() throws -> JSONValue {
        let v = try value()
        return v
    }

    mutating func expect(_ c: UInt8) throws {
        guard pos < bytes.count, bytes[pos] == c else { throw error("Expected '\(Character(UnicodeScalar(c)))'") }
        pos += 1
    }

    mutating func readUntil(_ c: UInt8) throws -> String {
        let start = pos
        while pos < bytes.count, bytes[pos] != c { pos += 1 }
        guard pos < bytes.count else { throw error("Unexpected end of data") }
        let s = String(decoding: bytes[start..<pos], as: UTF8.self)
        pos += 1
        return s
    }

    mutating func value() throws -> JSONValue {
        guard pos < bytes.count else { throw error("Unexpected end of data") }
        let t = bytes[pos]
        pos += 1
        switch t {
        case UInt8(ascii: "N"): try expect(UInt8(ascii: ";")); return .null
        case UInt8(ascii: "b"): try expect(UInt8(ascii: ":")); let v = try readUntil(UInt8(ascii: ";")); return .bool(v == "1")
        case UInt8(ascii: "i"): try expect(UInt8(ascii: ":")); return .number(try readUntil(UInt8(ascii: ";")))
        case UInt8(ascii: "d"):
            try expect(UInt8(ascii: ":"))
            let v = try readUntil(UInt8(ascii: ";"))
            return .number(v == "INF" ? "Infinity" : (v == "-INF" ? "-Infinity" : (v == "NAN" ? "NaN" : v)))
        case UInt8(ascii: "s"):
            try expect(UInt8(ascii: ":"))
            guard let len = Int(try readUntil(UInt8(ascii: ":"))) else { throw error("Invalid string length") }
            try expect(UInt8(ascii: "\""))
            guard pos + len <= bytes.count else { throw error("String length \(len) exceeds data") }
            let s = String(decoding: bytes[pos..<pos + len], as: UTF8.self)
            pos += len
            try expect(UInt8(ascii: "\""))
            try expect(UInt8(ascii: ";"))
            return .string(s)
        case UInt8(ascii: "a"):
            try expect(UInt8(ascii: ":"))
            guard let count = Int(try readUntil(UInt8(ascii: ":"))) else { throw error("Invalid array length") }
            try expect(UInt8(ascii: "{"))
            var pairs: [(key: String, value: JSONValue)] = []
            for _ in 0..<count {
                let k = try value()
                let v = try value()
                pairs.append((key: k.stringValue ?? XMLJSON.scalar(k), value: v))
            }
            try expect(UInt8(ascii: "}"))
            let isList = pairs.enumerated().allSatisfy { $0.element.key == String($0.offset) }
            return isList ? .array(pairs.map(\.value)) : .object(pairs)
        case UInt8(ascii: "O"):
            try expect(UInt8(ascii: ":"))
            _ = try readUntil(UInt8(ascii: ":"))
            try expect(UInt8(ascii: "\""))
            let cls = try readUntil(UInt8(ascii: "\""))
            try expect(UInt8(ascii: ":"))
            guard let count = Int(try readUntil(UInt8(ascii: ":"))) else { throw error("Invalid object length") }
            try expect(UInt8(ascii: "{"))
            var pairs: [(key: String, value: JSONValue)] = [(key: "__class", value: .string(cls))]
            for _ in 0..<count {
                let k = try value()
                let v = try value()
                var key = k.stringValue ?? XMLJSON.scalar(k)
                key = key.replacingOccurrences(of: "\0", with: ":")
                pairs.append((key: key, value: v))
            }
            try expect(UInt8(ascii: "}"))
            return .object(pairs)
        default:
            throw error("Unknown type marker '\(Character(UnicodeScalar(t)))'")
        }
    }
}
