import Foundation
import CryptoKit
import BitlatheCore

public struct IDGeneratorTool: DevTool {
    public static let id = "id.generate"
    public static let name = "UUID / ULID / ID Generator"
    public static let summary = "Generate and decode UUID v1/v3/v4/v5/v7, ULID, Nano ID and MongoDB ObjectId"
    public static let category = ToolCategory.generate
    public static let symbol = "number.square"
    public static let keywords = ["uuid", "guid", "ulid", "nanoid", "objectid", "mongodb", "v4", "v7", "v5", "id", "generate", "decode", "unique"]
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: false)
    public static let samples = [ToolSample("Decode UUID v7", "0192f3a4-9b2c-7d3e-8f10-1a2b3c4d5e6f"), ToolSample("Decode ULID", "01HZ7K8N2Q3R4S5T6V7W8X9Y0Z"), ToolSample("Decode ObjectId", "65f1c2d3e4f5a6b7c8d9e0f1")]
    public static let optionFields: [OptionField] = [
        .mode([.init("generate", "Generate"), .init("decode", "Decode")], default: "generate"),
        .picker("kind", "Kind", [.init("uuid4", "UUID v4 (random)"), .init("uuid7", "UUID v7 (time-ordered)"), .init("uuid1", "UUID v1 (time + node)"), .init("uuid5", "UUID v5 (SHA-1 name)"), .init("uuid3", "UUID v3 (MD5 name)"),
                                 .init("ulid", "ULID"), .init("nanoid", "Nano ID"), .init("objectid", "MongoDB ObjectId"), .init("nil", "Nil / Max UUID")], default: "uuid4", visibleWhen: ("mode", ["generate"])),
        .stepper("count", "Count", min: 1, max: 1000, default: 5, visibleWhen: ("mode", ["generate"])),
        .toggle("uppercase", "Uppercase", visibleWhen: ("mode", ["generate"])),
        .toggle("hyphens", "Hyphens", default: true, visibleWhen: ("kind", ["uuid4", "uuid7", "uuid1", "uuid5", "uuid3", "nil"])),
        .toggle("braces", "Braces {…}", visibleWhen: ("kind", ["uuid4", "uuid7", "uuid1", "uuid5", "uuid3", "nil"]), advanced: true),
        .picker("namespace", "Namespace", [.init("dns", "DNS"), .init("url", "URL"), .init("oid", "OID"), .init("x500", "X.500"), .init("custom", "Custom UUID")], default: "dns", visibleWhen: ("kind", ["uuid5", "uuid3"])),
        .text("customNamespace", "Namespace UUID", placeholder: "6ba7b810-9dad-11d1-80b4-00c04fd430c8", visibleWhen: ("namespace", ["custom"])),
        .text("nameValue", "Name", placeholder: "example.com (or use the input)", visibleWhen: ("kind", ["uuid5", "uuid3"])),
        .stepper("nanoLength", "Length", min: 2, max: 128, default: 21, visibleWhen: ("kind", ["nanoid"])),
        .text("nanoAlphabet", "Alphabet", placeholder: "default: A-Za-z0-9_-", visibleWhen: ("kind", ["nanoid"]), advanced: true),
    ]
    public struct Options: ToolOptions {
        public var mode = "generate"
        public var kind = "uuid4"
        public var count = 5
        public var uppercase = false
        public var hyphens = true
        public var braces = false
        public var namespace = "dns"
        public var customNamespace = ""
        public var nameValue = ""
        public var nanoLength = 21
        public var nanoAlphabet = ""
        public init() {}
    }
    public init() {}

    static let namespaces: [String: String] = ["dns": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "url": "6ba7b811-9dad-11d1-80b4-00c04fd430c8", "oid": "6ba7b812-9dad-11d1-80b4-00c04fd430c8", "x500": "6ba7b814-9dad-11d1-80b4-00c04fd430c8"]
    static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func format(_ bytes: [UInt8]) -> String {
        let h = bytes.map { String(format: "%02x", $0) }.joined()
        return "\(h.prefix(8))-\(h.dropFirst(8).prefix(4))-\(h.dropFirst(12).prefix(4))-\(h.dropFirst(16).prefix(4))-\(h.dropFirst(20))"
    }

    public static func uuidV7(time: Date = .now) -> [UInt8] {
        let ms = UInt64(time.timeIntervalSince1970 * 1000)
        var b = (0..<16).map { _ in UInt8.random(in: 0...255) }
        for i in 0..<6 { b[i] = UInt8((ms >> UInt64(8 * (5 - i))) & 0xFF) }
        b[6] = (b[6] & 0x0F) | 0x70
        b[8] = (b[8] & 0x3F) | 0x80
        return b
    }

    public static func uuidV1() -> [UInt8] {
        // 100-ns intervals since 1582-10-15
        let ts = UInt64((Date().timeIntervalSince1970 + 12219292800) * 10_000_000)
        var b = [UInt8](repeating: 0, count: 16)
        let timeLow = UInt32(ts & 0xFFFF_FFFF), timeMid = UInt16((ts >> 32) & 0xFFFF), timeHi = UInt16((ts >> 48) & 0x0FFF) | 0x1000
        b[0] = UInt8(timeLow >> 24); b[1] = UInt8((timeLow >> 16) & 0xFF); b[2] = UInt8((timeLow >> 8) & 0xFF); b[3] = UInt8(timeLow & 0xFF)
        b[4] = UInt8(timeMid >> 8); b[5] = UInt8(timeMid & 0xFF); b[6] = UInt8(timeHi >> 8); b[7] = UInt8(timeHi & 0xFF)
        let clock = UInt16.random(in: 0...0x3FFF) | 0x8000
        b[8] = UInt8(clock >> 8); b[9] = UInt8(clock & 0xFF)
        // Random multicast node (privacy: never leak the real MAC)
        for i in 10..<16 { b[i] = UInt8.random(in: 0...255) }
        b[10] |= 0x01
        return b
    }

    public static func uuidNamed(namespace: [UInt8], name: String, version: Int) -> [UInt8] {
        let input = Data(namespace) + Data(name.utf8)
        var h = version == 3 ? [UInt8](Insecure.MD5.hash(data: input)) : [UInt8](Insecure.SHA1.hash(data: input).prefix(16))
        h[6] = (h[6] & 0x0F) | UInt8(version << 4)
        h[8] = (h[8] & 0x3F) | 0x80
        return h
    }

    public static func parseUUID(_ s: String) -> [UInt8]? {
        let clean = s.trimmed().replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "urn:uuid:", with: "")
        guard clean.count == 32, let d = Data(hex: clean) else { return nil }
        return [UInt8](d)
    }

    public static func ulid(time: Date = .now) -> String {
        let ms = UInt64(time.timeIntervalSince1970 * 1000)
        var out = ""
        for i in (0..<10).reversed() { out.append(crockford[Int((ms >> UInt64(5 * i)) & 0x1F)]) }
        var rnd = (0..<10).map { _ in UInt8.random(in: 0...255) }
        rnd[0] &= 0x7F
        var bits: UInt64 = 0
        var n = 0
        var tail = ""
        for b in rnd {
            bits = (bits << 8) | UInt64(b)
            n += 8
            while n >= 5 { n -= 5; tail.append(crockford[Int((bits >> UInt64(n)) & 0x1F)]) }
        }
        return out + tail
    }

    public static func objectId() -> String {
        let ts = UInt32(Date().timeIntervalSince1970)
        var b: [UInt8] = [UInt8(ts >> 24), UInt8((ts >> 16) & 0xFF), UInt8((ts >> 8) & 0xFF), UInt8(ts & 0xFF)]
        b += (0..<8).map { _ in UInt8.random(in: 0...255) }
        return b.map { String(format: "%02x", $0) }.joined()
    }

    public static func nanoid(length: Int, alphabet: String) -> String {
        let chars = Array(alphabet.isEmpty ? "useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict" : alphabet)
        var out = ""
        for _ in 0..<length { out.append(chars[Int.random(in: 0..<chars.count)]) }
        return out
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        if options.mode == "decode" || (!input.text.trimmed().isEmpty && options.mode == "generate" && ["uuid4", "uuid7", "uuid1", "ulid", "objectid", "nanoid", "nil"].contains(options.kind) && input.text.trimmed().count >= 20 && !input.text.contains("\n")) {
            return try decode(input.text.trimmed())
        }
        var ids: [String] = []
        for _ in 0..<options.count {
            var s: String
            switch options.kind {
            case "uuid7": s = Self.format(Self.uuidV7())
            case "uuid1": s = Self.format(Self.uuidV1())
            case "uuid5", "uuid3":
                let nsString = options.namespace == "custom" ? options.customNamespace : (Self.namespaces[options.namespace] ?? "")
                guard let ns = Self.parseUUID(nsString) else { throw ToolError("Invalid namespace UUID") }
                let name = options.nameValue.isEmpty ? input.text.trimmed() : options.nameValue
                guard !name.isEmpty else { throw ToolError("Enter a name to hash (e.g. example.com) in the options or the input") }
                s = Self.format(Self.uuidNamed(namespace: ns, name: name, version: options.kind == "uuid5" ? 5 : 3))
            case "ulid": s = Self.ulid()
            case "nanoid": s = Self.nanoid(length: options.nanoLength, alphabet: options.nanoAlphabet)
            case "objectid": s = Self.objectId()
            case "nil": s = ids.count % 2 == 0 ? "00000000-0000-0000-0000-000000000000" : "ffffffff-ffff-ffff-ffff-ffffffffffff"
            default: s = UUID().uuidString.lowercased()
            }
            if options.kind.hasPrefix("uuid") || options.kind == "nil" {
                if !options.hyphens { s = s.replacingOccurrences(of: "-", with: "") }
                if options.braces { s = "{\(s)}" }
            }
            if options.uppercase { s = s.uppercased() }
            if options.kind == "ulid" && !options.uppercase { s = s.uppercased() }
            ids.append(s)
            if options.kind == "uuid5" || options.kind == "uuid3" || options.kind == "nil" { if ids.count >= (options.kind == "nil" ? 2 : 1) { break } }
        }
        let facets = [OutputFacet("JSON array", text: JSONSerializer.string(.array(ids.map { .string($0) })), language: .json), OutputFacet("SQL list", text: ids.map { "'\($0)'" }.joined(separator: ", "))]
        return ToolOutput(text: ids.joined(separator: "\n"), facets: facets, metadata: [MetaRow("Generated", "\(ids.count)")])
    }

    func decode(_ text: String) throws -> ToolOutput {
        let lines = text.components(separatedBy: "\n").map { $0.trimmed() }.filter { !$0.isEmpty }
        var rows: [MetaRow] = []
        var out: [String] = []
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        for s in lines {
            if let b = Self.parseUUID(s) {
                let version = Int(b[6] >> 4)
                let variantBits = b[8] >> 5
                let variant = variantBits & 0b100 == 0 ? "NCS (reserved)" : (variantBits & 0b110 == 0b100 ? "RFC 4122 / 9562" : (variantBits == 0b110 ? "Microsoft" : "Future"))
                var desc = "UUID v\(version) · \(variant)"
                let allZero = b.allSatisfy { $0 == 0 }, allFF = b.allSatisfy { $0 == 0xFF }
                if allZero { desc = "Nil UUID" } else if allFF { desc = "Max UUID" }
                rows.append(MetaRow(s, desc))
                if version == 7, !allZero {
                    let ms = b[0..<6].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                    let d = Date(timeIntervalSince1970: Double(ms) / 1000)
                    rows.append(MetaRow("  Timestamp", "\(df.string(from: d)) (\(UnixTimeTool.relative(d))) · \(ms) ms"))
                    rows.append(MetaRow("  Random", Data(b[8...]).hexString.suffix(14) + " + " + String(format: "%03x", UInt16(b[6] & 0x0F) << 8 | UInt16(b[7])), style: .mono))
                } else if version == 1 {
                    let timeLow = UInt64(b[0]) << 24 | UInt64(b[1]) << 16 | UInt64(b[2]) << 8 | UInt64(b[3])
                    let timeMid = UInt64(b[4]) << 8 | UInt64(b[5])
                    let timeHi = UInt64(b[6] & 0x0F) << 8 | UInt64(b[7])
                    let ts = timeHi << 48 | timeMid << 32 | timeLow
                    let d = Date(timeIntervalSince1970: Double(ts) / 10_000_000 - 12219292800)
                    rows.append(MetaRow("  Timestamp", "\(df.string(from: d)) (\(UnixTimeTool.relative(d)))"))
                    rows.append(MetaRow("  Clock seq", String(format: "0x%04x", UInt16(b[8] & 0x3F) << 8 | UInt16(b[9])), style: .mono))
                    rows.append(MetaRow("  Node", b[10...].map { String(format: "%02x", $0) }.joined(separator: ":") + (b[10] & 1 == 1 ? " (random/multicast)" : " (MAC address)"), style: .mono))
                } else if version == 4 {
                    rows.append(MetaRow("  Random bits", "122"))
                } else if version == 3 || version == 5 {
                    rows.append(MetaRow("  Derived from", "\(version == 3 ? "MD5" : "SHA-1") of namespace + name"))
                }
                rows.append(MetaRow("  Hex", Data(b).hexString, style: .mono))
                rows.append(MetaRow("  Base64", Data(b).base64EncodedString(), style: .mono))
                rows.append(MetaRow("  URN", "urn:uuid:" + Self.format(b), style: .mono))
                out.append("\(s): \(desc)")
            } else if s.count == 26, s.uppercased().unicodeScalars.allSatisfy({ Self.crockford.contains(Character($0)) }) {
                var ms: UInt64 = 0
                for c in s.uppercased().prefix(10) { ms = ms * 32 + UInt64(Self.crockford.firstIndex(of: c) ?? 0) }
                let d = Date(timeIntervalSince1970: Double(ms) / 1000)
                rows.append(MetaRow(s, "ULID"))
                rows.append(MetaRow("  Timestamp", "\(df.string(from: d)) (\(UnixTimeTool.relative(d))) · \(ms) ms"))
                rows.append(MetaRow("  Randomness", String(s.suffix(16)) + " (80 bits)", style: .mono))
                out.append("\(s): ULID from \(df.string(from: d))")
            } else if s.count == 24, Detect.isHex(s) {
                let ts = UInt32(s.prefix(8), radix: 16) ?? 0
                let d = Date(timeIntervalSince1970: Double(ts))
                rows.append(MetaRow(s, "MongoDB ObjectId"))
                rows.append(MetaRow("  Timestamp", "\(df.string(from: d)) (\(UnixTimeTool.relative(d)))"))
                rows.append(MetaRow("  Process random", String(s.dropFirst(8).prefix(10)), style: .mono))
                rows.append(MetaRow("  Counter", String(Int(s.suffix(6), radix: 16) ?? 0), style: .mono))
                out.append("\(s): ObjectId from \(df.string(from: d))")
            } else {
                rows.append(MetaRow(s, "Not a recognised ID (\(s.count) chars)", style: .warning))
                out.append("\(s): unknown")
            }
        }
        return ToolOutput(text: out.joined(separator: "\n"), metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isSingleLine(s) else { return nil }
        if s.range(of: "^\\{?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\\}?$", options: .regularExpression) != nil { return DetectionScore(0.95, "UUID", options: ["mode": .string("decode")]) }
        if s.range(of: "^[0-7][0-9A-HJKMNP-TV-Z]{25}$", options: .regularExpression) != nil { return DetectionScore(0.85, "ULID", options: ["mode": .string("decode")]) }
        if s.range(of: "^[0-9a-f]{24}$", options: .regularExpression) != nil { return DetectionScore(0.6, "MongoDB ObjectId", options: ["mode": .string("decode")]) }
        return nil
    }
}
