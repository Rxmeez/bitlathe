import Foundation
import BitlatheCore

/// Order-preserving JSON value. Numbers keep their source text so precision survives round trips.
public indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case (.bool(let a), .bool(let b)): a == b
        case (.number(let a), .number(let b)): a == b || (Double(a) != nil && Double(a) == Double(b))
        case (.string(let a), .string(let b)): a == b
        case (.array(let a), .array(let b)): a == b
        case (.object(let a), .object(let b)): a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    public static func number(_ d: Double) -> JSONValue {
        if d == d.rounded(), abs(d) < 1e15 { return .number(String(Int64(d))) }
        return .number(String(d))
    }
    public static func number(_ i: Int) -> JSONValue { .number(String(i)) }

    public var doubleValue: Double? { if case .number(let s) = self { return Double(s) } else { return nil } }
    public var intValue: Int? {
        if case .number(let s) = self { return Int(s) ?? Double(s).flatMap { $0 == $0.rounded() ? Int($0) : nil } }
        return nil
    }
    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    public var objectValue: [(key: String, value: JSONValue)]? { if case .object(let o) = self { return o } else { return nil } }
    public var isNull: Bool { if case .null = self { return true } else { return false } }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let o) = self else { return nil }
        return o.first { $0.key == key }?.value
    }
    public subscript(index: Int) -> JSONValue? {
        guard case .array(let a) = self, a.indices.contains(index) else { return nil }
        return a[index]
    }

    public var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .number(let s): (Int(s) != nil) ? "integer" : "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    /// Converts to Foundation objects (for interop with PropertyListSerialization etc).
    public var foundationObject: Any {
        switch self {
        case .null: NSNull()
        case .bool(let b): b
        case .number(let s): if let i = Int(s) { i } else { Double(s) ?? 0 }
        case .string(let s): s
        case .array(let a): a.map(\.foundationObject)
        case .object(let o):
            o.reduce(into: [String: Any]()) { $0[$1.key] = $1.value.foundationObject as Any }
        }
    }

    public init(foundation any: Any) {
        switch any {
        case is NSNull: self = .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else if n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 1e18 { self = .number(String(n.int64Value)) }
            else { self = .number(String(n.doubleValue)) }
        case let b as Bool: self = .bool(b)
        case let i as Int: self = .number(String(i))
        case let d as Double: self = .number(d)
        case let s as String: self = .string(s)
        case let date as Date: self = .string(ISO8601DateFormatter().string(from: date))
        case let data as Data: self = .string(data.base64EncodedString())
        case let a as [Any]: self = .array(a.map { JSONValue(foundation: $0) })
        case let d as [String: Any]:
            self = .object(d.keys.sorted().map { (key: $0, value: JSONValue(foundation: d[$0]!)) })   // swiftlint:disable:this force_unwrapping
        default: self = .string(String(describing: any))
        }
    }

    public func sortedKeys() -> JSONValue {
        switch self {
        case .object(let o): .object(o.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value.sortedKeys()) })
        case .array(let a): .array(a.map { $0.sortedKeys() })
        default: self
        }
    }

    public var count: Int {
        switch self {
        case .array(let a): a.count
        case .object(let o): o.count
        default: 0
        }
    }
}

// MARK: - Parser

public struct JSONParser {
    public struct Options: Sendable {
        public var allowComments = false
        public var allowTrailingCommas = false
        public var allowSingleQuotes = false
        public var allowUnquotedKeys = false
        public var allowSpecialNumbers = false   // Infinity, NaN, hex, leading +
        public var allowMultilineStrings = false
        public init() {}
        public static let strict = Options()
        public static var json5: Options {
            var o = Options()
            o.allowComments = true
            o.allowTrailingCommas = true
            o.allowSingleQuotes = true
            o.allowUnquotedKeys = true
            o.allowSpecialNumbers = true
            o.allowMultilineStrings = true
            return o
        }
        public static var jsonc: Options {
            var o = Options()
            o.allowComments = true
            o.allowTrailingCommas = true
            return o
        }
    }

