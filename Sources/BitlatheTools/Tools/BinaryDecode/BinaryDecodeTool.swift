import Foundation
import BitlatheCore

public struct BinaryDecodeTool: DevTool {
    public static let id = "binary.decode"
    public static let name = "MessagePack / CBOR / Protobuf"
    public static let summary = "Decode MessagePack, CBOR or schemaless Protobuf (hex, Base64 or raw bytes) to JSON — and encode JSON back"
    public static let category = ToolCategory.encode
    public static let symbol = "shippingbox.circle"
    public static let keywords = ["messagepack", "msgpack", "cbor", "protobuf", "proto", "binary", "decode", "json", "wire"]
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: true, inputLanguage: .plain, outputLanguage: .json)
    public static let samples = [ToolSample("MessagePack hex", "82 a4 6e 61 6d 65 a8 42 69 74 6c 61 74 68 65 a4 74 61 67 73 92 a3 6d 61 63 a3 64 65 76"),
                                 ToolSample("CBOR hex", "a2646e616d6568426974 6c6174686565636f756e7418 2a", options: ["format": .string("cbor")]),
                                 ToolSample("Protobuf hex", "0a03416461 10 2a 1a 05 68656c6c6f", options: ["format": .string("protobuf")]),
                                 ToolSample("JSON → MessagePack", #"{"id":7,"name":"Ada","ok":true}"#, options: ["mode": .string("encode")])]
    public static let optionFields: [OptionField] = [
        .mode([.init("decode", "Decode → JSON"), .init("encode", "JSON → bytes")], default: "decode"),
        .segmented("format", "Format", [.init("auto", "Auto"), .init("msgpack", "MessagePack"), .init("cbor", "CBOR"), .init("protobuf", "Protobuf")], default: "auto"),
        .segmented("wrap", "Bytes as", [.init("auto", "Auto"), .init("hex", "Hex"), .init("base64", "Base64")], default: "auto"),
    ]
    public struct Options: ToolOptions {
        public var mode = "decode"
        public var format = "auto"
        public var wrap = "auto"
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        if options.mode == "encode" {
            let v = try JSONParser.parse(input.text, options: .json5)
            let fmt = options.format == "cbor" ? "cbor" : "msgpack"
            if options.format == "protobuf" { throw ToolError("Encoding Protobuf needs a schema", hint: "Use MessagePack or CBOR for schemaless encoding") }
            let data = fmt == "cbor" ? CBOR.encode(v) : MessagePack.encode(v)
            let meta = [MetaRow("Format", fmt == "cbor" ? "CBOR" : "MessagePack"), MetaRow("Bytes", "\(data.count)"), MetaRow("JSON size", "\(input.text.utf8.count) bytes")]
            let text = options.wrap == "base64" ? data.base64EncodedString() : data.hexString
            return ToolOutput(text: text, language: .hex, facets: [OutputFacet("Hex", text: data.hexString), OutputFacet("Base64", text: data.base64EncodedString())], metadata: meta)
        }
        var data: Data
        switch input.payload {
        case .text(let t):
            let s = t.trimmed()
            guard !s.isEmpty else { throw ToolError.emptyInput }
            if options.wrap == "hex" { guard let d = Data(hex: s) else { throw ToolError("Invalid hex") }; data = d }
            else if options.wrap == "base64" { data = try Base64TextTool.decode(s) }
            else if Detect.isHex(s), let d = Data(hex: s) { data = d }
            else if let d = try? Base64TextTool.decode(s) { data = d }
            else { throw ToolError("Input is neither hex nor Base64", hint: "Paste bytes as hex (0a 03 …) or Base64, or drop a file") }
        default:
            data = input.data
        }
        guard !data.isEmpty else { throw ToolError.emptyInput }
        var format = options.format
        if format == "auto" {
            if let v = try? MessagePack.decode(data), case .object = v { format = "msgpack" }
            else if let v = try? CBOR.decode(data), case .object = v { format = "cbor" }
            else if (try? Protobuf.decode(data)) != nil, data.first.map({ $0 & 0x07 <= 5 && $0 >> 3 > 0 }) == true { format = "protobuf" }
            else if (try? MessagePack.decode(data)) != nil { format = "msgpack" }
            else if (try? CBOR.decode(data)) != nil { format = "cbor" }
            else { format = "protobuf" }
        }
        let value: JSONValue
        switch format {
        case "cbor": value = try CBOR.decode(data)
        case "protobuf": value = try Protobuf.decode(data)
        default: value = try MessagePack.decode(data)
        }
        let name = format == "cbor" ? "CBOR" : (format == "protobuf" ? "Protobuf (schemaless)" : "MessagePack")
        var warnings: [String] = []
        if format == "protobuf" { warnings.append("Without a schema, field names are numbers and nested messages are guessed from valid sub-structures. Varints are shown unsigned.") }
        return ToolOutput(text: JSONSerializer.string(value), language: .json, metadata: [MetaRow("Format", name), MetaRow("Bytes", "\(data.count)")], warnings: warnings)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isHex(s, minLength: 4), let d = Data(hex: s), let first = d.first else { return nil }
        if (first >= 0x80 && first <= 0x8F) || first == 0xDE || first == 0xDF || (first >= 0x90 && first <= 0x9F) {
            if let v = try? MessagePack.decode(d), v.count > 0 { return DetectionScore(0.75, "MessagePack bytes", options: ["format": .string("msgpack")]) }
        }
        if (first >= 0xA0 && first <= 0xBF) || first == 0xBF {
            if let v = try? CBOR.decode(d), v.count > 0 { return DetectionScore(0.75, "CBOR bytes", options: ["format": .string("cbor")]) }
        }
        if first & 0x07 == 2 || first & 0x07 == 0, first >> 3 > 0, first >> 3 < 32, (try? Protobuf.decode(d)) != nil, d.count >= 4 {
            return DetectionScore(0.45, "Possible Protobuf message", options: ["format": .string("protobuf")])
        }
        return nil
    }
}

// MARK: - Byte reader

struct ByteReader {
    let bytes: [UInt8]
    var pos = 0
    /// Current container nesting; decoders call `enter()` so hostile input cannot overflow the stack.
    var depth = 0
    static let maxDepth = 128
    init(_ d: Data) { bytes = [UInt8](d) }
    mutating func enter() throws {
        depth += 1
        if depth > Self.maxDepth { throw ToolError("Nesting is deeper than \(Self.maxDepth) levels") }
    }
    var isAtEnd: Bool { pos >= bytes.count }
    var remaining: Int { bytes.count - pos }

    mutating func byte() throws -> UInt8 {
        guard pos < bytes.count else { throw ToolError("Unexpected end of data at byte \(pos)") }
        defer { pos += 1 }
        return bytes[pos]
    }
    mutating func take(_ n: Int) throws -> [UInt8] {
        guard n >= 0, pos + n <= bytes.count else { throw ToolError("Unexpected end of data at byte \(pos) (needed \(n) bytes)") }
        defer { pos += n }
        return Array(bytes[pos..<pos + n])
    }
    mutating func uint(_ n: Int) throws -> UInt64 {
        var v: UInt64 = 0
        for b in try take(n) { v = (v << 8) | UInt64(b) }
        return v
    }
    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let b = try byte()
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { throw ToolError("Varint too long") }
        }
    }
    static func string(_ bytes: [UInt8]) -> JSONValue {
        if let s = String(bytes: bytes, encoding: .utf8) { return .string(s) }
        return .object([(key: "$bytes", value: .string(Data(bytes).hexString))])
    }
    static func float32(_ v: UInt64) -> JSONValue { .number(Double(Float(bitPattern: UInt32(v)))) }
    static func float64(_ v: UInt64) -> JSONValue { .number(Double(bitPattern: v)) }
}

