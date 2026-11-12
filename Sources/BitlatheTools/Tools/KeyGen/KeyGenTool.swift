import Foundation
import CryptoKit
import BitlatheCore

public struct KeyGenTool: DevTool {
    public static let id = "key.generate"
    public static let name = "Key Generator"
    public static let summary = "Generate RSA, EC (P-256/384/521), Ed25519 and symmetric keys as PEM, JWK, OpenSSH or raw bytes"
    public static let category = ToolCategory.generate
    public static let symbol = "key"
    public static let keywords = ["key", "rsa", "ec", "p256", "ed25519", "pem", "jwk", "ssh", "keypair", "generate", "private key", "public key", "secret"]
    public static let io = ToolIO.generator
    public static let sideEffects = false
    public static let optionFields: [OptionField] = [
        .picker("kind", "Type", [.init("ed25519", "Ed25519"), .init("p256", "EC P-256"), .init("p384", "EC P-384"), .init("p521", "EC P-521"), .init("rsa2048", "RSA 2048"), .init("rsa3072", "RSA 3072"), .init("rsa4096", "RSA 4096"), .init("symmetric", "Symmetric (random bytes)")], default: "ed25519"),
        .segmented("format", "Format", [.init("pem", "PEM"), .init("jwk", "JWK"), .init("ssh", "OpenSSH"), .init("all", "All")], default: "pem", visibleWhen: ("kind", ["ed25519", "p256", "p384", "p521", "rsa2048", "rsa3072", "rsa4096"])),
        .picker("symmetricBits", "Size", [.init("128", "128-bit"), .init("192", "192-bit"), .init("256", "256-bit"), .init("512", "512-bit")], default: "256", visibleWhen: ("kind", ["symmetric"])),
        .text("comment", "SSH comment", placeholder: "you@host", visibleWhen: ("format", ["ssh", "all"])),
        .text("kid", "JWK kid", placeholder: "key id", visibleWhen: ("format", ["jwk", "all"]), advanced: true),
    ]
    public struct Options: ToolOptions {
        public var kind = "ed25519"
        public var format = "pem"
        public var symmetricBits = "256"
        public var comment = ""
        public var kid = ""
        public init() {}
    }
    public init() {}