    private let bytes: [UInt8]
    private var pos = 0
    private let options: Options
    private var depth = 0
    private var valueCounter = 0

    public static func parse(_ text: String, options: Options = .strict) throws -> JSONValue {
        var p = JSONParser(bytes: Array(text.utf8), options: options)
        p.skipWhitespace()
        guard p.pos < p.bytes.count else { throw p.error("Unexpected end of input", hint: "The document is empty") }
        let v = try p.parseValue()
        p.skipWhitespace()
        if p.pos < p.bytes.count {
            throw p.error("Unexpected \(p.describeCurrent()) after the end of the document", hint: "Only one top-level value is allowed")
        }
        return v
    }

    private init(bytes: [UInt8], options: Options) {
        self.bytes = bytes
        self.options = options
    }

    private func lineColumn(at offset: Int) -> (Int, Int) {
        var line = 1
        var col = 1
        var i = 0
        while i < offset && i < bytes.count {
            if bytes[i] == 0x0A { line += 1; col = 1 }
            else if bytes[i] & 0xC0 != 0x80 { col += 1 }  // count code points, not continuation bytes
            i += 1
        }
        return (line, col)
    }

    private func error(_ msg: String, hint: String? = nil, at offset: Int? = nil) -> ToolError {
        let off = offset ?? pos
        let (l, c) = lineColumn(at: off)
        let utf16Offset = String(decoding: bytes[0..<min(off, bytes.count)], as: UTF8.self).utf16.count
        return ToolError(msg, line: l, column: c, hint: hint, range: utf16Offset..<(utf16Offset + 1))
    }

    private func describeCurrent() -> String {
        guard pos < bytes.count else { return "end of input" }
        let b = bytes[pos]
        if b == 0x22 { return "'\"'" }
        if b >= 0x20 && b < 0x7F { return "'\(Character(UnicodeScalar(b)))'" }
        return "character"
    }

    private mutating func skipWhitespace() {
        while pos < bytes.count {
            let b = bytes[pos]
            if b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09 { pos += 1; continue }
            if b == 0x2F, options.allowComments, pos + 1 < bytes.count {
                if bytes[pos + 1] == 0x2F {
                    while pos < bytes.count, bytes[pos] != 0x0A { pos += 1 }
                    continue
                }
                if bytes[pos + 1] == 0x2A {
                    pos += 2
                    while pos + 1 < bytes.count, !(bytes[pos] == 0x2A && bytes[pos + 1] == 0x2F) { pos += 1 }
                    pos = min(pos + 2, bytes.count)
                    continue
                }
            }
            // BOM / NBSP tolerated in JSON5
            if options.allowComments, b == 0xEF, pos + 2 < bytes.count, bytes[pos + 1] == 0xBB, bytes[pos + 2] == 0xBF { pos += 3; continue }
            break
        }
    }

    private mutating func parseValue() throws -> JSONValue {
        guard pos < bytes.count else { throw error("Unexpected end of input", hint: "Missing a value") }
        depth += 1
        defer { depth -= 1 }
        if depth > 512 { throw error("Nesting too deep") }
        valueCounter &+= 1
        if valueCounter & 0xFFF == 0, Task.isCancelled { throw CancellationError() }
        switch bytes[pos] {
        case 0x7B: return try parseObject()
        case 0x5B: return try parseArray()
        case 0x22: return .string(try parseString(quote: 0x22))
        case 0x27:
            if options.allowSingleQuotes { return .string(try parseString(quote: 0x27)) }
            throw error("Single-quoted strings are not valid JSON", hint: "Use double quotes, or switch the input mode to JSON5")
        case 0x74: try expectLiteral("true"); return .bool(true)
        case 0x66: try expectLiteral("false"); return .bool(false)
        case 0x6E: try expectLiteral("null"); return .null
        case 0x2F where !options.allowComments:
            throw error("Comments are not allowed in JSON", hint: "Switch the input mode to JSONC or JSON5 to strip comments")
        default:
            let b = bytes[pos]
            if b == 0x2D || b == 0x2B || (b >= 0x30 && b <= 0x39) || b == 0x2E || b == 0x49 || b == 0x4E {
                return try parseNumber()
            }
            if b == 0x7D { throw error("Unexpected '}'", hint: "Missing a value, or an extra closing brace") }
            if b == 0x5D { throw error("Unexpected ']'", hint: "Missing a value, or an extra closing bracket") }
            if b == 0x2C { throw error("Unexpected ','", hint: "Missing a value before the comma") }
            throw error("Unexpected \(describeCurrent())", hint: looksLikeUnquotedWord() ? "Strings and keys must be in double quotes" : nil)
        }
    }