// MARK: - MessagePack

enum MessagePack {
    static func decode(_ data: Data) throws -> JSONValue {
        var r = ByteReader(data)
        let v = try value(&r)
        if !r.isAtEnd { throw ToolError("Trailing bytes after MessagePack value (\(r.remaining) bytes)") }
        return v
    }

    static func value(_ r: inout ByteReader) throws -> JSONValue {
        try r.enter()
        defer { r.depth -= 1 }
        let b = try r.byte()
        switch b {
        case 0x00...0x7F: return .number(Int(b))
        case 0x80...0x8F: return try map(&r, Int(b & 0x0F))
        case 0x90...0x9F: return try array(&r, Int(b & 0x0F))
        case 0xA0...0xBF: return ByteReader.string(try r.take(Int(b & 0x1F)))
        case 0xC0: return .null
        case 0xC2: return .bool(false)
        case 0xC3: return .bool(true)
        case 0xC4: return bin(try r.take(Int(try r.uint(1))))
        case 0xC5: return bin(try r.take(Int(try r.uint(2))))
        case 0xC6: return bin(try r.take(Int(try r.uint(4))))
        case 0xC7: let n = Int(try r.uint(1)); return try ext(&r, n)
        case 0xC8: let n = Int(try r.uint(2)); return try ext(&r, n)
        case 0xC9: let n = Int(try r.uint(4)); return try ext(&r, n)
        case 0xCA: return ByteReader.float32(try r.uint(4))
        case 0xCB: return ByteReader.float64(try r.uint(8))
        case 0xCC: return .number(String(try r.uint(1)))
        case 0xCD: return .number(String(try r.uint(2)))
        case 0xCE: return .number(String(try r.uint(4)))
        case 0xCF: return .number(String(try r.uint(8)))
        case 0xD0: return .number(String(Int8(bitPattern: UInt8(try r.uint(1)))))
        case 0xD1: return .number(String(Int16(bitPattern: UInt16(try r.uint(2)))))
        case 0xD2: return .number(String(Int32(bitPattern: UInt32(try r.uint(4)))))
        case 0xD3: return .number(String(Int64(bitPattern: try r.uint(8))))
        case 0xD4: return try ext(&r, 1)
        case 0xD5: return try ext(&r, 2)
        case 0xD6: return try ext(&r, 4)
        case 0xD7: return try ext(&r, 8)
        case 0xD8: return try ext(&r, 16)
        case 0xD9: return ByteReader.string(try r.take(Int(try r.uint(1))))
        case 0xDA: return ByteReader.string(try r.take(Int(try r.uint(2))))
        case 0xDB: return ByteReader.string(try r.take(Int(try r.uint(4))))
        case 0xDC: return try array(&r, Int(try r.uint(2)))
        case 0xDD: return try array(&r, Int(try r.uint(4)))
        case 0xDE: return try map(&r, Int(try r.uint(2)))
        case 0xDF: return try map(&r, Int(try r.uint(4)))
        case 0xE0...0xFF: return .number(Int(Int8(bitPattern: b)))
        default: throw ToolError(String(format: "Unknown MessagePack type 0x%02X at byte %d", b, r.pos - 1))
        }
    }

