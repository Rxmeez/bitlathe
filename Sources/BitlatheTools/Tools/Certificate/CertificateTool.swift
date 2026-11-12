import Foundation
import CryptoKit
import Security
import BitlatheCore

public struct CertificateTool: DevTool {
    public static let id = "cert.x509"
    public static let name = "Certificate Decoder"
    public static let summary = "Decode X.509 certificates, chains, CSRs and keys (PEM or DER): subject, SANs, validity, fingerprints"
    public static let category = ToolCategory.inspect
    public static let symbol = "checkmark.seal"
    public static let keywords = ["certificate", "x509", "pem", "der", "csr", "tls", "ssl", "san", "fingerprint", "chain", "public key", "private key"]
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: true)
    public static let samples = [ToolSample("Self-signed cert", Self.sampleCert)]
    public struct Options: ToolOptions { public init() {} }
    public init() {}

    public static let sampleCert = """
    -----BEGIN CERTIFICATE-----
    MIIB6jCCAZCgAwIBAgIUXNW1JCIfBDMjwRP6Hti+V3CRrfYwCgYIKoZIzj0EAwIw
    LjEZMBcGA1UEAwwQYml0bGF0aGUuZXhhbXBsZTERMA8GA1UECgwIQml0bGF0aGUw
    HhcNMjYxMTEyMTcwODE3WhcNMjcxMjE0MTcwODE3WjAuMRkwFwYDVQQDDBBiaXRs
    YXRoZS5leGFtcGxlMREwDwYDVQQKDAhCaXRsYXRoZTBZMBMGByqGSM49AgEGCCqG
    SM49AwEHA0IABJG5Y1fN7/yWAmDM7eBcRDxT3ZvSWdMMaVVJnPgP5xlBi56uarSp
    i3DIEJGlgu8dvW4MfNrxjGWLUpM0sOKkxCmjgYswgYgwHQYDVR0OBBYEFGUYruM2
    PfUxC+Mhxpzu2YqUdxdmMB8GA1UdIwQYMBaAFGUYruM2PfUxC+Mhxpzu2YqUdxdm
    MA8GA1UdEwEB/wQFMAMBAf8wNQYDVR0RBC4wLIIQYml0bGF0aGUuZXhhbXBsZYIS
    Ki5iaXRsYXRoZS5leGFtcGxlhwR/AAABMAoGCCqGSM49BAMCA0gAMEUCIQDXDAB/
    1zNnm1wuyjN9Dle6cuztn00CjjS0O3P3dVQm/wIgGZSk5YiiRDskma1immPu7YYz
    g+fSaRYEwEpdrQ/n1Pw=
    -----END CERTIFICATE-----
    """

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        var blocks: [PEM.Block] = []
        switch input.payload {
        case .text(let t):
            guard !t.trimmed().isEmpty else { throw ToolError.emptyInput }
            blocks = PEM.parse(t)
            if blocks.isEmpty {
                if let d = Data(base64Encoded: t.filter { !$0.isWhitespace }), (try? ASN1.parse(d)) != nil { blocks = [PEM.Block(label: "CERTIFICATE", data: d, headers: [:])] }
                else if let d = Data(hex: t.trimmed()), (try? ASN1.parse(d)) != nil { blocks = [PEM.Block(label: "CERTIFICATE", data: d, headers: [:])] }
                else { throw ToolError("No PEM block found", hint: "Expected -----BEGIN CERTIFICATE-----, CERTIFICATE REQUEST, PUBLIC KEY or PRIVATE KEY") }
            }
        default:
            let data = input.data
            guard !data.isEmpty else { throw ToolError.emptyInput }
            if let s = String(data: data, encoding: .utf8), s.contains("-----BEGIN") { blocks = PEM.parse(s) }
            else if (try? ASN1.parse(data)) != nil { blocks = [PEM.Block(label: "CERTIFICATE", data: data, headers: [:])] }
            else { throw ToolError("File is neither PEM nor DER") }
        }
        var rows: [MetaRow] = []
        var warnings: [String] = []
        var text = ""
        var json: [JSONValue] = []
        for (i, b) in blocks.enumerated() {
            if blocks.count > 1 { rows.append(MetaRow("── Block \(i + 1)", b.label, style: .muted)) }
            do {
                switch b.label {
                case "CERTIFICATE", "TRUSTED CERTIFICATE", "X509 CERTIFICATE":
                    let c = try X509.parse(b.data)
                    rows += c.rows
                    warnings += c.warnings
                    text += c.summary + "\n\n"
                    json.append(c.json)
                case "CERTIFICATE REQUEST", "NEW CERTIFICATE REQUEST":
                    let r = try X509.parseCSR(b.data)
                    rows += r.rows
                    text += r.summary + "\n\n"
                    json.append(r.json)
                default:
                    if b.label.contains("KEY") || b.label.isEmpty {
                        let key = try CryptoKeys.load(PEM.encode(b.data, label: b.label))
                        rows.append(MetaRow("Key", key.description))
                        let jwk = CryptoKeys.jwk(CryptoKeys.publicKey(of: key))
                        rows.append(MetaRow("Public JWK", JSONSerializer.string(jwk, options: .minified), style: .mono))
                        let spkiPEM = CryptoKeys.pem(CryptoKeys.publicKey(of: key))
                        if let spki = PEM.parse(spkiPEM).first { rows.append(MetaRow("SPKI SHA-256", Data(SHA256.hash(data: spki.data)).base64EncodedString(), style: .mono)) }
                        text += key.description + "\n" + spkiPEM + "\n\n"
                        json.append(jwk)
                    } else {
                        rows.append(MetaRow("Unsupported block", b.label, style: .warning))
                    }
                }
            } catch let e as ToolError {
                rows.append(MetaRow("Error", e.message, style: .danger))
                warnings.append("Block \(i + 1): \(e.message)")
            }
        }
        if blocks.count > 1 {
            let certs = blocks.filter { $0.label.contains("CERTIFICATE") && !$0.label.contains("REQUEST") }.compactMap { try? X509.parse($0.data) }
            if certs.count > 1 {
                var chainOK = true
                for (a, b) in zip(certs, certs.dropFirst()) where a.issuerDN != b.subjectDN { chainOK = false; warnings.append("Chain break: \"\(a.subject)\" was not issued by \"\(b.subject)\"") }
                rows.insert(MetaRow("Chain", chainOK ? "\(certs.count) certificates, issuer links consistent" : "\(certs.count) certificates, inconsistent order/links", style: chainOK ? .success : .warning), at: 0)
            }
        }
        return ToolOutput(text: JSONSerializer.string(json.count == 1 ? json[0] : .array(json)), language: .json, facets: [OutputFacet("Summary", text: text.trimmed())], metadata: rows, warnings: warnings, isValid: warnings.isEmpty)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.contains("-----BEGIN CERTIFICATE") || s.contains("-----BEGIN CERTIFICATE REQUEST") || s.contains("-----BEGIN NEW CERTIFICATE REQUEST") { return DetectionScore(0.98, "PEM certificate") }
        if s.contains("-----BEGIN") && s.contains("KEY-----") { return DetectionScore(0.9, "PEM key") }
        if s.hasPrefix("MII"), Detect.isBase64(s), (try? X509.parse(Data(base64Encoded: s.filter { !$0.isWhitespace }) ?? Data())) != nil { return DetectionScore(0.85, "DER certificate (Base64)") }
        return nil
    }
}