    private func looksLikeUnquotedWord() -> Bool {
        pos < bytes.count && ((bytes[pos] >= 0x41 && bytes[pos] <= 0x5A) || (bytes[pos] >= 0x61 && bytes[pos] <= 0x7A))
    }

    private mutating func expectLiteral(_ lit: String) throws {
        let l = Array(lit.utf8)
        guard pos + l.count <= bytes.count, Array(bytes[pos..<pos + l.count]) == l else {
            throw error("Unexpected \(describeCurrent())", hint: "Did you mean \(lit)?")
        }
        pos += l.count
        if pos < bytes.count, isIdentChar(bytes[pos]) {
            throw error("Unexpected text after \(lit)")
        }
    }

    private func isIdentChar(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b == 0x24 || b >= 0x80
    }

    private mutating func parseObject() throws -> JSONValue {
        let startPos = pos
        pos += 1
        var pairs: [(key: String, value: JSONValue)] = []
        skipWhitespace()
        if pos < bytes.count, bytes[pos] == 0x7D { pos += 1; return .object(pairs) }
        while true {
            skipWhitespace()
            guard pos < bytes.count else { throw error("Unterminated object", hint: "Missing '}'", at: startPos) }
            let key: String
            if bytes[pos] == 0x22 { key = try parseString(quote: 0x22) }
            else if bytes[pos] == 0x27, options.allowSingleQuotes { key = try parseString(quote: 0x27) }
            else if options.allowUnquotedKeys, isIdentChar(bytes[pos]) {
                let s = pos
                while pos < bytes.count, isIdentChar(bytes[pos]) { pos += 1 }
                key = String(decoding: bytes[s..<pos], as: UTF8.self)
            } else if bytes[pos] == 0x7D {
                if options.allowTrailingCommas { pos += 1; return .object(pairs) }
                throw error("Trailing comma before '}'", hint: "Remove the comma after the last property, or switch to JSON5")
            } else if isIdentChar(bytes[pos]) {
                throw error("Object keys must be double-quoted strings", hint: "Switch to JSON5 to allow unquoted keys")
            } else {
                throw error("Expected a property name", hint: "Object keys must be strings in double quotes")
            }
            skipWhitespace()
            guard pos < bytes.count, bytes[pos] == 0x3A else { throw error("Expected ':' after property name \"\(key)\"") }
            pos += 1
            skipWhitespace()
            let v = try parseValue()
            pairs.append((key: key, value: v))
            skipWhitespace()
            guard pos < bytes.count else { throw error("Unterminated object", hint: "Missing '}'", at: startPos) }
            if bytes[pos] == 0x2C { pos += 1; continue }
            if bytes[pos] == 0x7D { pos += 1; return .object(pairs) }
            if bytes[pos] == 0x22 || isIdentChar(bytes[pos]) { throw error("Missing ',' between properties") }
            throw error("Expected ',' or '}' after property value")
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        let startPos = pos
        pos += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if pos < bytes.count, bytes[pos] == 0x5D { pos += 1; return .array(items) }
        while true {
            skipWhitespace()
            guard pos < bytes.count else { throw error("Unterminated array", hint: "Missing ']'", at: startPos) }
            if bytes[pos] == 0x5D {
                if options.allowTrailingCommas { pos += 1; return .array(items) }
                throw error("Trailing comma before ']'", hint: "Remove the comma after the last item, or switch to JSON5")
            }
            items.append(try parseValue())
            skipWhitespace()
            guard pos < bytes.count else { throw error("Unterminated array", hint: "Missing ']'", at: startPos) }
            if bytes[pos] == 0x2C { pos += 1; continue }
            if bytes[pos] == 0x5D { pos += 1; return .array(items) }
            throw error("Expected ',' or ']' after array element")
        }
    }

    private mutating func parseString(quote: UInt8) throws -> String {
        let startPos = pos
        pos += 1
        // Fast path: no escapes, no control characters. Decode the slice in one go.
        var scan = pos
        let count = bytes.count
        while scan < count {
            let c = bytes[scan]
            if c == quote {
                let str = String(decoding: bytes[pos..<scan], as: UTF8.self)
                pos = scan + 1
                return str
            }
            if c == 0x5C || c < 0x20 { break }
            scan += 1
        }
        var out = [UInt8]()
        out.reserveCapacity(scan - pos + 16)
        out.append(contentsOf: bytes[pos..<scan])
        pos = scan
        while true {
            guard pos < bytes.count else { throw error("Unterminated string", hint: "Missing closing quote", at: startPos) }
            let b = bytes[pos]
            if b == quote { pos += 1; break }
            if b == 0x5C {
                pos += 1
                guard pos < bytes.count else { throw error("Unterminated escape sequence") }
                let e = bytes[pos]
                switch e {
                case 0x22: out.append(0x22)
                case 0x27 where options.allowSingleQuotes: out.append(0x27)
                case 0x5C: out.append(0x5C)
                case 0x2F: out.append(0x2F)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0C)
                case 0x6E: out.append(0x0A)
                case 0x72: out.append(0x0D)
                case 0x74: out.append(0x09)
                case 0x30 where options.allowSpecialNumbers: out.append(0)
                case 0x76 where options.allowMultilineStrings: out.append(0x0B)
                case 0x0A where options.allowMultilineStrings: break   // line continuation
                case 0x0D where options.allowMultilineStrings:
                    if pos + 1 < bytes.count, bytes[pos + 1] == 0x0A { pos += 1 }
                case 0x78 where options.allowSpecialNumbers:
                    guard pos + 2 < bytes.count, let v = UInt8(String(decoding: bytes[pos + 1...pos + 2], as: UTF8.self), radix: 16) else {
                        throw error("Invalid \\x escape")
                    }
                    out.append(contentsOf: Array(String(UnicodeScalar(v)).utf8))
                    pos += 2
                case 0x75:
                    guard pos + 4 < bytes.count, let cu = UInt16(String(decoding: bytes[pos + 1...pos + 4], as: UTF8.self), radix: 16) else {
                        throw error("Invalid \\u escape", hint: "Expected four hex digits")
                    }
                    pos += 4
                    var scalarValue = UInt32(cu)
                    if cu >= 0xD800 && cu <= 0xDBFF {
                        // surrogate pair
                        if pos + 6 < bytes.count, bytes[pos + 1] == 0x5C, bytes[pos + 2] == 0x75,
                           let lo = UInt16(String(decoding: bytes[pos + 3...pos + 6], as: UTF8.self), radix: 16), lo >= 0xDC00, lo <= 0xDFFF {
                            scalarValue = 0x10000 + ((UInt32(cu) - 0xD800) << 10) + (UInt32(lo) - 0xDC00)
                            pos += 6
                        } else {
                            scalarValue = 0xFFFD
                        }
                    } else if cu >= 0xDC00 && cu <= 0xDFFF {
                        scalarValue = 0xFFFD
                    }
                    out.append(contentsOf: Array(String(UnicodeScalar(scalarValue) ?? "\u{FFFD}").utf8))
                default:
                    throw error("Invalid escape sequence '\\\(Character(UnicodeScalar(e)))'", hint: "Valid escapes: \\\" \\\\ \\/ \\b \\f \\n \\r \\t \\uXXXX")
                }
                pos += 1
                continue
            }
            if b < 0x20 {
                if b == 0x0A || b == 0x0D {
                    throw error("Unescaped line break in string", hint: "Use \\n inside strings, or switch to JSON5 for multi-line strings", at: startPos)
                }
                throw error("Unescaped control character in string", hint: "Control characters must be escaped as \\uXXXX")
            }
            out.append(b)
            pos += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = pos
        if bytes[pos] == 0x2B {
            guard options.allowSpecialNumbers else { throw error("Numbers cannot start with '+'", hint: "Remove the plus sign or switch to JSON5") }
            pos += 1
        } else if bytes[pos] == 0x2D { pos += 1 }
        guard pos < bytes.count else { throw error("Invalid number") }
        // Infinity / NaN
        if bytes[pos] == 0x49 || bytes[pos] == 0x4E {
            guard options.allowSpecialNumbers else { throw error("Unexpected \(describeCurrent())", hint: "Infinity and NaN are not valid JSON; switch to JSON5") }
            let rest = String(decoding: bytes[pos..<min(pos + 8, bytes.count)], as: UTF8.self)
            if rest.hasPrefix("Infinity") { pos += 8; return .number(bytes[start] == 0x2D ? "-Infinity" : "Infinity") }
            if rest.hasPrefix("NaN") { pos += 3; return .number("NaN") }
            throw error("Invalid number")
        }
        // hex
        if bytes[pos] == 0x30, pos + 1 < bytes.count, bytes[pos + 1] == 0x78 || bytes[pos + 1] == 0x58 {
            guard options.allowSpecialNumbers else { throw error("Hexadecimal numbers are not valid JSON", hint: "Switch to JSON5") }
            pos += 2
            let hs = pos
            while pos < bytes.count, Detect.hexChars.contains(UnicodeScalar(bytes[pos])) { pos += 1 }
            guard pos > hs, let v = UInt64(String(decoding: bytes[hs..<pos], as: UTF8.self), radix: 16) else { throw error("Invalid hex number") }
            return .number(bytes[start] == 0x2D ? "-\(v)" : "\(v)")
        }
        if bytes[pos] == 0x30, pos + 1 < bytes.count, bytes[pos + 1] >= 0x30, bytes[pos + 1] <= 0x39 {
            throw error("Numbers cannot have leading zeros")
        }
        var sawDigit = false
        while pos < bytes.count, bytes[pos] >= 0x30, bytes[pos] <= 0x39 { pos += 1; sawDigit = true }
        if pos < bytes.count, bytes[pos] == 0x2E {
            if !sawDigit, !options.allowSpecialNumbers { throw error("Numbers must start with a digit") }
            pos += 1
            let fs = pos
            while pos < bytes.count, bytes[pos] >= 0x30, bytes[pos] <= 0x39 { pos += 1 }
            if pos == fs, !options.allowSpecialNumbers { throw error("Expected digits after the decimal point") }
            sawDigit = sawDigit || pos > fs
        }
        guard sawDigit else { throw error("Invalid number") }
        if pos < bytes.count, bytes[pos] == 0x65 || bytes[pos] == 0x45 {
            pos += 1
            if pos < bytes.count, bytes[pos] == 0x2B || bytes[pos] == 0x2D { pos += 1 }
            let es = pos
            while pos < bytes.count, bytes[pos] >= 0x30, bytes[pos] <= 0x39 { pos += 1 }
            if pos == es { throw error("Expected digits in exponent") }
        }
        if pos < bytes.count, isIdentChar(bytes[pos]) { throw error("Unexpected character in number") }
        var text = String(decoding: bytes[start..<pos], as: UTF8.self)
        if text.hasPrefix("+") { text.removeFirst() }
        if text.hasPrefix(".") { text = "0" + text }
        if text.hasPrefix("-.") { text = "-0" + text.dropFirst() }
        if text.hasSuffix(".") { text += "0" }
        return .number(text)
    }
}

// MARK: - Serializer

public struct JSONSerializerOptions: Sendable {
    public var indent: Int = 2          // 0 = minified
    public var useTabs = false
    public var sortKeys = false
    public var escapeNonASCII = false
    public var escapeSlashes = false
    public var spaceAfterColon = true
    public init() {}
    public static let minified: JSONSerializerOptions = { var o = JSONSerializerOptions(); o.indent = 0; return o }()
    public static let pretty = JSONSerializerOptions()
}

public enum JSONSerializer {
    public static func string(_ value: JSONValue, options: JSONSerializerOptions = .pretty) -> String {
        var w = Writer(options: options, checksCancellation: false)
        // Non-throwing mode never throws.
        try? w.run(value)
        return String(decoding: w.out, as: UTF8.self)
    }