    static func bin(_ b: [UInt8]) -> JSONValue { .object([(key: "$bytes", value: .string(Data(b).hexString))]) }

    static func ext(_ r: inout ByteReader, _ n: Int) throws -> JSONValue {
        let type = Int8(bitPattern: try r.byte())
        let payload = try r.take(n)
        if type == -1 {
            // Timestamp extension
            var seconds: Int64 = 0
            var nanos: UInt32 = 0
            switch n {
            case 4: seconds = Int64(UInt32(payload[0]) << 24 | UInt32(payload[1]) << 16 | UInt32(payload[2]) << 8 | UInt32(payload[3]))
            case 8:
                let v = payload.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                nanos = UInt32(v >> 34)
                seconds = Int64(v & 0x3_FFFF_FFFF)
            case 12:
                nanos = payload[0..<4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                seconds = Int64(bitPattern: payload[4..<12].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
            default: break
            }
            let date = Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1e9)
            return .object([(key: "$timestamp", value: .string(ISO8601DateFormatter().string(from: date)))])
        }
        return .object([(key: "$ext", value: .number(Int(type))), (key: "data", value: .string(Data(payload).hexString))])
    }

    static func array(_ r: inout ByteReader, _ n: Int) throws -> JSONValue {
        var items: [JSONValue] = []
        items.reserveCapacity(min(n, 1024))
        for _ in 0..<n { items.append(try value(&r)) }
        return .array(items)
    }

    static func map(_ r: inout ByteReader, _ n: Int) throws -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = []
        for _ in 0..<n {
            let k = try value(&r)
            let v = try value(&r)
            pairs.append((key: k.stringValue ?? XMLJSON.scalar(k), value: v))
        }
        return .object(pairs)
    }

