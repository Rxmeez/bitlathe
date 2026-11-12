import Foundation
import CryptoKit
import BitlatheCore

public struct HashGeneratorTool: DevTool {
    public static let id = "hash.generate"
    public static let name = "Hash Generator"
    public static let summary = "MD5, SHA-1, SHA-2, SHA-3, Keccak, BLAKE2, BLAKE3, CRC32 and HMAC for text or files"
    public static let category = ToolCategory.generate
    public static let symbol = "number.square.fill"
    public static let keywords = ["hash", "md5", "sha1", "sha256", "sha512", "sha3", "keccak", "blake2", "blake3", "crc32", "hmac", "digest", "checksum"]
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: true)
    public static let samples = [ToolSample("Text", "The quick brown fox jumps over the lazy dog"), ToolSample("Empty string", " ")]
    public static let algorithms: [(String, String)] = [
        ("all", "All algorithms"), ("md5", "MD5"), ("sha1", "SHA-1"), ("sha256", "SHA-256"), ("sha384", "SHA-384"), ("sha512", "SHA-512"), ("sha512_256", "SHA-512/256"),
        ("sha3_224", "SHA3-224"), ("sha3_256", "SHA3-256"), ("sha3_384", "SHA3-384"), ("sha3_512", "SHA3-512"), ("keccak256", "Keccak-256 (Ethereum)"), ("shake128", "SHAKE128 (256-bit)"), ("shake256", "SHAKE256 (512-bit)"),
        ("blake2b", "BLAKE2b-512"), ("blake2b256", "BLAKE2b-256"), ("blake2s", "BLAKE2s-256"), ("blake3", "BLAKE3"), ("crc32", "CRC32"), ("adler32", "Adler-32"), ("sha256d", "SHA-256d (double)"),
    ]
    public static let optionFields: [OptionField] = [
        .picker("algorithm", "Algorithm", algorithms.map { OptionChoice($0.0, $0.1) }, default: "all"),
        .segmented("encoding", "Output", [.init("hex", "Hex"), .init("base64", "Base64"), .init("base64url", "Base64URL")], default: "hex"),
        .toggle("uppercase", "Uppercase", visibleWhen: ("encoding", ["hex"])),
        .toggle("hmac", "HMAC"),
        .secret("key", "Key", placeholder: "HMAC key", visibleWhen: ("hmac", ["true"])),
        .toggle("keyIsHex", "Key is hex", visibleWhen: ("hmac", ["true"]), advanced: true),
        .toggle("perLine", "Hash each line", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var algorithm = "all"
        public var encoding = "hex"
        public var uppercase = false
        public var hmac = false
        public var key = ""
        public var keyIsHex = false
        public var perLine = false
        public init() {}
    }
    public init() {}

    public static func digest(_ algo: String, _ data: Data, key: Data?) -> Data? {
        if let key {
            switch algo {
            case "md5": return Data(HMAC<Insecure.MD5>.authenticationCode(for: data, using: SymmetricKey(data: key)))
            case "sha1": return Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: SymmetricKey(data: key)))
            case "sha256": return Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
            case "sha384": return Data(HMAC<SHA384>.authenticationCode(for: data, using: SymmetricKey(data: key)))
            case "sha512": return Data(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: key)))
            case "sha3_256", "sha3_224", "sha3_384", "sha3_512", "keccak256", "blake2b", "blake2b256", "blake2s", "blake3":
                // Generic HMAC construction for algorithms CryptoKit lacks (BLAKE keyed modes are used natively).
                if algo == "blake2b" { return Blake2b.hash(data, outputLength: 64, key: key.prefix(64)) }
                if algo == "blake2b256" { return Blake2b.hash(data, outputLength: 32, key: key.prefix(64)) }
                if algo == "blake2s" { return Blake2s.hash(data, outputLength: 32, key: key.prefix(32)) }
                if algo == "blake3" { return Blake3.hash(data, key: key.count == 32 ? key : Data(SHA256.hash(data: key))) }
                let block = algo.contains("224") ? 144 : (algo.contains("384") ? 104 : (algo.contains("512") ? 72 : 136))
                var k = key.count > block ? digest(algo, key, key: nil)! : key   // swiftlint:disable:this force_unwrapping
                k += Data(repeating: 0, count: block - k.count)
                let ipad = Data(k.map { $0 ^ 0x36 }), opad = Data(k.map { $0 ^ 0x5C })
                return digest(algo, opad + digest(algo, ipad + data, key: nil)!, key: nil)   // swiftlint:disable:this force_unwrapping
            default: return nil
            }
        }
        switch algo {
        case "md5": return Hashing.md5(data)
        case "sha1": return Hashing.sha1(data)
        case "sha256": return Hashing.sha256(data)
        case "sha384": return Hashing.sha384(data)
        case "sha512": return Hashing.sha512(data)
        case "sha512_256": return Hashing.sha512(data).prefix(32).isEmpty ? nil : Data(SHA512_256Hasher.hash(data))
        case "sha3_224": return Keccak.sha3(data, bits: 224)
        case "sha3_256": return Keccak.sha3(data, bits: 256)
        case "sha3_384": return Keccak.sha3(data, bits: 384)
        case "sha3_512": return Keccak.sha3(data, bits: 512)
        case "keccak256": return Keccak.keccak(data, bits: 256)
        case "shake128": return Keccak.shake128(data, outputBytes: 32)
        case "shake256": return Keccak.shake256(data, outputBytes: 64)
        case "blake2b": return Blake2b.hash(data, outputLength: 64)
        case "blake2b256": return Blake2b.hash(data, outputLength: 32)
        case "blake2s": return Blake2s.hash(data, outputLength: 32)
        case "blake3": return Blake3.hash(data)
        case "crc32": var v = Compressor.crc32(data).bigEndian; return Data(bytes: &v, count: 4)
        case "adler32": var v = Compressor.adler32(data).bigEndian; return Data(bytes: &v, count: 4)
        case "sha256d": return Hashing.sha256d(data)
        default: return nil
        }
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        var data = input.data
        if case .text(let t) = input.payload, t == " " { data = Data() }   // "Empty string" sample
        guard !data.isEmpty || input.payload.kindName == "text" else { throw ToolError.emptyInput }
        var key: Data?
        if options.hmac {
            guard !options.key.isEmpty else { throw ToolError("Enter an HMAC key") }
            key = options.keyIsHex ? (Data(hex: options.key) ?? Data(options.key.utf8)) : Data(options.key.utf8)
        }
        func encode(_ d: Data) -> String {
            switch options.encoding {
            case "base64": d.base64EncodedString()
            case "base64url": d.base64URL
            default: options.uppercase ? d.hexString.uppercased() : d.hexString
            }
        }
        if options.perLine, options.algorithm != "all", case .text(let t) = input.payload {
            let lines = t.components(separatedBy: "\n")
            let out = lines.map { l in Self.digest(options.algorithm, Data(l.utf8), key: key).map(encode) ?? "" }
            return ToolOutput(text: out.joined(separator: "\n"), metadata: [MetaRow("Lines", "\(lines.count)")])
        }
        let algos = options.algorithm == "all" ? Self.algorithms.dropFirst().filter { !["sha512_256"].contains($0.0) || true } : Self.algorithms.filter { $0.0 == options.algorithm }
        var rows: [MetaRow] = [MetaRow("Input", "\(ByteFormatter.string(data.count))" + (input.fileName.map { " · \($0)" } ?? "") + (key != nil ? " · HMAC" : ""))]
        var facets: [OutputFacet] = []
        var primary = ""
        for (id, name) in algos {
            try Task.checkpoint()
            guard let d = Self.digest(id, data, key: key) else {
                if key != nil { rows.append(MetaRow(name, "HMAC not supported for this algorithm", style: .muted)) }
                continue
            }
            let s = encode(d)
            if primary.isEmpty || id == options.algorithm { primary = s }
            rows.append(MetaRow(name + (key != nil ? " (HMAC)" : ""), s, style: .mono))
            facets.append(OutputFacet(name, text: s))
        }
        let text = options.algorithm == "all" ? rows.dropFirst().map { "\($0.label.padding(toLength: 24, withPad: " ", startingAt: 0)) \($0.value)" }.joined(separator: "\n") : primary
        return ToolOutput(text: text, facets: facets, metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isSingleLine(s), s.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil else { return nil }
        switch s.count {
        case 32: return DetectionScore(0.4, "Looks like an MD5 digest")
        case 40: return DetectionScore(0.45, "Looks like a SHA-1 digest")
        case 64: return DetectionScore(0.45, "Looks like a SHA-256 digest")
        case 128: return DetectionScore(0.45, "Looks like a SHA-512 digest")
        default: return nil
        }
    }
}