    /// Like `string(_:options:)` but checks `Task.isCancelled` periodically and throws `CancellationError`.
    public static func stringCancellable(_ value: JSONValue, options: JSONSerializerOptions = .pretty) throws -> String {
        var w = Writer(options: options, checksCancellation: true)
        try w.run(value)
        return String(decoding: w.out, as: UTF8.self)
    }

    /// Byte-level writer: appends UTF-8 into one `[UInt8]` buffer, copying clean string runs in bulk.
    private struct Writer {
        var out: [UInt8] = []
        let options: JSONSerializerOptions
        let pretty: Bool
        let unit: [UInt8]
        let checksCancellation: Bool
        var counter = 0
        var pads: [[UInt8]] = []

        init(options: JSONSerializerOptions, checksCancellation: Bool) {
            self.options = options
            self.checksCancellation = checksCancellation
            pretty = options.indent > 0 || options.useTabs
            unit = options.useTabs ? [0x09] : [UInt8](repeating: 0x20, count: options.indent)
            out.reserveCapacity(4096)
        }

        mutating func run(_ value: JSONValue) throws {
            let v = options.sortKeys ? value.sortedKeys() : value
            try write(v, level: 0)
        }

        private mutating func pad(_ level: Int) {
            guard pretty else { return }
            while pads.count <= level {
                pads.append(Array((0..<pads.count).map { _ in unit }.joined()))
            }
            out.append(contentsOf: pads[level])
        }

