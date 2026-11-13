import Foundation
import BitlatheCore
import BitlatheTools

/// What the extension shows. Built off the main thread from the file's bytes; pure and testable.
struct PreviewModel: Sendable {
    struct Claim: Sendable, Identifiable {
        var id: String { name }
        var name: String
        var value: String
        var note: String?
        var tone: Tone = .plain
    }
    enum Tone: Sendable { case plain, good, bad, warn }
    struct JWTInfo: Sendable {
        var algorithm: String
        var header: String
        var payload: String
        var claims: [Claim]
        var status: (text: String, tone: Tone)?
        var unsigned: Bool
    }
    struct CertInfo: Sendable, Identifiable {
        var id = UUID()
        var title: String
        var subject: String
        var issuer: String
        var validity: String
        var status: (text: String, tone: Tone)
        var sans: [String]
        var key: String
        var signature: String
        var serial: String
        var badges: [String]
        var fingerprints: [(String, String)]
        var warnings: [String]
    }
    enum Content: Sendable {
        case jwt(JWTInfo)
        case certificates([CertInfo], notes: [String])
        case csr(title: String, rows: [MetaRow])
        case code(text: String, language: CodeLanguage, truncated: Bool, notice: String?)
        case message(String)
    }
    var title: String
    var subtitle: String
    var symbol: String
    var content: Content
}

enum PreviewBuilder {
    static let maxBytes = 8 * 1024 * 1024
    static let maxDisplayChars = 300_000

