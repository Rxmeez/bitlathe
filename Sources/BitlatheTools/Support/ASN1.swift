import Foundation
import BitlatheCore

/// Minimal DER parser/encoder for certificates, CSRs and keys.
public indirect enum ASN1: Sendable, Equatable {
    case sequence([ASN1])
    case set([ASN1])
    case integer(Data)
    case bitString(unused: Int, Data)
    case octetString(Data)
    case null
    case objectIdentifier(String)
    case utf8String(String)
    case printableString(String)
    case ia5String(String)
    case t61String(String)
    case bmpString(String)
    case utcTime(Date)
    case generalizedTime(Date)
    case boolean(Bool)
    case contextSpecific(tag: Int, constructed: Bool, [ASN1], raw: Data)
    case unknown(tag: UInt8, Data)

    public var children: [ASN1] {
        switch self {
        case .sequence(let c), .set(let c): c
        case .contextSpecific(_, _, let c, _): c
        default: []
        }
    }
    public var data: Data? {
        switch self {
        case .integer(let d), .octetString(let d): d
        case .bitString(_, let d): d
        case .contextSpecific(_, _, _, let raw): raw
        default: nil
        }
    }
    public var string: String? {
        switch self {
        case .utf8String(let s), .printableString(let s), .ia5String(let s), .t61String(let s), .bmpString(let s): s
        case .objectIdentifier(let s): s
        default: nil
        }
    }
    public var oid: String? { if case .objectIdentifier(let s) = self { return s } else { return nil } }
    public var date: Date? {
        switch self {
        case .utcTime(let d), .generalizedTime(let d): d
        default: nil
        }
    }
    public subscript(i: Int) -> ASN1? { children.indices.contains(i) ? children[i] : nil }

    // MARK: Parsing

    public static func parse(_ data: Data) throws -> ASN1 {
        var r = ByteReader(data)
        let v = try parseOne(&r)
        return v
    }

    public static func parseAll(_ data: Data) throws -> [ASN1] {
        var r = ByteReader(data)
        var out: [ASN1] = []
        while !r.isAtEnd { out.append(try parseOne(&r)) }
        return out
    }

    static func parseOne(_ r: inout ByteReader) throws -> ASN1 {
        let tag = try r.byte()
        var len = Int(try r.byte())
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n <= 4, n > 0 else { throw ToolError("Invalid DER length") }
            len = Int(try r.uint(n))
        }
        let content = Data(try r.take(len))
        let cls = tag >> 6
        let constructed = tag & 0x20 != 0
        let number = Int(tag & 0x1F)
        if cls == 2 {
            let children = constructed ? ((try? parseAll(content)) ?? []) : []
            return .contextSpecific(tag: number, constructed: constructed, children, raw: content)
        }
        if cls != 0 { return .unknown(tag: tag, content) }
        switch number {
        case 0x01: return .boolean(content.first != 0)
        case 0x02: return .integer(content)
        case 0x03:
            guard let unused = content.first else { return .bitString(unused: 0, Data()) }
            return .bitString(unused: Int(unused), content.dropFirst())
        case 0x04: return .octetString(content)
        case 0x05: return .null
        case 0x06: return .objectIdentifier(decodeOID(content))
        case 0x0C: return .utf8String(String(decoding: content, as: UTF8.self))
        case 0x10: return .sequence(try parseAll(content))
        case 0x11: return .set(try parseAll(content))
        case 0x13: return .printableString(String(decoding: content, as: UTF8.self))
        case 0x14: return .t61String(String(data: content, encoding: .isoLatin1) ?? "")
        case 0x16: return .ia5String(String(decoding: content, as: UTF8.self))
        case 0x1E: return .bmpString(String(data: content, encoding: .utf16BigEndian) ?? "")
        case 0x17: return .utcTime(parseTime(String(decoding: content, as: UTF8.self), utc: true))
        case 0x18: return .generalizedTime(parseTime(String(decoding: content, as: UTF8.self), utc: false))
        default: return .unknown(tag: tag, content)
        }
    }

    static func parseTime(_ s: String, utc: Bool) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        var t = s
        if t.hasSuffix("Z") { t.removeLast() }
        if let dot = t.firstIndex(of: ".") { t = String(t[..<dot]) }
        f.dateFormat = utc ? "yyMMddHHmmss" : "yyyyMMddHHmmss"
        if let d = f.date(from: t) { return d }
        f.dateFormat = utc ? "yyMMddHHmm" : "yyyyMMddHHmm"
        return f.date(from: t) ?? .distantPast
    }

    public static func decodeOID(_ d: Data) -> String {
        guard let first = d.first else { return "" }
        var parts = [String(Int(first) / 40), String(Int(first) % 40)]
        if first >= 80 { parts = ["2", String(Int(first) - 80)] }
        var v = 0
        for b in d.dropFirst() {
            v = (v << 7) | Int(b & 0x7F)
            if b & 0x80 == 0 { parts.append(String(v)); v = 0 }
        }
        return parts.joined(separator: ".")
    }

    public static func encodeOID(_ s: String) -> Data {
        let nums = s.split(separator: ".").compactMap { Int($0) }
        guard nums.count >= 2 else { return Data() }
        var out = Data([UInt8(nums[0] * 40 + nums[1])])
        for n in nums.dropFirst(2) {
            var bytes: [UInt8] = [UInt8(n & 0x7F)]
            var v = n >> 7
            while v > 0 { bytes.insert(UInt8(v & 0x7F) | 0x80, at: 0); v >>= 7 }
            out.append(contentsOf: bytes)
        }
        return out
    }

    // MARK: Encoding

    public var encoded: Data {
        func tlv(_ tag: UInt8, _ content: Data) -> Data {
            var out = Data([tag])
            let n = content.count
            if n < 0x80 { out.append(UInt8(n)) }
            else {
                var lenBytes: [UInt8] = []
                var v = n
                while v > 0 { lenBytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
                out.append(0x80 | UInt8(lenBytes.count))
                out.append(contentsOf: lenBytes)
            }
            out.append(content)
            return out
        }
        switch self {
        case .sequence(let c): return tlv(0x30, c.reduce(Data()) { $0 + $1.encoded })
        case .set(let c): return tlv(0x31, c.reduce(Data()) { $0 + $1.encoded })
        case .integer(let d):
            var v = d
            if let f = v.first, f & 0x80 != 0 { v.insert(0, at: 0) }
            while v.count > 1, v[v.startIndex] == 0, v[v.startIndex + 1] & 0x80 == 0 { v.removeFirst() }
            return tlv(0x02, v.isEmpty ? Data([0]) : v)
        case .bitString(let unused, let d): return tlv(0x03, Data([UInt8(unused)]) + d)
        case .octetString(let d): return tlv(0x04, d)
        case .null: return Data([0x05, 0x00])
        case .objectIdentifier(let s): return tlv(0x06, ASN1.encodeOID(s))
        case .utf8String(let s): return tlv(0x0C, Data(s.utf8))
        case .printableString(let s): return tlv(0x13, Data(s.utf8))
        case .ia5String(let s): return tlv(0x16, Data(s.utf8))
        case .t61String(let s): return tlv(0x14, Data(s.utf8))
        case .bmpString(let s): return tlv(0x1E, s.data(using: .utf16BigEndian) ?? Data())
        case .boolean(let b): return tlv(0x01, Data([b ? 0xFF : 0x00]))
        case .utcTime(let d), .generalizedTime(let d):
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMddHHmmss'Z'"
            return tlv(0x18, Data(f.string(from: d).utf8))
        case .contextSpecific(let tag, let constructed, let children, let raw):
            return tlv(0x80 | (constructed ? 0x20 : 0) | UInt8(tag), constructed && !children.isEmpty ? children.reduce(Data()) { $0 + $1.encoded } : raw)
        case .unknown(let tag, let d): return tlv(tag, d)
        }
    }
}

