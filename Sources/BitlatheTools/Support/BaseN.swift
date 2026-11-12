import Foundation
import BitlatheCore

enum BaseN {
    // MARK: Base32 (RFC 4648) + Crockford + base32hex
    static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    static let base32HexAlphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUV")
    static let crockfordAlphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func base32Encode(_ data: Data, alphabet: [Character] = base32Alphabet, padding: Bool = true) -> String {
        var out = ""
        var buffer: UInt64 = 0
        var bits = 0
        for b in data {
            buffer = (buffer << 8) | UInt64(b)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(alphabet[Int((buffer >> UInt64(bits)) & 0x1F)])
            }
        }
        if bits > 0 { out.append(alphabet[Int((buffer << UInt64(5 - bits)) & 0x1F)]) }
        if padding { while out.count % 8 != 0 { out.append("=") } }
        return out
    }

    static func base32Decode(_ s: String, alphabet: [Character] = base32Alphabet) throws -> Data {
        var map: [Character: UInt64] = [:]
        for (i, c) in alphabet.enumerated() { map[c] = UInt64(i); map[Character(c.lowercased())] = UInt64(i) }
        if alphabet == crockfordAlphabet { map["O"] = 0; map["o"] = 0; map["I"] = 1; map["i"] = 1; map["L"] = 1; map["l"] = 1 }
        var out = Data()
        var buffer: UInt64 = 0
        var bits = 0
        for c in s where c != "=" && !c.isWhitespace && c != "-" {
            guard let v = map[c] else { throw ToolError("Invalid Base32 character '\(c)'") }
            buffer = (buffer << 5) | v
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> UInt64(bits)) & 0xFF))
            }
        }
        return out
    }

    // MARK: Base58 (Bitcoin alphabet)
    static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func base58Encode(_ data: Data) -> String {
        var bytes = [UInt8](data)
        var zeros = 0
        while zeros < bytes.count, bytes[zeros] == 0 { zeros += 1 }
        var digits: [UInt8] = []
        for b in bytes[zeros...] {
            var carry = Int(b)
            for i in 0..<digits.count {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 { digits.append(UInt8(carry % 58)); carry /= 58 }
        }
        bytes = []
        return String(repeating: "1", count: zeros) + String(digits.reversed().map { base58Alphabet[Int($0)] })
    }

    static func base58Decode(_ s: String) throws -> Data {
        var map: [Character: Int] = [:]
        for (i, c) in base58Alphabet.enumerated() { map[c] = i }
        var zeros = 0
        let chars = Array(s.filter { !$0.isWhitespace })
        while zeros < chars.count, chars[zeros] == "1" { zeros += 1 }
        var bytes: [UInt8] = []
        for c in chars[zeros...] {
            guard let v = map[c] else { throw ToolError("Invalid Base58 character '\(c)'", hint: "Base58 excludes 0, O, I and l") }
            var carry = v
            for i in 0..<bytes.count {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 { bytes.append(UInt8(carry & 0xFF)); carry >>= 8 }
        }
        return Data(repeating: 0, count: zeros) + Data(bytes.reversed())
    }

    // MARK: Base85 (Ascii85 + Z85 + RFC 1924)
    static let z85Alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#")
    static let rfc1924Alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~")

    static func ascii85Encode(_ data: Data, delimiters: Bool = true) -> String {
        var out = delimiters ? "<~" : ""
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            let chunk = Array(bytes[i..<min(i + 4, bytes.count)])
            let padding = 4 - chunk.count
            var v: UInt32 = 0
            for (k, b) in (chunk + Array(repeating: 0, count: padding)).enumerated() { v |= UInt32(b) << UInt32(8 * (3 - k)) }
            if v == 0 && padding == 0 { out.append("z") }
            else {
                var digits = [Character](repeating: "!", count: 5)
                var n = v
                for k in (0..<5).reversed() { digits[k] = Character(UnicodeScalar(UInt8(n % 85) + 33)); n /= 85 }
                out += String(digits.prefix(5 - padding))
            }
            i += 4
        }
        return out + (delimiters ? "~>" : "")
    }

    static func ascii85Decode(_ s: String) throws -> Data {
        var t = s.trimmed()
        if t.hasPrefix("<~") { t.removeFirst(2) }
        if t.hasSuffix("~>") { t.removeLast(2) }
        var out = Data()
        var group: [UInt32] = []
        func flush(_ g: [UInt32]) {
            let padding = 5 - g.count
            var v: UInt32 = 0
            for d in g + Array(repeating: 84, count: padding) { v = v &* 85 &+ d }
            let bytes = [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
            out.append(contentsOf: bytes.prefix(4 - padding))
        }
        for c in t where !c.isWhitespace {
            if c == "z", group.isEmpty { out.append(contentsOf: [0, 0, 0, 0]); continue }
            guard let a = c.asciiValue, a >= 33, a <= 117 else { throw ToolError("Invalid Ascii85 character '\(c)'") }
            group.append(UInt32(a) - 33)
            if group.count == 5 { flush(group); group = [] }
        }
        if group.count == 1 { throw ToolError("Invalid Ascii85 length") }
        if !group.isEmpty { flush(group) }
        return out
    }

    static func base85Encode(_ data: Data, alphabet: [Character]) -> String {
        var out = ""
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            let chunk = Array(bytes[i..<min(i + 4, bytes.count)])
            let padding = 4 - chunk.count
            var v: UInt32 = 0
            for (k, b) in (chunk + Array(repeating: 0, count: padding)).enumerated() { v |= UInt32(b) << UInt32(8 * (3 - k)) }
            var digits = [Character](repeating: "0", count: 5)
            var n = v
            for k in (0..<5).reversed() { digits[k] = alphabet[Int(n % 85)]; n /= 85 }
            out += String(digits.prefix(5 - padding))
            i += 4
        }
        return out
    }

    static func base85Decode(_ s: String, alphabet: [Character]) throws -> Data {
        var map: [Character: UInt32] = [:]
        for (i, c) in alphabet.enumerated() { map[c] = UInt32(i) }
        var out = Data()
        var group: [UInt32] = []
        func flush(_ g: [UInt32]) {
            let padding = 5 - g.count
            var v: UInt32 = 0
            for d in g + Array(repeating: 84, count: padding) { v = v &* 85 &+ d }
            let bytes = [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
            out.append(contentsOf: bytes.prefix(4 - padding))
        }
        for c in s where !c.isWhitespace {
            guard let v = map[c] else { throw ToolError("Invalid Base85 character '\(c)'") }
            group.append(v)
            if group.count == 5 { flush(group); group = [] }
        }
        if !group.isEmpty { flush(group) }
        return out
    }
}
