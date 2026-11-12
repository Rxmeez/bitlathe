import Foundation
import CryptoKit
import BitlatheCore

public struct JWTTool: DevTool {
    public static let id = "jwt.debug"
    public static let name = "JWT Debugger"
    public static let summary = "Decode, explain, verify and sign JSON Web Tokens (HS, RS, PS, ES and EdDSA)"
    public static let category = ToolCategory.inspect
    public static let symbol = "key.horizontal"
    public static let keywords = ["jwt", "json web token", "jws", "bearer", "oauth", "oidc", "claims", "verify", "sign", "hs256", "rs256", "es256"]
    public static let historyEnabledByDefault = false
    public static let samples = [ToolSample("HS256 token", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkFkYSBMb3ZlbGFjZSIsImFkbWluIjp0cnVlLCJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MTcwMDAwMzYwMH0.vZ3H8R0L6T09KuBBi0Ds8dl4NdVZqYMV2VMnX5Bmatg", options: ["secret": .string("bitlathe")]),
                                 ToolSample("Sign new token", #"{"sub":"42","name":"Ada","role":"admin"}"#, options: ["mode": .string("sign"), "secret": .string("secret")])]
    public static let optionFields: [OptionField] = [
        .mode([.init("decode", "Decode & verify"), .init("sign", "Encode & sign")], default: "decode"),
        .picker("algorithm", "Algorithm", [.init("HS256", "HS256"), .init("HS384", "HS384"), .init("HS512", "HS512"), .init("RS256", "RS256"), .init("RS384", "RS384"), .init("RS512", "RS512"),
                                           .init("PS256", "PS256"), .init("PS384", "PS384"), .init("PS512", "PS512"), .init("ES256", "ES256"), .init("ES384", "ES384"), .init("ES512", "ES512"), .init("EdDSA", "EdDSA")], default: "HS256", visibleWhen: ("mode", ["sign"])),
        .secret("secret", "Secret", placeholder: "HMAC secret (HS*)", help: "Used for HS256/384/512 verification and signing"),
        .toggle("secretBase64", "Secret is Base64", advanced: true),
        .multiline("key", "Key (PEM / JWK)", placeholder: "-----BEGIN PUBLIC KEY----- … or a JWK — public key to verify, private key to sign"),
        .stepper("expiresIn", "Expires in (s)", min: 0, max: 31_536_000, step: 60, default: 3600, visibleWhen: ("mode", ["sign"])),
        .toggle("setIat", "Add iat", default: true, visibleWhen: ("mode", ["sign"])),
        .text("kid", "kid", placeholder: "key id", visibleWhen: ("mode", ["sign"]), advanced: true),
    ]
    public struct Options: ToolOptions {
        public var mode = "decode"
        public var algorithm = "HS256"
        public var secret = ""
        public var secretBase64 = false
        public var key = ""
        public var expiresIn = 3600
        public var setIat = true
        public var kid = ""
        public init() {}
    }
    public init() {}

    public struct Decoded: Sendable {
        public var header: JSONValue
        public var payload: JSONValue
        public var signature: Data
        public var signingInput: Data
        public var parts: [String]
        public var algorithm: String { header["alg"]?.stringValue ?? "none" }
    }

    public static func decode(_ token: String) throws -> Decoded {
        var t = token.trimmed()
        if t.lowercased().hasPrefix("bearer ") { t = String(t.dropFirst(7)).trimmed() }
        if t.hasPrefix("Authorization:") { t = t.replacingOccurrences(of: "Authorization:", with: "").replacingOccurrences(of: "Bearer", with: "").trimmed() }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 || parts.count == 5 else {
            throw ToolError("A JWT has 3 parts separated by dots; found \(parts.count)", hint: parts.count == 5 ? "This looks like an encrypted JWE, which cannot be decoded without the key" : "Check that the whole token was pasted")
        }
        if parts.count == 5 { throw ToolError("This is a JWE (encrypted token) with 5 parts; only JWS tokens can be decoded", hint: "The header is: \(Data(base64URL: parts[0]).flatMap { String(data: $0, encoding: .utf8) } ?? "?")") }
        guard let h = Data(base64URL: parts[0]), let hs = String(data: h, encoding: .utf8) else { throw ToolError("Header is not valid Base64URL", range: 0..<parts[0].utf16.count) }
        guard let p = Data(base64URL: parts[1]), let ps = String(data: p, encoding: .utf8) else { throw ToolError("Payload is not valid Base64URL", range: (parts[0].count + 1)..<(parts[0].count + 1 + parts[1].utf16.count)) }
        let header: JSONValue
        do { header = try JSONParser.parse(hs) } catch { throw ToolError("Header is not valid JSON: \(hs.prefix(60))") }
        let payload: JSONValue
        do { payload = try JSONParser.parse(ps) } catch { throw ToolError("Payload is not valid JSON: \(ps.prefix(60))") }
        let sig = Data(base64URL: parts[2]) ?? Data()
        return Decoded(header: header, payload: payload, signature: sig, signingInput: Data((parts[0] + "." + parts[1]).utf8), parts: parts)
    }

    static let claimDocs: [String: String] = [
        "iss": "Issuer — who created the token", "sub": "Subject — whom the token is about", "aud": "Audience — intended recipient(s)", "exp": "Expiration time", "nbf": "Not valid before",
        "iat": "Issued at", "jti": "JWT ID — unique identifier (replay protection)", "scope": "OAuth scopes granted", "scp": "Scopes (Azure style)", "azp": "Authorized party (client id)",
        "nonce": "OIDC replay nonce", "at_hash": "Access token hash", "c_hash": "Code hash", "auth_time": "When the user authenticated", "acr": "Authentication context class", "amr": "Authentication methods",
        "email": "Email address", "email_verified": "Email verified", "name": "Full name", "given_name": "Given name", "family_name": "Family name", "preferred_username": "Preferred username", "picture": "Profile picture URL",
        "roles": "Roles", "role": "Role", "groups": "Groups", "permissions": "Permissions", "client_id": "OAuth client id", "sid": "Session id", "typ": "Token type", "cnf": "Confirmation (proof-of-possession)",
        "org_id": "Organisation id", "tenant": "Tenant", "tid": "Tenant id (Azure)", "oid": "Object id (Azure)", "upn": "User principal name", "ver": "Token version", "kid": "Key id used to sign", "alg": "Signing algorithm",
        "cty": "Content type", "x5t": "X.509 thumbprint (SHA-1)", "x5t#S256": "X.509 thumbprint (SHA-256)", "jku": "JWK Set URL", "x5u": "X.509 URL", "crit": "Critical header parameters", "enc": "Encryption algorithm (JWE)", "zip": "Compression",
    ]

    static func describeTime(_ v: JSONValue) -> String {
        guard let t = v.doubleValue else { return "" }
        let d = Date(timeIntervalSince1970: t)
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return "\(f.string(from: d)) (\(UnixTimeTool.relative(d)))"
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        if options.mode == "sign" { return try sign(text, options: options) }
        let d = try Self.decode(text)
        var rows: [MetaRow] = []
        var warnings: [String] = []
        let alg = d.algorithm
        rows.append(MetaRow("Algorithm", alg + (Self.algDescription(alg).map { " — \($0)" } ?? ""), style: alg == "none" ? .danger : .plain))
        if alg == "none" { warnings.append("alg=none: this token is unsigned and must not be trusted") }
        if let typ = d.header["typ"]?.stringValue { rows.append(MetaRow("Type", typ)) }
        if let kid = d.header["kid"]?.stringValue { rows.append(MetaRow("Key ID", kid, style: .mono)) }
        var validity: Bool? = nil
        let now = Date().timeIntervalSince1970
        if case .object(let claims) = d.payload {
            for (k, v) in claims {
                let doc = Self.claimDocs[k]
                var value: String
                switch k {
                case "exp", "nbf", "iat", "auth_time", "updated_at":
                    value = "\(XMLJSON.scalar(v)) → \(Self.describeTime(v))"
                    if k == "exp", let t = v.doubleValue {
                        if t < now { value += "  ⚠️ EXPIRED"; warnings.append("Token expired \(UnixTimeTool.relative(Date(timeIntervalSince1970: t)))") }
                        else { value += "  ⏳ expires in \(UnitConverterTool.human(seconds: t - now))" }
                    }
                    if k == "nbf", let t = v.doubleValue, t > now + 60 { warnings.append("Token is not valid yet (nbf is in the future)") }
                    if k == "iat", let t = v.doubleValue, t > now + 300 { warnings.append("iat is in the future — check clock skew") }
                default:
                    value = v.stringValue ?? JSONSerializer.string(v, options: .minified)
                }
                rows.append(MetaRow(k + (doc.map { " · \($0)" } ?? ""), value, style: .mono))
            }
            if claims.first(where: { $0.key == "exp" }) == nil { warnings.append("No exp claim: the token never expires") }
        }
        rows.append(MetaRow("Signature", d.signature.isEmpty ? "— (none)" : "\(d.signature.count) bytes · " + d.signature.hexString.prefix(32) + "…", style: .mono))

        // Verification
        var verified: Bool?
        if alg.hasPrefix("HS") {
            if !options.secret.isEmpty {
                let secret = options.secretBase64 ? (Data(base64URL: options.secret) ?? Data(options.secret.utf8)) : Data(options.secret.utf8)
                let expected = CryptoKeys.hmac(d.signingInput, algorithm: alg, secret: secret)
                verified = expected == d.signature
            }
        } else if alg != "none", !options.key.trimmed().isEmpty {
            let key = try CryptoKeys.load(options.key)
            verified = try CryptoKeys.verify(d.signature, message: d.signingInput, algorithm: alg, key: key)
        }
        if let v = verified {
            rows.insert(MetaRow("Signature check", v ? "Valid — signed with the provided \(alg.hasPrefix("HS") ? "secret" : "key")" : "INVALID — does not match", style: v ? .success : .danger), at: 1)
            if !v { warnings.insert("Signature verification failed", at: 0) }
            validity = v
        } else if alg != "none" {
            rows.insert(MetaRow("Signature check", alg.hasPrefix("HS") ? "Enter the secret to verify" : "Paste the public key (PEM or JWK) to verify", style: .muted), at: 1)
        }
        let headerText = JSONSerializer.string(d.header)
        let payloadText = JSONSerializer.string(d.payload)
        let combined = "// Header\n\(headerText)\n\n// Payload\n\(payloadText)\n\n// Signature (hex)\n\(d.signature.hexString)"
        let headerLen = d.parts[0].utf16.count
        let annotations = [
            Annotation(.input, range: 0..<headerLen, style: .info, tooltip: "Header"),
            Annotation(.input, range: (headerLen + 1)..<(headerLen + 1 + d.parts[1].utf16.count), style: .group, tooltip: "Payload"),
            Annotation(.input, range: (headerLen + 2 + d.parts[1].utf16.count)..<(headerLen + 2 + d.parts[1].utf16.count + d.parts[2].utf16.count), style: .match, tooltip: "Signature"),
        ]
        return ToolOutput(text: combined, language: .json, facets: [OutputFacet("Header", text: headerText, language: .json), OutputFacet("Payload", text: payloadText, language: .json)],
                          metadata: rows, annotations: annotations, warnings: warnings, isValid: validity)
    }

    func sign(_ text: String, options: Options) throws -> ToolOutput {
        var payload = try JSONParser.parse(text, options: .json5)
        guard case .object(var claims) = payload else { throw ToolError("Payload must be a JSON object of claims") }
        let now = Int(Date().timeIntervalSince1970)
        if options.setIat, !claims.contains(where: { $0.key == "iat" }) { claims.append((key: "iat", value: .number(now))) }
        if options.expiresIn > 0, !claims.contains(where: { $0.key == "exp" }) { claims.append((key: "exp", value: .number(now + options.expiresIn))) }
        payload = .object(claims)
        var header: [(key: String, value: JSONValue)] = [(key: "alg", value: .string(options.algorithm)), (key: "typ", value: .string("JWT"))]
        if !options.kid.isEmpty { header.append((key: "kid", value: .string(options.kid))) }
        let h = Data(JSONSerializer.string(.object(header), options: .minified).utf8).base64URL
        let p = Data(JSONSerializer.string(payload, options: .minified).utf8).base64URL
        let signingInput = Data((h + "." + p).utf8)
        let sig: Data
        if options.algorithm.hasPrefix("HS") {
            guard !options.secret.isEmpty else { throw ToolError("Enter a secret to sign with \(options.algorithm)") }
            let secret = options.secretBase64 ? (Data(base64URL: options.secret) ?? Data(options.secret.utf8)) : Data(options.secret.utf8)
            if secret.count < 32, !options.secretBase64 { /* allowed, but warn below */ }
            sig = CryptoKeys.hmac(signingInput, algorithm: options.algorithm, secret: secret)
        } else {
            guard !options.key.trimmed().isEmpty else { throw ToolError("Paste a private key (PEM or JWK) to sign with \(options.algorithm)", hint: "Generate one with the Key Generator tool") }
            let key = try CryptoKeys.load(options.key)
            guard key.isPrivate else { throw ToolError("Signing needs a private key; the pasted key is public") }
            sig = try CryptoKeys.sign(signingInput, algorithm: options.algorithm, key: key)
        }
        let token = h + "." + p + "." + sig.base64URL
        var warnings: [String] = []
        if options.algorithm.hasPrefix("HS"), options.secret.utf8.count < 32 { warnings.append("HMAC secret is shorter than 32 bytes; use a longer random secret in production") }
        let rows = [MetaRow("Algorithm", options.algorithm), MetaRow("Length", "\(token.count) chars"), MetaRow("Expires", options.expiresIn > 0 ? Self.describeTime(.number(now + options.expiresIn)) : "never")]
        return ToolOutput(text: token, facets: [OutputFacet("Authorization header", text: "Authorization: Bearer \(token)"), OutputFacet("Payload", text: JSONSerializer.string(payload), language: .json)], metadata: rows, warnings: warnings)
    }

    static func algDescription(_ alg: String) -> String? {
        switch alg {
        case "HS256", "HS384", "HS512": "HMAC with SHA-\(alg.dropFirst(2)) (shared secret)"
        case "RS256", "RS384", "RS512": "RSA PKCS#1 v1.5 with SHA-\(alg.dropFirst(2))"
        case "PS256", "PS384", "PS512": "RSA-PSS with SHA-\(alg.dropFirst(2))"
        case "ES256": "ECDSA P-256 with SHA-256"
        case "ES384": "ECDSA P-384 with SHA-384"
        case "ES512": "ECDSA P-521 with SHA-512"
        case "ES256K": "ECDSA secp256k1 with SHA-256 (not verifiable here)"
        case "EdDSA": "Edwards-curve signature (Ed25519)"
        case "none": "UNSIGNED"
        default: nil
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        var t = s
        if t.lowercased().hasPrefix("bearer ") { t = String(t.dropFirst(7)) }
        guard Detect.isSingleLine(t), t.hasPrefix("ey") else { return nil }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ $0.isEmpty || Detect.isBase64URL(String($0), minLength: 1) }) else { return nil }
        return (try? decode(t)) != nil ? DetectionScore(0.98, "JSON Web Token") : DetectionScore(0.5, "Looks like a JWT")
    }
}