        @inline(__always) private mutating func append(_ s: StaticString) {
            s.withUTF8Buffer { out.append(contentsOf: $0) }
        }

        private mutating func tick() throws {
            counter &+= 1
            if checksCancellation, counter & 0x3FF == 0, Task.isCancelled { throw CancellationError() }
        }

        private mutating func write(_ v: JSONValue, level: Int) throws {
            switch v {
            case .null: append("null")
            case .bool(let b): if b { append("true") } else { append("false") }
            case .number(let s): out.append(contentsOf: s.utf8)
            case .string(let s): JSONSerializer.writeString(s, to: &out, options: options)
            case .array(let a):
                if a.isEmpty { append("[]"); return }
                out.append(0x5B)
                if pretty { out.append(0x0A) }
                let last = a.count - 1
                for (i, item) in a.enumerated() {
                    try tick()
                    pad(level + 1)
                    try write(item, level: level + 1)
                    if i < last { out.append(0x2C) }
                    if pretty { out.append(0x0A) }
                }
                pad(level)
                out.append(0x5D)
            case .object(let o):
                if o.isEmpty { append("{}"); return }
                out.append(0x7B)
                if pretty { out.append(0x0A) }
                let last = o.count - 1
                for (i, pair) in o.enumerated() {
                    try tick()
                    pad(level + 1)
                    JSONSerializer.writeString(pair.key, to: &out, options: options)
                    out.append(0x3A)
                    if pretty && options.spaceAfterColon { out.append(0x20) }
                    try write(pair.value, level: level + 1)
                    if i < last { out.append(0x2C) }
                    if pretty { out.append(0x0A) }
                }
                pad(level)
                out.append(0x7D)
            }
        }
    }

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    private static func appendUnicodeEscape(_ v: UInt32, to out: inout [UInt8]) {
        out.append(0x5C); out.append(0x75)
        out.append(hexDigits[Int((v >> 12) & 0xF)]); out.append(hexDigits[Int((v >> 8) & 0xF)])
        out.append(hexDigits[Int((v >> 4) & 0xF)]); out.append(hexDigits[Int(v & 0xF)])
    }