public enum X509 {
    public struct Certificate: Sendable {
        public var subject: String
        public var subjectDN: String
        public var issuer: String
        public var issuerDN: String
        public var serial: String
        public var notBefore: Date
        public var notAfter: Date
        public var version: Int
        public var signatureAlgorithm: String
        public var publicKey: String
        public var sans: [String]
        public var isCA: Bool
        public var keyUsage: [String]
        public var extKeyUsage: [String]
        public var fingerprints: [(String, String)]
        public var extensions: [(String, String, Bool)]
        public var rows: [MetaRow]
        public var warnings: [String]
        public var summary: String
        public var json: JSONValue
    }

    static func dn(_ node: ASN1?) -> (String, [(String, String)]) {
        var parts: [(String, String)] = []
        for rdn in node?.children ?? [] {
            for atv in rdn.children {
                if let oid = atv[0]?.oid, let v = atv[1]?.string { parts.append((OID.name(oid), v)) }
            }
        }
        return (parts.map { "\($0.0)=\($0.1)" }.joined(separator: ", "), parts)
    }

    static func algorithm(_ node: ASN1?) -> String {
        guard let oid = node?[0]?.oid else { return "?" }
        var name = OID.name(oid)
        if oid == "1.2.840.113549.1.1.10", let params = node?[1] {
            if let hash = params.children.first(where: { if case .contextSpecific(0, _, _, _) = $0 { return true } else { return false } })?.children.first?[0]?.oid { name += " (\(OID.name(hash)))" }
        }
        return name
    }