    static func encode(_ v: JSONValue) -> Data {
        var out = Data()
        write(v, &out)
        return out
    }

    static func write(_ v: JSONValue, _ out: inout Data) {
        func be(_ x: UInt64, _ n: Int) { for i in (0..<n).reversed() { out.append(UInt8((x >> UInt64(8 * i)) & 0xFF)) } }
        switch v {
        case .null: out.append(0xC0)
        case .bool(let b): out.append(b ? 0xC3 : 0xC2)
        case .number(let s):
            if let i = Int64(s) {
                if i >= 0 && i < 128 { out.append(UInt8(i)) }
                else if i < 0 && i >= -32 { out.append(UInt8(bitPattern: Int8(i))) }
                else if i >= 0 && i <= 0xFF { out.append(0xCC); be(UInt64(i), 1) }
                else if i >= 0 && i <= 0xFFFF { out.append(0xCD); be(UInt64(i), 2) }
                else if i >= 0 && i <= 0xFFFF_FFFF { out.append(0xCE); be(UInt64(i), 4) }
                else if i >= 0 { out.append(0xCF); be(UInt64(i), 8) }
                else if i >= Int64(Int8.min) { out.append(0xD0); be(UInt64(UInt8(bitPattern: Int8(i))), 1) }
                else if i >= Int64(Int16.min) { out.append(0xD1); be(UInt64(UInt16(bitPattern: Int16(i))), 2) }
                else if i >= Int64(Int32.min) { out.append(0xD2); be(UInt64(UInt32(bitPattern: Int32(i))), 4) }
                else { out.append(0xD3); be(UInt64(bitPattern: i), 8) }
            } else {
                out.append(0xCB); be((Double(s) ?? 0).bitPattern, 8)
            }
        case .string(let str):
            let b = Array(str.utf8)
            if b.count < 32 { out.append(0xA0 | UInt8(b.count)) }
            else if b.count <= 0xFF { out.append(0xD9); be(UInt64(b.count), 1) }
            else if b.count <= 0xFFFF { out.append(0xDA); be(UInt64(b.count), 2) }
            else { out.append(0xDB); be(UInt64(b.count), 4) }
            out.append(contentsOf: b)
        case .array(let a):
            if a.count < 16 { out.append(0x90 | UInt8(a.count)) }
            else if a.count <= 0xFFFF { out.append(0xDC); be(UInt64(a.count), 2) }
            else { out.append(0xDD); be(UInt64(a.count), 4) }
            for i in a { write(i, &out) }
        case .object(let o):
            if o.count < 16 { out.append(0x80 | UInt8(o.count)) }
            else if o.count <= 0xFFFF { out.append(0xDE); be(UInt64(o.count), 2) }
            else { out.append(0xDF); be(UInt64(o.count), 4) }
            for (k, val) in o { write(.string(k), &out); write(val, &out) }
        }
    }
}

// MARK: - CBOR

enum CBOR {
    static func decode(_ data: Data) throws -> JSONValue {
        var r = ByteReader(data)
        let v = try value(&r)
        if !r.isAtEnd { throw ToolError("Trailing bytes after CBOR value (\(r.remaining) bytes)") }
        return v
    }

    static func head(_ r: inout ByteReader, _ info: UInt8) throws -> UInt64? {
        switch info {
        case 0...23: return UInt64(info)
        case 24: return try r.uint(1)
        case 25: return try r.uint(2)
        case 26: return try r.uint(4)
        case 27: return try r.uint(8)
        case 31: return nil   // indefinite
        default: throw ToolError("Invalid CBOR additional info \(info)")
        }
    }