// MARK: - PEM

public enum PEM {
    public struct Block: Sendable, Equatable {
        public var label: String
        public var data: Data
        public var headers: [String: String]
    }

    public static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let l = lines[i].trimmed()
            if l.hasPrefix("-----BEGIN "), l.hasSuffix("-----") {
                let label = String(l.dropFirst(11).dropLast(5))
                var body = ""
                var headers: [String: String] = [:]
                i += 1
                while i < lines.count, !lines[i].trimmed().hasPrefix("-----END") {
                    let line = lines[i].trimmed()
                    if let c = line.firstIndex(of: ":"), line.range(of: "^[A-Za-z-]+:", options: .regularExpression) != nil { headers[String(line[..<c])] = line[line.index(after: c)...].trimmed() }
                    else { body += line }
                    i += 1
                }
                if let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters) { blocks.append(Block(label: label, data: data, headers: headers)) }
            }
            i += 1
        }
        return blocks
    }

    public static func encode(_ data: Data, label: String) -> String {
        let b64 = data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN \(label)-----\n\(b64)\n-----END \(label)-----"
    }
}

// MARK: - OIDs

public enum OID {
    public static let names: [String: String] = [
        "2.5.4.3": "CN", "2.5.4.6": "C", "2.5.4.7": "L", "2.5.4.8": "ST", "2.5.4.10": "O", "2.5.4.11": "OU", "2.5.4.5": "serialNumber", "2.5.4.4": "SN", "2.5.4.42": "GN",
        "2.5.4.12": "title", "2.5.4.9": "street", "2.5.4.17": "postalCode", "2.5.4.15": "businessCategory", "1.2.840.113549.1.9.1": "emailAddress", "0.9.2342.19200300.100.1.25": "DC", "0.9.2342.19200300.100.1.1": "UID",
        "1.3.6.1.4.1.311.60.2.1.3": "jurisdictionC", "1.3.6.1.4.1.311.60.2.1.2": "jurisdictionST", "1.3.6.1.4.1.311.60.2.1.1": "jurisdictionL",
        "1.2.840.113549.1.1.1": "RSA", "1.2.840.113549.1.1.5": "SHA-1 with RSA", "1.2.840.113549.1.1.11": "SHA-256 with RSA", "1.2.840.113549.1.1.12": "SHA-384 with RSA", "1.2.840.113549.1.1.13": "SHA-512 with RSA",
        "1.2.840.113549.1.1.10": "RSA-PSS", "1.2.840.10045.2.1": "EC", "1.2.840.10045.4.3.2": "ECDSA with SHA-256", "1.2.840.10045.4.3.3": "ECDSA with SHA-384", "1.2.840.10045.4.3.4": "ECDSA with SHA-512", "1.2.840.10045.4.1": "ECDSA with SHA-1",
        "1.3.101.112": "Ed25519", "1.3.101.113": "Ed448", "1.3.101.110": "X25519", "1.2.840.10045.3.1.7": "P-256", "1.3.132.0.34": "P-384", "1.3.132.0.35": "P-521", "1.3.132.0.10": "secp256k1",
        "2.5.29.14": "Subject Key Identifier", "2.5.29.15": "Key Usage", "2.5.29.17": "Subject Alternative Name", "2.5.29.18": "Issuer Alternative Name", "2.5.29.19": "Basic Constraints", "2.5.29.31": "CRL Distribution Points",
        "2.5.29.32": "Certificate Policies", "2.5.29.35": "Authority Key Identifier", "2.5.29.37": "Extended Key Usage", "1.3.6.1.5.5.7.1.1": "Authority Information Access", "1.3.6.1.4.1.11129.2.4.2": "SCT List (Certificate Transparency)",
        "2.5.29.30": "Name Constraints", "2.5.29.36": "Policy Constraints", "2.5.29.9": "Subject Directory Attributes", "1.3.6.1.5.5.7.1.24": "TLS Feature (OCSP Must-Staple)",
        "1.3.6.1.5.5.7.3.1": "TLS Web Server Authentication", "1.3.6.1.5.5.7.3.2": "TLS Web Client Authentication", "1.3.6.1.5.5.7.3.3": "Code Signing", "1.3.6.1.5.5.7.3.4": "Email Protection", "1.3.6.1.5.5.7.3.8": "Time Stamping", "1.3.6.1.5.5.7.3.9": "OCSP Signing",
        "1.3.6.1.5.5.7.48.1": "OCSP", "1.3.6.1.5.5.7.48.2": "CA Issuers", "2.23.140.1.2.1": "Domain Validated", "2.23.140.1.2.2": "Organization Validated", "2.23.140.1.1": "Extended Validation", "2.23.140.1.2.3": "Individual Validated",
        "1.2.840.113549.1.9.14": "Extension Request", "1.2.840.113549.1.9.7": "Challenge Password", "1.2.840.113549.1.9.2": "Unstructured Name",
        "2.16.840.1.101.3.4.2.1": "SHA-256", "2.16.840.1.101.3.4.2.2": "SHA-384", "2.16.840.1.101.3.4.2.3": "SHA-512", "1.3.14.3.2.26": "SHA-1", "1.2.840.113549.2.5": "MD5",
        "1.2.840.113549.1.5.13": "PBES2", "1.2.840.113549.1.5.12": "PBKDF2", "2.16.840.1.101.3.4.1.42": "AES-256-CBC", "2.16.840.1.101.3.4.1.2": "AES-128-CBC", "1.2.840.113549.2.9": "HMAC-SHA256",
    ]
    public static func name(_ oid: String) -> String { names[oid] ?? oid }
}
