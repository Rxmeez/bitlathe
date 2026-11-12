import Foundation
import CryptoKit
import Security
import BitlatheCore

/// Key loading (PEM / DER / JWK) and JWS-style signing for RSA, EC and Ed25519.
public enum CryptoKeys {
    public enum KeyKind: String, Sendable { case rsa = "RSA", ec = "EC", ed25519 = "Ed25519" }

    public enum Key: @unchecked Sendable {
        case rsaPrivate(SecKey, bits: Int)
        case rsaPublic(SecKey, bits: Int)
        case p256Private(P256.Signing.PrivateKey), p256Public(P256.Signing.PublicKey)
        case p384Private(P384.Signing.PrivateKey), p384Public(P384.Signing.PublicKey)
        case p521Private(P521.Signing.PrivateKey), p521Public(P521.Signing.PublicKey)
        case ed25519Private(Curve25519.Signing.PrivateKey), ed25519Public(Curve25519.Signing.PublicKey)

        public var isPrivate: Bool {
            switch self {
            case .rsaPrivate, .p256Private, .p384Private, .p521Private, .ed25519Private: true
            default: false
            }
        }
        public var kind: KeyKind {
            switch self {
            case .rsaPrivate, .rsaPublic: .rsa
            case .ed25519Private, .ed25519Public: .ed25519
            default: .ec
            }
        }
        public var curve: String? {
            switch self {
            case .p256Private, .p256Public: "P-256"
            case .p384Private, .p384Public: "P-384"
            case .p521Private, .p521Public: "P-521"
            case .ed25519Private, .ed25519Public: "Ed25519"
            default: nil
            }
        }
        public var description: String {
            switch self {
            case .rsaPrivate(_, let b): "RSA \(b)-bit private key"
            case .rsaPublic(_, let b): "RSA \(b)-bit public key"
            default: "\(curve ?? "") \(isPrivate ? "private" : "public") key"
            }
        }
    }

    // MARK: Loading

    public static func load(_ text: String) throws -> Key {
        let t = text.trimmed()
        if t.hasPrefix("{") { return try fromJWK(t) }
        let blocks = PEM.parse(t)
        if let b = blocks.first { return try fromDER(b.data, label: b.label) }
        if let d = Data(base64Encoded: t, options: .ignoreUnknownCharacters), !d.isEmpty { return try fromDER(d, label: "") }
        if t.hasPrefix("ssh-") || t.hasPrefix("ecdsa-sha2") { return try fromOpenSSH(t) }
        throw ToolError("Unrecognised key format", hint: "Paste a PEM block (-----BEGIN …-----), a JWK, or an OpenSSH public key")
    }