    static func build(url: URL) throws -> PreviewModel {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes) ?? Data()
        return build(data: data, name: url.lastPathComponent, ext: url.pathExtension.lowercased())
    }

    static func build(data: Data, name: String, ext: String) -> PreviewModel {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        switch ext {
        case "jwt": return jwt(text, name: name) ?? fallback(text, name: name, why: "This file does not contain a decodable JWT.")
        case "pem", "crt", "cer", "der", "csr", "p10", "req": return certificates(data: data, text: text, name: name)
        case "json", "jsonc", "json5": return json(text ?? "", name: name, ext: ext)
        case "yaml", "yml": return yaml(text ?? "", name: name)
        default:
            if let text, let m = jwt(text, name: name) { return m }
            if let text, text.contains("-----BEGIN") { return certificates(data: data, text: text, name: name) }
            return fallback(text, name: name, why: "Bitlathe has no preview for this file type.")
        }
    }

    static func fallback(_ text: String?, name: String, why: String) -> PreviewModel {
        PreviewModel(title: name, subtitle: "Unsupported", symbol: "questionmark.circle", content: .message(why))
    }

    // MARK: JWT

    static func jwt(_ text: String?, name: String) -> PreviewModel? {
        guard let text, let d = try? JWTTool.decode(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let now = Date().timeIntervalSince1970
        var claims: [PreviewModel.Claim] = []
        var status: (String, PreviewModel.Tone)?
        if case .object(let items) = d.payload {
            let order = ["iss", "sub", "aud", "exp", "nbf", "iat", "jti"]
            let sorted = items.sorted { (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99) }
            for (k, v) in sorted where order.contains(k) {
                var value = scalar(v)
                var note: String?
                var tone = PreviewModel.Tone.plain
                if ["exp", "nbf", "iat"].contains(k), let t = v.doubleValue {
                    let date = Date(timeIntervalSince1970: t)
                    value = date.formatted(date: .abbreviated, time: .standard)
                    note = UnixTimeTool.relative(date)
                    if k == "exp" {
                        if t < now { tone = .bad; status = ("Expired", .bad) } else { tone = .good; status = status ?? ("Valid", .good) }
                    }
                    if k == "nbf", t > now { tone = .warn; status = ("Not yet valid", .warn) }
                }
                claims.append(.init(name: k, value: value, note: note, tone: tone))
            }
        }
        if status == nil { status = ("No expiry", .warn) }
        let alg = d.algorithm
        let info = PreviewModel.JWTInfo(algorithm: alg, header: JSONSerializer.string(d.header), payload: JSONSerializer.string(d.payload),
                                        claims: claims, status: status, unsigned: alg.lowercased() == "none")
        return PreviewModel(title: name, subtitle: "JSON Web Token · \(alg)", symbol: "key.horizontal", content: .jwt(info))
    }

    static func scalar(_ v: JSONValue) -> String {
        switch v {
        case .string(let s): return s
        case .array(let a): return a.map(scalar).joined(separator: ", ")
        default: return JSONSerializer.string(v, options: .minified)
        }
    }

    // MARK: Certificates

    static func certificates(data: Data, text: String?, name: String) -> PreviewModel {
        var certs: [PreviewModel.CertInfo] = []
        var notes: [String] = []
        var csrs: [(String, [MetaRow])] = []
        if let text, text.contains("-----BEGIN") {
            for block in PEM.parse(text) {
                let label = block.label.uppercased()
                if label.contains("CERTIFICATE REQUEST") {
                    if let c = try? X509.parseCSR(block.data) { csrs.append((name, c.rows)) } else { notes.append("A certificate request could not be parsed.") }
                } else if label.contains("CERTIFICATE") {
                    if let c = try? X509.parse(block.data) { certs.append(cert(c)) } else { notes.append("A certificate block could not be parsed.") }
                } else {
                    notes.append("Skipped a \(block.label) block (private keys are never displayed).")
                }
            }
        } else if let c = try? X509.parse(data) {
            certs.append(cert(c))
        } else if let c = try? X509.parseCSR(data) {
            csrs.append((name, c.rows))
        }
        if let csr = csrs.first, certs.isEmpty {
            return PreviewModel(title: name, subtitle: "Certificate signing request", symbol: "doc.badge.gearshape", content: .csr(title: csr.0, rows: csr.1))
        }
        if certs.isEmpty {
            return PreviewModel(title: name, subtitle: "No certificate found", symbol: "exclamationmark.triangle", content: .message(notes.first ?? "No X.509 certificate or request could be read from this file."))
        }
        let sub = certs.count == 1 ? "X.509 certificate" : "Certificate chain · \(certs.count) certificates"
        return PreviewModel(title: name, subtitle: sub, symbol: "checkmark.seal", content: .certificates(certs, notes: notes))
    }

    static func cert(_ c: X509.Certificate) -> PreviewModel.CertInfo {
        let now = Date()
        let status: (String, PreviewModel.Tone) = c.notAfter < now ? ("Expired", .bad) : c.notBefore > now ? ("Not yet valid", .warn)
            : (c.notAfter.timeIntervalSince(now) < 30 * 86400 ? "Expires soon" : "Valid", c.notAfter.timeIntervalSince(now) < 30 * 86400 ? .warn : .good)
        var badges: [String] = []
        if c.isCA { badges.append("CA") }
        if c.subjectDN == c.issuerDN { badges.append("Self-signed") }
        let fmt = { (d: Date) in d.formatted(date: .abbreviated, time: .shortened) }
        return .init(title: c.subject.isEmpty ? c.subjectDN : c.subject, subject: c.subjectDN, issuer: c.issuerDN,
                     validity: "\(fmt(c.notBefore))  to  \(fmt(c.notAfter))", status: status, sans: c.sans, key: c.publicKey,
                     signature: c.signatureAlgorithm, serial: c.serial, badges: badges,
                     fingerprints: c.fingerprints.filter { $0.0 != "MD5" }, warnings: c.warnings.filter { !$0.hasPrefix("Certificate expired") && !$0.hasPrefix("Self-signed") })
    }

    // MARK: JSON / YAML

    static func json(_ text: String, name: String, ext: String) -> PreviewModel {
        var parsed: JSONValue?
        var notice: String?
        for opts in [JSONParser.Options.strict, .jsonc, .json5] {
            if let v = try? JSONParser.parse(text, options: opts) { parsed = v; break }
        }
        let body: String
        if let parsed { body = JSONSerializer.string(parsed) } else {
            body = text
            let err = (try? JSONParser.parse(text, options: .json5)).map { _ in "" } ?? "Not valid JSON, showing the original text."
            notice = err
        }
        return code(body, language: .json, name: name, subtitle: parsed == nil ? "JSON (invalid)" : "JSON · formatted", symbol: "curlybraces", notice: notice)
    }

    static func yaml(_ text: String, name: String) -> PreviewModel {
        do {
            return code(try QuickLookSupport.prettyYAML(text), language: .yaml, name: name, subtitle: "YAML · formatted", symbol: "list.bullet.indent", notice: nil)
        } catch {
            return code(text, language: .yaml, name: name, subtitle: "YAML (invalid)", symbol: "list.bullet.indent", notice: "Not valid YAML, showing the original text.")
        }
    }

    static func code(_ body: String, language: CodeLanguage, name: String, subtitle: String, symbol: String, notice: String?) -> PreviewModel {
        let truncated = body.count > maxDisplayChars
        let shown = truncated ? String(body.prefix(maxDisplayChars)) : body
        return PreviewModel(title: name, subtitle: subtitle, symbol: symbol, content: .code(text: shown, language: language, truncated: truncated, notice: notice))
    }
}