    /// Appends the quoted, escaped form of `s` as UTF-8 bytes.
    static func writeString(_ s: String, to out: inout [UInt8], options: JSONSerializerOptions) {
        out.append(0x22)
        var s = s
        s.withUTF8 { buf in
            let n = buf.count
            var runStart = 0
            var i = 0
            @inline(__always) func flush(upTo end: Int) {
                if end > runStart { out.append(contentsOf: UnsafeBufferPointer(rebasing: buf[runStart..<end])) }
            }
            while i < n {
                let b = buf[i]
                if b >= 0x20, b != 0x22, b != 0x5C, b != 0x7F, b != 0x2F, b < 0x80 { i += 1; continue }
                if b >= 0x80 {
                    // Multi-byte scalar: only U+2028/2029 always escape; everything else only when escapeNonASCII.
                    if !options.escapeNonASCII {
                        if b == 0xE2, i + 2 < n, buf[i + 1] == 0x80, buf[i + 2] == 0xA8 || buf[i + 2] == 0xA9 {
                            flush(upTo: i)
                            appendUnicodeEscape(buf[i + 2] == 0xA8 ? 0x2028 : 0x2029, to: &out)
                            i += 3; runStart = i
                        } else {
                            i += 1
                        }
                        continue
                    }
                    flush(upTo: i)
                    let len = b >= 0xF0 ? 4 : (b >= 0xE0 ? 3 : 2)
                    let end = Swift.min(i + len, n)
                    let scalar = String(decoding: UnsafeBufferPointer(rebasing: buf[i..<end]), as: UTF8.self).unicodeScalars.first!   // swiftlint:disable:this force_unwrapping
                    let v = scalar.value
                    if v > 0xFFFF {
                        let w = v - 0x10000
                        appendUnicodeEscape(0xD800 + (w >> 10), to: &out)
                        appendUnicodeEscape(0xDC00 + (w & 0x3FF), to: &out)
                    } else {
                        appendUnicodeEscape(v, to: &out)
                    }
                    i = end; runStart = i
                    continue
                }
                if b == 0x2F, !options.escapeSlashes { i += 1; continue }
                flush(upTo: i)
                switch b {
                case 0x22: out.append(0x5C); out.append(0x22)
                case 0x5C: out.append(0x5C); out.append(0x5C)
                case 0x2F: out.append(0x5C); out.append(0x2F)
                case 0x0A: out.append(0x5C); out.append(0x6E)
                case 0x0D: out.append(0x5C); out.append(0x72)
                case 0x09: out.append(0x5C); out.append(0x74)
                case 0x08: out.append(0x5C); out.append(0x62)
                case 0x0C: out.append(0x5C); out.append(0x66)
                default: appendUnicodeEscape(UInt32(b), to: &out)
                }
                i += 1; runStart = i
            }
            flush(upTo: n)
        }
        out.append(0x22)
    }

    public static func writeString(_ s: String, to out: inout String, options: JSONSerializerOptions) {
        var bytes: [UInt8] = []
        writeString(s, to: &bytes, options: options)
        out += String(decoding: bytes, as: UTF8.self)
    }

    public static func quoted(_ s: String) -> String {
        var out = ""
        writeString(s, to: &out, options: .pretty)
        return out
    }
}