    static func publicKeyInfo(_ spki: ASN1?) -> (String, String, Int) {
        guard let alg = spki?[0], let oid = alg[0]?.oid, case .bitString(_, let bits)? = spki?[1] else { return ("?", "", 0) }
        switch oid {
        case "1.2.840.113549.1.1.1":
            if case .sequence(let items)? = try? ASN1.parse(bits), let n = items.first?.data {
                let bitsCount = (n.count - (n.first == 0 ? 1 : 0)) * 8
                let e = items.count > 1 ? items[1].data.map { $0.reduce(0) { ($0 << 8) | Int($1) } } ?? 0 : 0
                return ("RSA \(bitsCount)-bit", "e=\(e)", bitsCount)
            }
            return ("RSA", "", 0)
        case "1.2.840.10045.2.1":
            let curve = alg[1]?.oid.map(OID.name) ?? "?"
            return ("EC \(curve)", bits.hexString.prefix(32) + "…", curve == "P-384" ? 384 : (curve == "P-521" ? 521 : 256))
        case "1.3.101.112": return ("Ed25519", bits.hexString, 256)
        case "1.3.101.113": return ("Ed448", bits.hexString, 448)
        default: return (OID.name(oid), "", 0)
        }
    }

    static func generalNames(_ node: ASN1) -> [String] {
        node.children.compactMap { gn -> String? in
            guard case .contextSpecific(let tag, _, let children, let raw) = gn else { return nil }
            switch tag {
            case 1: return "email:" + String(decoding: raw, as: UTF8.self)
            case 2: return "DNS:" + String(decoding: raw, as: UTF8.self)
            case 6: return "URI:" + String(decoding: raw, as: UTF8.self)
            case 7:
                if raw.count == 4 { return "IP:" + raw.map(String.init).joined(separator: ".") }
                if raw.count == 16 { return "IP:" + CIDRTool.v6Compressed(stride(from: 0, to: 16, by: 2).map { UInt16(raw[raw.startIndex + $0]) << 8 | UInt16(raw[raw.startIndex + $0 + 1]) }) }
                return "IP:" + raw.hexString
            case 4: return "DirName:" + dn(children.first).0
            case 0: return "OtherName:" + (children.first?.oid ?? raw.hexString)
            default: return "[\(tag)]:" + raw.hexString
            }
        }
    }