/// SHA-512/256 via CryptoKit is unavailable; implement with the FIPS IVs on top of SHA-512's structure is non-trivial,
/// so derive from a tiny self-contained SHA-512 core.
enum SHA512_256Hasher {
    static let k: [UInt64] = [
        0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc, 0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
        0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2, 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
        0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65, 0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
        0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4, 0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
        0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df, 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
        0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
        0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
        0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec, 0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
        0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
        0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c, 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
    ]
    static let iv: [UInt64] = [0x22312194FC2BF72C, 0x9F555FA3C84C64C2, 0x2393B86B6F53B151, 0x963877195940EABD, 0x96283EE2A88EFFE3, 0xBE5E1E2553863992, 0x2B0199FC2C85B8AA, 0x0EB72DDC81C52CA2]

    static func hash(_ data: Data) -> Data {
        var msg = [UInt8](data)
        let bitLen = UInt64(msg.count) * 8
        msg.append(0x80)
        while msg.count % 128 != 112 { msg.append(0) }
        msg += [UInt8](repeating: 0, count: 8)
        for i in 0..<8 { msg.append(UInt8((bitLen >> UInt64(8 * (7 - i))) & 0xFF)) }
        var h = iv
        func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { (x >> n) | (x << (64 - n)) }
        for chunk in stride(from: 0, to: msg.count, by: 128) {
            var w = [UInt64](repeating: 0, count: 80)
            for i in 0..<16 { for j in 0..<8 { w[i] = (w[i] << 8) | UInt64(msg[chunk + i * 8 + j]) } }
            for i in 16..<80 {
                let s0 = rotr(w[i - 15], 1) ^ rotr(w[i - 15], 8) ^ (w[i - 15] >> 7)
                let s1 = rotr(w[i - 2], 19) ^ rotr(w[i - 2], 61) ^ (w[i - 2] >> 6)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<80 {
                let S1 = rotr(e, 14) ^ rotr(e, 18) ^ rotr(e, 41)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = rotr(a, 28) ^ rotr(a, 34) ^ rotr(a, 39)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = S0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        var out = Data()
        for v in h.prefix(4) { for i in 0..<8 { out.append(UInt8((v >> UInt64(8 * (7 - i))) & 0xFF)) } }
        return out
    }
}