    static func openssh(_ key: CryptoKeys.Key, comment: String) -> String? {
        func field(_ d: Data) -> Data { var n = UInt32(d.count).bigEndian; return Data(bytes: &n, count: 4) + d }
        var blob: Data
        var type: String
        switch key {
        case .ed25519Public(let k): type = "ssh-ed25519"; blob = field(Data(type.utf8)) + field(k.rawRepresentation)
        case .p256Public(let k): type = "ecdsa-sha2-nistp256"; blob = field(Data(type.utf8)) + field(Data("nistp256".utf8)) + field(k.x963Representation)
        case .p384Public(let k): type = "ecdsa-sha2-nistp384"; blob = field(Data(type.utf8)) + field(Data("nistp384".utf8)) + field(k.x963Representation)
        case .p521Public(let k): type = "ecdsa-sha2-nistp521"; blob = field(Data(type.utf8)) + field(Data("nistp521".utf8)) + field(k.x963Representation)
        case .rsaPublic(let k, _):
            guard let pkcs1 = SecKeyCopyExternalRepresentation(k, nil) as Data?, case .sequence(let items) = (try? ASN1.parse(pkcs1)) ?? .null, items.count == 2, let n = items[0].data, let e = items[1].data else { return nil }
            type = "ssh-rsa"
            func mpint(_ d: Data) -> Data { var v = d; if let f = v.first, f & 0x80 != 0 { v.insert(0, at: 0) }; return field(v) }
            blob = field(Data(type.utf8)) + mpint(e) + mpint(n)
        default: return nil
        }
        return "\(type) \(blob.base64EncodedString())\(comment.isEmpty ? "" : " " + comment)"
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        if options.kind == "symmetric" {
            let bytes = (Int(options.symmetricBits) ?? 256) / 8
            let d = RandomStringTool.randomBytes(bytes)
            let rows = [MetaRow("Hex", d.hexString, style: .mono), MetaRow("Base64", d.base64EncodedString(), style: .mono), MetaRow("Base64URL", d.base64URL, style: .mono),
                        MetaRow("JWK (oct)", JSONSerializer.string(.object([(key: "kty", value: .string("oct")), (key: "k", value: .string(d.base64URL))]), options: .minified), style: .mono),
                        MetaRow("Bits", "\(bytes * 8)")]
            return ToolOutput(text: d.hexString, facets: [OutputFacet("Base64", text: d.base64EncodedString()), OutputFacet("Base64URL", text: d.base64URL)], metadata: rows)
        }
        let key: CryptoKeys.Key
        switch options.kind {
        case "p256": key = .p256Private(P256.Signing.PrivateKey())
        case "p384": key = .p384Private(P384.Signing.PrivateKey())
        case "p521": key = .p521Private(P521.Signing.PrivateKey())
        case "rsa2048": key = try CryptoKeys.generateRSA(bits: 2048)
        case "rsa3072": key = try CryptoKeys.generateRSA(bits: 3072)
        case "rsa4096": key = try CryptoKeys.generateRSA(bits: 4096)
        default: key = .ed25519Private(Curve25519.Signing.PrivateKey())
        }
        try Task.checkpoint()
        let pub = CryptoKeys.publicKey(of: key)
        let privatePEM = CryptoKeys.pem(key), publicPEM = CryptoKeys.pem(pub)
        let kid = options.kid.isEmpty ? nil : options.kid
        let privateJWK = JSONSerializer.string(CryptoKeys.jwk(key, kid: kid)), publicJWK = JSONSerializer.string(CryptoKeys.jwk(pub, kid: kid))
        let ssh = Self.openssh(pub, comment: options.comment) ?? ""
        let spkiData = PEM.parse(publicPEM).first?.data ?? Data()
        let fingerprint = Data(SHA256.hash(data: spkiData)).base64EncodedString()
        let rows = [MetaRow("Key", key.description), MetaRow("SPKI SHA-256", fingerprint, style: .mono), MetaRow("JWK thumbprint", Self.jwkThumbprint(pub), style: .mono),
                    MetaRow("Private PEM", privatePEM, style: .mono), MetaRow("Public PEM", publicPEM, style: .mono), MetaRow("OpenSSH public", ssh.isEmpty ? "—" : ssh, style: .mono)]
        let text: String = switch options.format {
        case "jwk": "// Private JWK (keep secret)\n\(privateJWK)\n\n// Public JWK\n\(publicJWK)"
        case "ssh": ssh + "\n\n" + privatePEM
        case "all": "\(privatePEM)\n\n\(publicPEM)\n\n\(ssh)\n\n\(privateJWK)\n\n\(publicJWK)"
        default: privatePEM + "\n\n" + publicPEM
        }
        let facets = [OutputFacet("Private PEM", text: privatePEM), OutputFacet("Public PEM", text: publicPEM), OutputFacet("Private JWK", text: privateJWK, language: .json), OutputFacet("Public JWK", text: publicJWK, language: .json), OutputFacet("OpenSSH public", text: ssh)]
        return ToolOutput(text: text, language: options.format == "jwk" ? .json : .plain, facets: facets, metadata: rows, warnings: ["Private keys are generated locally and never stored. Copy them somewhere safe; history is disabled for this tool."])
    }

    static func jwkThumbprint(_ pub: CryptoKeys.Key) -> String {
        guard case .object(let o) = CryptoKeys.jwk(pub) else { return "" }
        let required: [String] = switch pub.kind { case .rsa: ["e", "kty", "n"]; case .ec: ["crv", "kty", "x", "y"]; case .ed25519: ["crv", "kty", "x"] }
        let canonical = JSONSerializer.string(.object(required.compactMap { k in o.first { $0.key == k } }), options: .minified)
        return Data(SHA256.hash(data: Data(canonical.utf8))).base64URL
    }
}