    static func parseExtensions(_ node: ASN1?) -> (sans: [String], isCA: Bool, pathLen: Int?, keyUsage: [String], eku: [String], list: [(String, String, Bool)], skid: String?, akid: String?) {
        var sans: [String] = [], isCA = false, pathLen: Int?, keyUsage: [String] = [], eku: [String] = [], list: [(String, String, Bool)] = []
        var skid: String?, akid: String?
        for ext in node?.children ?? [] {
            guard let oid = ext[0]?.oid else { continue }
            var critical = false
            var valueNode: ASN1? = ext[1]
            if case .boolean(let b)? = ext[1] { critical = b; valueNode = ext[2] }
            guard case .octetString(let raw)? = valueNode, let inner = try? ASN1.parse(raw) else { list.append((OID.name(oid), "?", critical)); continue }
            var desc = ""
            switch oid {
            case "2.5.29.17":
                sans = generalNames(inner)
                desc = sans.joined(separator: ", ")
            case "2.5.29.19":
                if case .boolean(let ca)? = inner[0] { isCA = ca }
                if let pl = inner.children.first(where: { if case .integer = $0 { return true } else { return false } })?.data { pathLen = pl.reduce(0) { ($0 << 8) | Int($1) } }
                desc = isCA ? "CA:TRUE" + (pathLen.map { ", pathlen:\($0)" } ?? "") : "CA:FALSE"
            case "2.5.29.15":
                if case .bitString(let unused, let bits) = inner, let first = bits.first {
                    let names = ["Digital Signature", "Non Repudiation", "Key Encipherment", "Data Encipherment", "Key Agreement", "Certificate Sign", "CRL Sign", "Encipher Only", "Decipher Only"]
                    var value = UInt16(first) << 8
                    if bits.count > 1 { value |= UInt16(bits[bits.startIndex + 1]) }
                    _ = unused
                    for (i, n) in names.enumerated() where value & (0x8000 >> i) != 0 { keyUsage.append(n) }
                }
                desc = keyUsage.joined(separator: ", ")
            case "2.5.29.37":
                eku = inner.children.compactMap { $0.oid.map(OID.name) }
                desc = eku.joined(separator: ", ")
            case "2.5.29.14":
                skid = inner.data?.hexString
                desc = skid.map { $0.chunked(2).joined(separator: ":").uppercased() } ?? ""
            case "2.5.29.35":
                for c in inner.children { if case .contextSpecific(0, _, _, let raw) = c { akid = raw.hexString } }
                desc = akid.map { "keyid:" + $0.chunked(2).joined(separator: ":").uppercased() } ?? ""
            case "2.5.29.31":
                desc = inner.children.flatMap { $0.children }.flatMap { $0.children }.flatMap { generalNames($0) }.joined(separator: ", ")
            case "1.3.6.1.5.5.7.1.1":
                desc = inner.children.compactMap { ad -> String? in
                    guard let m = ad[0]?.oid, let gn = ad[1] else { return nil }
                    return OID.name(m) + " → " + generalNames(.sequence([gn])).joined()
                }.joined(separator: "; ")
            case "2.5.29.32":
                desc = inner.children.compactMap { $0[0]?.oid.map(OID.name) }.joined(separator: ", ")
            case "1.3.6.1.4.1.11129.2.4.2":
                desc = "\(max(0, (inner.data?.count ?? 0) - 2)) bytes of SCTs"
            default:
                desc = raw.count > 40 ? "\(raw.count) bytes" : raw.hexString
            }
            list.append((OID.name(oid), desc, critical))
        }
        return (sans, isCA, pathLen, keyUsage, eku, list, skid, akid)
    }