    static func value(_ r: inout ByteReader) throws -> JSONValue {
        try r.enter()
        defer { r.depth -= 1 }
        let b = try r.byte()
        let major = b >> 5
        let info = b & 0x1F
        switch major {
        case 0: return .number(String(try head(&r, info) ?? 0))
        case 1:
            let n = try head(&r, info) ?? 0
            return n <= UInt64(Int64.max) ? .number(String(-1 - Int64(n))) : .string("-\(n + 1)")
        case 2, 3:
            if let n = try head(&r, info) {
                let bytes = try r.take(Int(n))
                return major == 3 ? ByteReader.string(bytes) : MessagePack.bin(bytes)
            }
            var chunks: [UInt8] = []
            while true {
                guard let next = r.bytes[safe: r.pos] else { throw ToolError("Unterminated indefinite string") }
                if next == 0xFF { r.pos += 1; break }
                let h = try r.byte()
                let n = try head(&r, h & 0x1F) ?? 0
                chunks += try r.take(Int(n))
            }
            return major == 3 ? ByteReader.string(chunks) : MessagePack.bin(chunks)
        case 4:
            var items: [JSONValue] = []
            if let n = try head(&r, info) { for _ in 0..<n { items.append(try value(&r)) } }
            else { while r.bytes[safe: r.pos] != 0xFF { items.append(try value(&r)) }; r.pos += 1 }
            return .array(items)
        case 5:
            var pairs: [(key: String, value: JSONValue)] = []
            func pair() throws { let k = try value(&r); let v = try value(&r); pairs.append((key: k.stringValue ?? XMLJSON.scalar(k), value: v)) }
            if let n = try head(&r, info) { for _ in 0..<n { try pair() } }
            else { while r.bytes[safe: r.pos] != 0xFF { try pair() }; r.pos += 1 }
            return .object(pairs)
        case 6:
            let tag = try head(&r, info) ?? 0
            let inner = try value(&r)
            switch tag {
            case 0, 1:
                if tag == 1, let t = inner.doubleValue { return .object([(key: "$date", value: .string(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: t))))]) }
                return inner
            case 2, 3:
                if case .object(let o) = inner, let hex = o.first?.value.stringValue { return .object([(key: "$bignum", value: .string((tag == 3 ? "-" : "") + "0x" + hex))]) }
                return inner
            case 32: return inner
            default: return .object([(key: "$tag", value: .number(String(tag))), (key: "value", value: inner)])
            }
        case 7:
            switch info {
            case 20: return .bool(false)
            case 21: return .bool(true)
            case 22: return .null
            case 23: return .object([(key: "$undefined", value: .bool(true))])
            case 24: return .object([(key: "$simple", value: .number(String(try r.uint(1))))])
            case 25:
                let h = UInt16(try r.uint(2))
                return .number(Double(Self.halfToFloat(h)))
            case 26: return ByteReader.float32(try r.uint(4))
            case 27: return ByteReader.float64(try r.uint(8))
            case 31: throw ToolError("Unexpected CBOR break")
            default: return .object([(key: "$simple", value: .number(Int(info)))])
            }
        default:
            throw ToolError("Invalid CBOR major type")
        }
    }

    static func halfToFloat(_ h: UInt16) -> Float {
        let exp = Int((h >> 10) & 0x1F)
        let mant = Float(h & 0x3FF)
        let sign: Float = h & 0x8000 != 0 ? -1 : 1
        if exp == 0 { return sign * mant * pow(2, -24) }
        if exp == 31 { return mant == 0 ? sign * .infinity : .nan }
        return sign * (1 + mant / 1024) * pow(2, Float(exp - 15))
    }

    static func encode(_ v: JSONValue) -> Data {
        var out = Data()
        write(v, &out)
        return out
    }

    static func writeHead(_ major: UInt8, _ n: UInt64, _ out: inout Data) {
        let m = major << 5
        if n < 24 { out.append(m | UInt8(n)) }
        else if n <= 0xFF { out.append(m | 24); out.append(UInt8(n)) }
        else if n <= 0xFFFF { out.append(m | 25); out.append(UInt8(n >> 8)); out.append(UInt8(n & 0xFF)) }
        else if n <= 0xFFFF_FFFF { out.append(m | 26); for i in (0..<4).reversed() { out.append(UInt8((n >> UInt64(8 * i)) & 0xFF)) } }
        else { out.append(m | 27); for i in (0..<8).reversed() { out.append(UInt8((n >> UInt64(8 * i)) & 0xFF)) } }
    }

    static func write(_ v: JSONValue, _ out: inout Data) {
        switch v {
        case .null: out.append(0xF6)
        case .bool(let b): out.append(b ? 0xF5 : 0xF4)
        case .number(let s):
            if let i = Int64(s) { if i >= 0 { writeHead(0, UInt64(i), &out) } else { writeHead(1, UInt64(-1 - i), &out) } }
            else { out.append(0xFB); let bits = (Double(s) ?? 0).bitPattern; for i in (0..<8).reversed() { out.append(UInt8((bits >> UInt64(8 * i)) & 0xFF)) } }
        case .string(let str): let b = Array(str.utf8); writeHead(3, UInt64(b.count), &out); out.append(contentsOf: b)
        case .array(let a): writeHead(4, UInt64(a.count), &out); for i in a { write(i, &out) }
        case .object(let o): writeHead(5, UInt64(o.count), &out); for (k, val) in o { write(.string(k), &out); write(val, &out) }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Protobuf (schemaless)

enum Protobuf {
    static func decode(_ data: Data) throws -> JSONValue {
        var r = ByteReader(data)
        return try message(&r, depth: 0)
    }

    static func message(_ r: inout ByteReader, depth: Int) throws -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = []
        while !r.isAtEnd {
            let tag = try r.varint()
            let field = Int(tag >> 3)
            let wire = tag & 0x07
            guard field > 0 else { throw ToolError("Invalid field number 0") }
            let v: JSONValue
            switch wire {
            case 0:
                let n = try r.varint()
                v = n > UInt64(Int64.max) ? .string(String(n)) : .number(String(n))
            case 1:
                let bits = try r.uint(8).byteSwapped
                let d = Double(bitPattern: bits)
                v = .object([(key: "$fixed64", value: .number(String(bits))), (key: "double", value: d.isFinite ? .number(d) : .string("\(d)"))])
            case 2:
                let len = Int(try r.varint())
                let bytes = try r.take(len)
                if depth < 16, !bytes.isEmpty, let nested = try? Protobuf.decodeStrict(Data(bytes), depth: depth + 1) {
                    v = nested
                } else if let s = String(bytes: bytes, encoding: .utf8), s.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0 == "\n" || $0 == "\t" }) {
                    v = .string(s)
                } else {
                    v = .object([(key: "$bytes", value: .string(Data(bytes).hexString))])
                }
            case 5:
                let bits = UInt32(try r.uint(4)).byteSwapped
                v = .object([(key: "$fixed32", value: .number(String(bits))), (key: "float", value: .number(Double(Float(bitPattern: bits))))])
            case 3, 4:
                throw ToolError("Deprecated group wire types are not supported")
            default:
                throw ToolError("Invalid wire type \(wire) at byte \(r.pos)")
            }
            let key = String(field)
            if let i = fields.firstIndex(where: { $0.key == key }) {
                if case .array(var arr) = fields[i].value, fields[i].value.arrayValue != nil, (fields[i].value.arrayValue?.first.map { _ in true } ?? false) { arr.append(v); fields[i].value = .array(arr) }
                else { fields[i].value = .array([fields[i].value, v]) }
            } else {
                fields.append((key: key, value: v))
            }
        }
        return .object(fields)
    }

    /// Strict decode used to decide if bytes are a nested message: every field must be plausible.
    static func decodeStrict(_ data: Data, depth: Int) throws -> JSONValue {
        var r = ByteReader(data)
        let v = try message(&r, depth: depth)
        guard case .object(let o) = v, !o.isEmpty, o.allSatisfy({ (Int($0.key) ?? 0) < 10000 }) else { throw ToolError("not a message") }
        return v
    }
}