    static func fromDER(_ der: Data, label: String) throws -> Key {
        let node = try ASN1.parse(der)
        switch label {
        case "RSA PRIVATE KEY": return try rsa(pkcs1: der, isPrivate: true)
        case "RSA PUBLIC KEY": return try rsa(pkcs1: der, isPrivate: false)
        case "EC PRIVATE KEY": return try ecSEC1(node, der: der)
        case "ENCRYPTED PRIVATE KEY": throw ToolError("Encrypted private keys are not supported", hint: "Decrypt it first: openssl pkcs8 -in key.pem -out plain.pem")
        default: break
        }
        // Detect by structure
        if case .sequence(let items) = node {
            // SPKI: SEQ { SEQ { OID, params }, BITSTRING }
            if items.count == 2, case .sequence(let alg) = items[0], let oid = alg.first?.oid, case .bitString(_, let bits) = items[1] {
                switch oid {
                case "1.2.840.113549.1.1.1": return try rsa(pkcs1: bits, isPrivate: false)
                case "1.2.840.10045.2.1":
                    let curve = alg.count > 1 ? alg[1].oid ?? "" : ""
                    switch curve {
                    case "1.3.132.0.34": return .p384Public(try P384.Signing.PublicKey(x963Representation: bits))
                    case "1.3.132.0.35": return .p521Public(try P521.Signing.PublicKey(x963Representation: bits))
                    default: return .p256Public(try P256.Signing.PublicKey(x963Representation: bits))
                    }
                case "1.3.101.112": return .ed25519Public(try Curve25519.Signing.PublicKey(rawRepresentation: bits))
                default: throw ToolError("Unsupported public key algorithm \(OID.name(oid))")
                }
            }
            // PKCS#8: SEQ { INTEGER 0, SEQ { OID, params }, OCTETSTRING }
            if items.count >= 3, case .integer = items[0], case .sequence(let alg) = items[1], let oid = alg.first?.oid, case .octetString(let inner) = items[2] {
                switch oid {
                case "1.2.840.113549.1.1.1": return try rsa(pkcs1: inner, isPrivate: true)
                case "1.2.840.10045.2.1": return try ecSEC1(try ASN1.parse(inner), der: inner, curveOID: alg.count > 1 ? alg[1].oid : nil)
                case "1.3.101.112":
                    guard case .octetString(let raw) = try ASN1.parse(inner) else { throw ToolError("Invalid Ed25519 key") }
                    return .ed25519Private(try Curve25519.Signing.PrivateKey(rawRepresentation: raw))
                default: throw ToolError("Unsupported private key algorithm \(OID.name(oid))")
                }
            }
            // PKCS#1 RSA private: 9 integers; public: 2 integers
            if items.count >= 9, items.allSatisfy({ if case .integer = $0 { return true } else { return false } }) { return try rsa(pkcs1: der, isPrivate: true) }
            if items.count == 2, items.allSatisfy({ if case .integer = $0 { return true } else { return false } }) { return try rsa(pkcs1: der, isPrivate: false) }
            // SEC1 EC private: INTEGER 1, OCTETSTRING, [0] curve, [1] pubkey
            if items.count >= 2, case .integer(let v) = items[0], v == Data([1]), case .octetString = items[1] { return try ecSEC1(node, der: der) }
        }
        throw ToolError("Could not understand this key's DER structure")
    }