    public static func parse(_ der: Data) throws -> Certificate {
        let root = try ASN1.parse(der)
        guard case .sequence(let top) = root, top.count >= 3, case .sequence(let tbs) = top[0] else { throw ToolError("Not an X.509 certificate (expected SEQUENCE { tbsCertificate, signatureAlgorithm, signature })") }
        var idx = 0
        var version = 1
        if case .contextSpecific(0, _, let c, _) = tbs[0], let v = c.first?.data { version = Int(v.first ?? 0) + 1; idx = 1 }
        guard tbs.count >= idx + 6 else { throw ToolError("Truncated certificate") }
        let serialData = tbs[idx].data ?? Data()
        let sigAlg = algorithm(tbs[idx + 1])
        let (issuer, issuerParts) = dn(tbs[idx + 2])
        let validity = tbs[idx + 3]
        let notBefore = validity[0]?.date ?? .distantPast
        let notAfter = validity[1]?.date ?? .distantPast
        let (subject, subjectParts) = dn(tbs[idx + 4])
        let spki = tbs[idx + 5]
        let (pkName, pkDetail, pkBits) = publicKeyInfo(spki)
        var extNode: ASN1?
        for item in tbs.dropFirst(idx + 6) { if case .contextSpecific(3, _, let c, _) = item { extNode = c.first } }
        let ext = parseExtensions(extNode)
        let now = Date()
        var warnings: [String] = []
        let days = Int(notAfter.timeIntervalSince(now) / 86400)
        if notAfter < now { warnings.append("Certificate expired \(UnixTimeTool.relative(notAfter))") }
        else if days < 30 { warnings.append("Certificate expires in \(days) days") }
        if notBefore > now { warnings.append("Certificate is not valid yet") }
        if sigAlg.contains("SHA-1") || sigAlg.contains("MD5") { warnings.append("Weak signature algorithm: \(sigAlg)") }
        if pkName.hasPrefix("RSA"), pkBits < 2048 { warnings.append("Weak RSA key: \(pkBits) bits") }
        if version == 3, ext.sans.isEmpty, !ext.isCA { warnings.append("No Subject Alternative Names — modern browsers ignore the CN") }
        if subject == issuer { warnings.append("Self-signed certificate") }
        if notAfter.timeIntervalSince(notBefore) > 398 * 86400, !ext.isCA { warnings.append("Validity longer than 398 days; public CAs no longer issue these") }
        let spkiData = spki.encoded
        let fingerprints = [("SHA-256", Data(SHA256.hash(data: der))), ("SHA-1", Data(Insecure.SHA1.hash(data: der))), ("MD5", Data(Insecure.MD5.hash(data: der)))]
            .map { ($0.0, $0.1.hexString.chunked(2).joined(separator: ":").uppercased()) }
        let cn = subjectParts.first { $0.0 == "CN" }?.1 ?? subject
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.timeZone = TimeZone(identifier: "UTC")
        var rows: [MetaRow] = [
            MetaRow("Subject", subject.isEmpty ? "(empty)" : subject),
            MetaRow("Issuer", issuer),
            MetaRow("Valid from", df.string(from: notBefore) + " UTC"),
            MetaRow("Valid until", df.string(from: notAfter) + " UTC" + (notAfter < now ? " — EXPIRED" : " (\(days) days left)"), style: notAfter < now ? .danger : (days < 30 ? .warning : .success)),
            MetaRow("Serial", serialData.hexString.chunked(2).joined(separator: ":").uppercased(), style: .mono),
            MetaRow("Version", "v\(version)"),
            MetaRow("Signature algorithm", sigAlg),
            MetaRow("Public key", pkName + (pkDetail.isEmpty ? "" : " · \(pkDetail)")),
            MetaRow("SPKI SHA-256 (HPKP pin)", Data(SHA256.hash(data: spkiData)).base64EncodedString(), style: .mono),
            MetaRow("CA", ext.isCA ? "Yes" + (ext.pathLen.map { " (path length \($0))" } ?? "") : "No"),
        ]
        if !ext.sans.isEmpty { rows.append(MetaRow("Subject Alt Names", ext.sans.joined(separator: "\n"), style: .mono)) }
        if !ext.keyUsage.isEmpty { rows.append(MetaRow("Key usage", ext.keyUsage.joined(separator: ", "))) }
        if !ext.eku.isEmpty { rows.append(MetaRow("Extended key usage", ext.eku.joined(separator: ", "))) }
        for f in fingerprints { rows.append(MetaRow("Fingerprint \(f.0)", f.1, style: .mono)) }
        for (name, desc, critical) in ext.list where !["Subject Alternative Name", "Key Usage", "Extended Key Usage", "Basic Constraints"].contains(name) {
            rows.append(MetaRow(name + (critical ? " (critical)" : ""), desc, style: .mono))
        }
        let summary = """
        \(cn)
        Issued by \(issuerParts.first { $0.0 == "CN" }?.1 ?? issuer)
        Valid \(df.string(from: notBefore)) → \(df.string(from: notAfter)) UTC
        \(pkName) · \(sigAlg)
        SANs: \(ext.sans.isEmpty ? "—" : ext.sans.joined(separator: ", "))
        SHA-256: \(fingerprints[0].1)
        """
        let json: JSONValue = .object([
            (key: "subject", value: .object(subjectParts.map { (key: $0.0, value: .string($0.1)) })),
            (key: "issuer", value: .object(issuerParts.map { (key: $0.0, value: .string($0.1)) })),
            (key: "serialNumber", value: .string(serialData.hexString)),
            (key: "version", value: .number(version)),
            (key: "notBefore", value: .string(ISO8601DateFormatter().string(from: notBefore))),
            (key: "notAfter", value: .string(ISO8601DateFormatter().string(from: notAfter))),
            (key: "signatureAlgorithm", value: .string(sigAlg)),
            (key: "publicKey", value: .object([(key: "type", value: .string(pkName)), (key: "bits", value: .number(pkBits))])),
            (key: "isCA", value: .bool(ext.isCA)),
            (key: "subjectAltNames", value: .array(ext.sans.map { .string($0) })),
            (key: "keyUsage", value: .array(ext.keyUsage.map { .string($0) })),
            (key: "extendedKeyUsage", value: .array(ext.eku.map { .string($0) })),
            (key: "fingerprints", value: .object(fingerprints.map { (key: $0.0, value: .string($0.1)) })),
            (key: "extensions", value: .array(ext.list.map { .object([(key: "name", value: .string($0.0)), (key: "value", value: .string($0.1)), (key: "critical", value: .bool($0.2))]) })),
        ])
        return Certificate(subject: cn, subjectDN: subject, issuer: issuerParts.first { $0.0 == "CN" }?.1 ?? issuer, issuerDN: issuer, serial: serialData.hexString, notBefore: notBefore, notAfter: notAfter,
                           version: version, signatureAlgorithm: sigAlg, publicKey: pkName, sans: ext.sans, isCA: ext.isCA, keyUsage: ext.keyUsage, extKeyUsage: ext.eku,
                           fingerprints: fingerprints, extensions: ext.list, rows: rows, warnings: warnings, summary: summary, json: json)
    }