    static func rsa(pkcs1: Data, isPrivate: Bool) throws -> Key {
        guard case .sequence(let items) = try ASN1.parse(pkcs1), let modulus = items[isPrivate ? 1 : 0].data else { throw ToolError("Invalid RSA key") }
        let bits = (modulus.count - (modulus.first == 0 ? 1 : 0)) * 8
        let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: isPrivate ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic, kSecAttrKeySizeInBits: bits]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error) else {
            throw ToolError("Could not load RSA key: \((error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "unknown error")")
        }
        return isPrivate ? .rsaPrivate(key, bits: bits) : .rsaPublic(key, bits: bits)
    }

    static func ecSEC1(_ node: ASN1, der: Data, curveOID: String? = nil) throws -> Key {
        guard case .sequence(let items) = node, items.count >= 2, case .octetString(let raw) = items[1] else { throw ToolError("Invalid EC private key") }
        var curve = curveOID
        for item in items { if case .contextSpecific(0, _, let c, _) = item, let o = c.first?.oid { curve = o } }
        switch curve {
        case "1.3.132.0.34": return .p384Private(try P384.Signing.PrivateKey(rawRepresentation: raw))
        case "1.3.132.0.35": return .p521Private(try P521.Signing.PrivateKey(rawRepresentation: raw))
        default:
            if raw.count == 48 { return .p384Private(try P384.Signing.PrivateKey(rawRepresentation: raw)) }
            if raw.count == 66 { return .p521Private(try P521.Signing.PrivateKey(rawRepresentation: raw)) }
            return .p256Private(try P256.Signing.PrivateKey(rawRepresentation: raw))
        }
    }

    static func fromJWK(_ json: String) throws -> Key {
        let v = try JSONParser.parse(json)
        let kty = v["kty"]?.stringValue ?? ""
        func b64(_ k: String) -> Data? { v[k]?.stringValue.flatMap { Data(base64URL: $0) } }
        switch kty {
        case "RSA":
            guard let n = b64("n"), let e = b64("e") else { throw ToolError("RSA JWK needs n and e") }
            if let d = b64("d"), let p = b64("p"), let q = b64("q"), let dp = b64("dp"), let dq = b64("dq"), let qi = b64("qi") {
                let der = ASN1.sequence([.integer(Data([0])), .integer(n), .integer(e), .integer(d), .integer(p), .integer(q), .integer(dp), .integer(dq), .integer(qi)]).encoded
                return try rsa(pkcs1: der, isPrivate: true)
            }
            return try rsa(pkcs1: ASN1.sequence([.integer(n), .integer(e)]).encoded, isPrivate: false)
        case "EC":
            guard let x = b64("x"), let y = b64("y") else { throw ToolError("EC JWK needs x and y") }
            let pub = Data([4]) + x + y
            let d = b64("d")
            switch v["crv"]?.stringValue {
            case "P-384":
                if let d { return .p384Private(try P384.Signing.PrivateKey(rawRepresentation: d)) }
                return .p384Public(try P384.Signing.PublicKey(x963Representation: pub))
            case "P-521":
                if let d { return .p521Private(try P521.Signing.PrivateKey(rawRepresentation: d)) }
                return .p521Public(try P521.Signing.PublicKey(x963Representation: pub))
            default:
                if let d { return .p256Private(try P256.Signing.PrivateKey(rawRepresentation: d)) }
                return .p256Public(try P256.Signing.PublicKey(x963Representation: pub))
            }
        case "OKP":
            if let d = b64("d") { return .ed25519Private(try Curve25519.Signing.PrivateKey(rawRepresentation: d)) }
            guard let x = b64("x") else { throw ToolError("OKP JWK needs x") }
            return .ed25519Public(try Curve25519.Signing.PublicKey(rawRepresentation: x))
        default:
            throw ToolError("Unsupported JWK key type \"\(kty)\"")
        }
    }

    static func fromOpenSSH(_ line: String) throws -> Key {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { throw ToolError("Invalid OpenSSH public key") }
        var r = ByteReader(blob)
        func field() throws -> Data { let n = Int(try r.uint(4)); return Data(try r.take(n)) }
        let type = String(decoding: try field(), as: UTF8.self)
        switch type {
        case "ssh-rsa":
            let e = try field(), n = try field()
            return try rsa(pkcs1: ASN1.sequence([.integer(n), .integer(e)]).encoded, isPrivate: false)
        case "ssh-ed25519":
            return .ed25519Public(try Curve25519.Signing.PublicKey(rawRepresentation: try field()))
        case "ecdsa-sha2-nistp256": _ = try field(); return .p256Public(try P256.Signing.PublicKey(x963Representation: try field()))
        case "ecdsa-sha2-nistp384": _ = try field(); return .p384Public(try P384.Signing.PublicKey(x963Representation: try field()))
        case "ecdsa-sha2-nistp521": _ = try field(); return .p521Public(try P521.Signing.PublicKey(x963Representation: try field()))
        default: throw ToolError("Unsupported OpenSSH key type \(type)")
        }
    }

    // MARK: Export

    public static func pem(_ key: Key) -> String {
        switch key {
        case .rsaPrivate(let k, _):
            let pkcs1 = SecKeyCopyExternalRepresentation(k, nil).map { $0 as Data } ?? Data()
            let pkcs8 = ASN1.sequence([.integer(Data([0])), .sequence([.objectIdentifier("1.2.840.113549.1.1.1"), .null]), .octetString(pkcs1)]).encoded
            return PEM.encode(pkcs8, label: "PRIVATE KEY")
        case .rsaPublic(let k, _):
            let pkcs1 = SecKeyCopyExternalRepresentation(k, nil).map { $0 as Data } ?? Data()
            let spki = ASN1.sequence([.sequence([.objectIdentifier("1.2.840.113549.1.1.1"), .null]), .bitString(unused: 0, pkcs1)]).encoded
            return PEM.encode(spki, label: "PUBLIC KEY")
        case .p256Private(let k): return k.pemRepresentation
        case .p256Public(let k): return k.pemRepresentation
        case .p384Private(let k): return k.pemRepresentation
        case .p384Public(let k): return k.pemRepresentation
        case .p521Private(let k): return k.pemRepresentation
        case .p521Public(let k): return k.pemRepresentation
        case .ed25519Private(let k):
            let der = ASN1.sequence([.integer(Data([0])), .sequence([.objectIdentifier("1.3.101.112")]), .octetString(ASN1.octetString(k.rawRepresentation).encoded)]).encoded
            return PEM.encode(der, label: "PRIVATE KEY")
        case .ed25519Public(let k):
            let der = ASN1.sequence([.sequence([.objectIdentifier("1.3.101.112")]), .bitString(unused: 0, k.rawRepresentation)]).encoded
            return PEM.encode(der, label: "PUBLIC KEY")
        }
    }

    public static func jwk(_ key: Key, kid: String? = nil) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = []
        func put(_ k: String, _ d: Data) { pairs.append((key: k, value: .string(d.base64URL))) }
        switch key {
        case .rsaPrivate(let k, _), .rsaPublic(let k, _):
            let pkcs1 = SecKeyCopyExternalRepresentation(k, nil).map { $0 as Data } ?? Data()
            if case .sequence(let items) = (try? ASN1.parse(pkcs1)) ?? .null {
                pairs.append((key: "kty", value: .string("RSA")))
                let ints: [Data] = items.compactMap(\.data).map { d in d.first == 0 && d.count > 1 ? Data(d.dropFirst()) : d }
                if key.isPrivate, ints.count >= 9 {
                    for (name, i) in zip(["n", "e", "d", "p", "q", "dp", "dq", "qi"], ints.dropFirst()) { put(name, i) }
                } else if ints.count >= 2 { put("n", ints[0]); put("e", ints[1]) }
            }
        case .p256Private(let k): pairs.append((key: "kty", value: .string("EC"))); pairs.append((key: "crv", value: .string("P-256"))); ecCoords(k.publicKey.x963Representation, 32, &pairs); put("d", k.rawRepresentation)
        case .p256Public(let k): pairs.append((key: "kty", value: .string("EC"))); pairs.append((key: "crv", value: .string("P-256"))); ecCoords(k.x963Representation, 32, &pairs)
        case .p384Private(let k): pairs.append((key: "kty", value: .string("EC"))); pairs.append((key: "crv", value: .string("P-384"))); ecCoords(k.publicKey.x963Representation, 48, &pairs); put("d", k.rawRepresentation)
        case .p384Public(let k): pairs.append((key: "kty", value: .string("EC"))); pairs.append((key: "crv", value: .string("P-384"))); ecCoords(k.x963Representation, 48, &pairs)
        case .p521Private(let k): pairs.append((key: "kty", value: .string("EC"))); pairs.append((key: "crv", value: .string("P-521"))); ecCoords(k.publicKey.x963Representation, 66, &pairs); put("d", k.rawRepresentation)
        case .p521Public(let k): pairs.append((key: "kty", value: .string("EC"))); pairs.append((key: "crv", value: .string("P-521"))); ecCoords(k.x963Representation, 66, &pairs)
        case .ed25519Private(let k): pairs.append((key: "kty", value: .string("OKP"))); pairs.append((key: "crv", value: .string("Ed25519"))); put("x", k.publicKey.rawRepresentation); put("d", k.rawRepresentation)
        case .ed25519Public(let k): pairs.append((key: "kty", value: .string("OKP"))); pairs.append((key: "crv", value: .string("Ed25519"))); put("x", k.rawRepresentation)
        }
        if let kid { pairs.append((key: "kid", value: .string(kid))) }
        return .object(pairs)
    }

    static func ecCoords(_ x963: Data, _ size: Int, _ pairs: inout [(key: String, value: JSONValue)]) {
        let body = x963.dropFirst()
        pairs.append((key: "x", value: .string(Data(body.prefix(size)).base64URL)))
        pairs.append((key: "y", value: .string(Data(body.suffix(size)).base64URL)))
    }

    public static func publicKey(of key: Key) -> Key {
        switch key {
        case .rsaPrivate(let k, let bits): return SecKeyCopyPublicKey(k).map { .rsaPublic($0, bits: bits) } ?? key
        case .p256Private(let k): return .p256Public(k.publicKey)
        case .p384Private(let k): return .p384Public(k.publicKey)
        case .p521Private(let k): return .p521Public(k.publicKey)
        case .ed25519Private(let k): return .ed25519Public(k.publicKey)
        default: return key
        }
    }

    // MARK: Generation

    public static func generateRSA(bits: Int) throws -> Key {
        let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: bits, kSecAttrIsPermanent: false]
        var error: Unmanaged<CFError>?
        guard let k = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else { throw ToolError("RSA generation failed: \((error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "")") }
        return .rsaPrivate(k, bits: bits)
    }

    // MARK: JWS

    public static func sign(_ message: Data, algorithm: String, key: Key) throws -> Data {
        switch (algorithm, key) {
        case ("RS256", .rsaPrivate(let k, _)): return try secSign(k, message, .rsaSignatureMessagePKCS1v15SHA256)
        case ("RS384", .rsaPrivate(let k, _)): return try secSign(k, message, .rsaSignatureMessagePKCS1v15SHA384)
        case ("RS512", .rsaPrivate(let k, _)): return try secSign(k, message, .rsaSignatureMessagePKCS1v15SHA512)
        case ("PS256", .rsaPrivate(let k, _)): return try secSign(k, message, .rsaSignatureMessagePSSSHA256)
        case ("PS384", .rsaPrivate(let k, _)): return try secSign(k, message, .rsaSignatureMessagePSSSHA384)
        case ("PS512", .rsaPrivate(let k, _)): return try secSign(k, message, .rsaSignatureMessagePSSSHA512)
        case ("ES256", .p256Private(let k)): return try k.signature(for: message).rawRepresentation
        case ("ES384", .p384Private(let k)): return try k.signature(for: message).rawRepresentation
        case ("ES512", .p521Private(let k)): return try k.signature(for: message).rawRepresentation
        case ("EdDSA", .ed25519Private(let k)), ("Ed25519", .ed25519Private(let k)): return try k.signature(for: message)
        default: throw ToolError("\(algorithm) needs a \(expectedKey(algorithm)) private key, got \(key.description)")
        }
    }

    public static func verify(_ signature: Data, message: Data, algorithm: String, key: Key) throws -> Bool {
        let pub = publicKey(of: key)
        switch (algorithm, pub) {
        case ("RS256", .rsaPublic(let k, _)): return secVerify(k, message, signature, .rsaSignatureMessagePKCS1v15SHA256)
        case ("RS384", .rsaPublic(let k, _)): return secVerify(k, message, signature, .rsaSignatureMessagePKCS1v15SHA384)
        case ("RS512", .rsaPublic(let k, _)): return secVerify(k, message, signature, .rsaSignatureMessagePKCS1v15SHA512)
        case ("PS256", .rsaPublic(let k, _)): return secVerify(k, message, signature, .rsaSignatureMessagePSSSHA256)
        case ("PS384", .rsaPublic(let k, _)): return secVerify(k, message, signature, .rsaSignatureMessagePSSSHA384)
        case ("PS512", .rsaPublic(let k, _)): return secVerify(k, message, signature, .rsaSignatureMessagePSSSHA512)
        case ("ES256", .p256Public(let k)): return (try? P256.Signing.ECDSASignature(rawRepresentation: signature)).map { k.isValidSignature($0, for: message) } ?? false
        case ("ES384", .p384Public(let k)): return (try? P384.Signing.ECDSASignature(rawRepresentation: signature)).map { k.isValidSignature($0, for: message) } ?? false
        case ("ES512", .p521Public(let k)): return (try? P521.Signing.ECDSASignature(rawRepresentation: signature)).map { k.isValidSignature($0, for: message) } ?? false
        case ("EdDSA", .ed25519Public(let k)), ("Ed25519", .ed25519Public(let k)): return k.isValidSignature(signature, for: message)
        default: throw ToolError("\(algorithm) needs a \(expectedKey(algorithm)) key, got \(key.description)")
        }
    }

    static func expectedKey(_ alg: String) -> String {
        if alg.hasPrefix("RS") || alg.hasPrefix("PS") { return "RSA" }
        if alg == "ES256" { return "P-256" }
        if alg == "ES384" { return "P-384" }
        if alg == "ES512" { return "P-521" }
        return "Ed25519"
    }

    static func secSign(_ k: SecKey, _ m: Data, _ alg: SecKeyAlgorithm) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(k, alg, m as CFData, &error) else {
            throw ToolError("Signing failed: \((error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "unknown")")
        }
        return sig as Data
    }

    static func secVerify(_ k: SecKey, _ m: Data, _ s: Data, _ alg: SecKeyAlgorithm) -> Bool {
        SecKeyVerifySignature(k, alg, m as CFData, s as CFData, nil)
    }

    public static func hmac(_ message: Data, algorithm: String, secret: Data) -> Data {
        switch algorithm {
        case "HS384": Data(HMAC<SHA384>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
        case "HS512": Data(HMAC<SHA512>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
        default: Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
        }
    }
}