    public struct CSR: Sendable {
        public var rows: [MetaRow]
        public var summary: String
        public var json: JSONValue
    }

    public static func parseCSR(_ der: Data) throws -> CSR {
        let root = try ASN1.parse(der)
        guard case .sequence(let top) = root, top.count >= 3, case .sequence(let info) = top[0], info.count >= 3 else { throw ToolError("Not a PKCS#10 certificate request") }
        let (subject, subjectParts) = dn(info[1])
        let (pkName, pkDetail, pkBits) = publicKeyInfo(info[2])
        var sans: [String] = []
        var extList: [(String, String, Bool)] = []
        var attrs: [(String, String)] = []
        if info.count > 3, case .contextSpecific(0, _, let attributes, _) = info[3] {
            for a in attributes {
                guard let oid = a[0]?.oid else { continue }
                if oid == "1.2.840.113549.1.9.14" {
                    let ext = parseExtensions(a[1]?.children.first)
                    sans = ext.sans
                    extList = ext.list
                } else {
                    attrs.append((OID.name(oid), a[1]?.children.first?.string ?? ""))
                }
            }
        }
        let sigAlg = algorithm(top[1])
        var rows = [MetaRow("Type", "Certificate Signing Request (PKCS#10)"), MetaRow("Subject", subject), MetaRow("Public key", pkName + (pkDetail.isEmpty ? "" : " · \(pkDetail)")), MetaRow("Signature algorithm", sigAlg)]
        if !sans.isEmpty { rows.append(MetaRow("Requested SANs", sans.joined(separator: "\n"), style: .mono)) }
        for (n, v) in attrs { rows.append(MetaRow(n, v)) }
        for (n, d, c) in extList where n != "Subject Alternative Name" { rows.append(MetaRow(n + (c ? " (critical)" : ""), d, style: .mono)) }
        rows.append(MetaRow("SHA-256", Data(SHA256.hash(data: der)).hexString.chunked(2).joined(separator: ":").uppercased(), style: .mono))
        let summary = "CSR for \(subject)\n\(pkName) · \(sigAlg)\nSANs: \(sans.isEmpty ? "—" : sans.joined(separator: ", "))"
        let json: JSONValue = .object([
            (key: "type", value: .string("CertificateRequest")),
            (key: "subject", value: .object(subjectParts.map { (key: $0.0, value: .string($0.1)) })),
            (key: "publicKey", value: .object([(key: "type", value: .string(pkName)), (key: "bits", value: .number(pkBits))])),
            (key: "signatureAlgorithm", value: .string(sigAlg)),
            (key: "subjectAltNames", value: .array(sans.map { .string($0) })),
        ])
        return CSR(rows: rows, summary: summary, json: json)
    }
}
