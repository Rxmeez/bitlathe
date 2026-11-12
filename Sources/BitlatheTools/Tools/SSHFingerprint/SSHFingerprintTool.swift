import Foundation
import CryptoKit
import BitlatheCore

public struct SSHFingerprintTool: DevTool {
    public static let id = "ssh.fingerprint"
    public static let name = "SSH Key Fingerprint"
    public static let summary = "MD5 and SHA-256 fingerprints, key type, bits and randomart for OpenSSH public keys"
    public static let category = ToolCategory.inspect
    public static let symbol = "fingerprint"
    public static let keywords = ["ssh", "fingerprint", "public key", "authorized_keys", "known_hosts", "ed25519", "rsa", "randomart", "md5", "sha256"]
    public static let samples = [ToolSample("Ed25519 key", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGl3xdcCb8qD3YmQ4D1Lw5K2L3Z8s8HnqZ0dQ2u3V8d4 ada@bitlathe")]
    public struct Options: ToolOptions { public init() {} }
    public init() {}

    public struct KeyInfo: Sendable {
        public var type: String
        public var bits: Int
        public var comment: String
        public var sha256: String
        public var md5: String
        public var blob: Data
    }

    public static func parse(_ line: String) throws -> KeyInfo {
        var l = line.trimmed()
        // known_hosts: "host ssh-ed25519 AAAA…" ; authorized_keys options: "no-pty ssh-rsa AAAA…"
        let tokens = l.split(separator: " ").map(String.init)
        guard let typeIdx = tokens.firstIndex(where: { $0.hasPrefix("ssh-") || $0.hasPrefix("ecdsa-") || $0.hasPrefix("sk-") }) else {
            // Maybe a bare blob
            if let d = Data(base64Encoded: l) { return try info(blob: d, comment: "") }
            throw ToolError("Not an OpenSSH public key", hint: "Expected 'ssh-ed25519 AAAA… comment' (the contents of id_ed25519.pub)")
        }
        guard tokens.count > typeIdx + 1, let blob = Data(base64Encoded: tokens[typeIdx + 1]) else { throw ToolError("Key data is not valid Base64") }
        let comment = tokens.dropFirst(typeIdx + 2).joined(separator: " ")
        l = ""
        return try info(blob: blob, comment: comment)
    }

    static func info(blob: Data, comment: String) throws -> KeyInfo {
        var r = ByteReader(blob)
        func field() throws -> Data { let n = Int(try r.uint(4)); return Data(try r.take(n)) }
        let type = String(decoding: try field(), as: UTF8.self)
        var bits = 0
        switch type {
        case "ssh-rsa": _ = try field(); let n = try field(); bits = (n.count - (n.first == 0 ? 1 : 0)) * 8
        case "ssh-ed25519", "sk-ssh-ed25519@openssh.com": bits = 256
        case "ssh-dss": _ = try field(); bits = 1024
        case "ecdsa-sha2-nistp256", "sk-ecdsa-sha2-nistp256@openssh.com": bits = 256
        case "ecdsa-sha2-nistp384": bits = 384
        case "ecdsa-sha2-nistp521": bits = 521
        default: throw ToolError("Unknown key type \(type)")
        }
        let sha = Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let md5 = Data(Insecure.MD5.hash(data: blob)).hexString.chunked(2).joined(separator: ":")
        return KeyInfo(type: type, bits: bits, comment: comment, sha256: "SHA256:" + sha, md5: "MD5:" + md5, blob: blob)
    }

    /// OpenSSH "drunken bishop" randomart.
    public static func randomart(_ digest: Data, title: String, bottom: String) -> String {
        let w = 17, h = 9
        var field = [[Int]](repeating: [Int](repeating: 0, count: w), count: h)
        var x = w / 2, y = h / 2
        for byte in digest {
            var b = byte
            for _ in 0..<4 {
                x += (b & 1) != 0 ? 1 : -1
                y += (b & 2) != 0 ? 1 : -1
                x = max(0, min(w - 1, x)); y = max(0, min(h - 1, y))
                if field[y][x] < 14 { field[y][x] += 1 }
                b >>= 2
            }
        }
        field[h / 2][w / 2] = 15
        field[y][x] = 16
        let symbols = Array(" .o+=*BOX@%&#/^SE")
        func border(_ t: String) -> String {
            let inner = t.isEmpty ? String(repeating: "-", count: w) : "[" + t + "]"
            let pad = w - inner.count
            return "+" + String(repeating: "-", count: max(0, pad / 2)) + inner + String(repeating: "-", count: max(0, pad - pad / 2)) + "+"
        }
        var out = [border(title)]
        for row in field { out.append("|" + String(row.map { symbols[$0] }) + "|") }
        out.append(border(bottom))
        return out.joined(separator: "\n")
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let lines = text.components(separatedBy: "\n").map { $0.trimmed() }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        if lines.count > 1 {
            var rows: [MetaRow] = []
            var out: [String] = []
            for l in lines {
                if let k = try? Self.parse(l) { rows.append(MetaRow(k.comment.isEmpty ? k.type : k.comment, "\(k.sha256)  (\(k.type) \(k.bits))", style: .mono)); out.append("\(k.bits) \(k.sha256) \(k.comment) (\(Self.pretty(k.type)))") }
                else { out.append("? \(l.prefix(40))…") }
            }
            return ToolOutput(text: out.joined(separator: "\n"), metadata: rows)
        }
        let k = try Self.parse(text)
        let art = Self.randomart(Data(SHA256.hash(data: k.blob)), title: Self.pretty(k.type) + " " + String(k.bits), bottom: "SHA256")
        var rows = [
            MetaRow("Type", "\(Self.pretty(k.type)) (\(k.type))"), MetaRow("Bits", "\(k.bits)"), MetaRow("SHA-256", k.sha256, style: .mono), MetaRow("MD5", k.md5, style: .mono),
        ]
        if !k.comment.isEmpty { rows.append(MetaRow("Comment", k.comment)) }
        rows.append(MetaRow("ssh-keygen -l", "\(k.bits) \(k.sha256) \(k.comment) (\(Self.pretty(k.type)))", style: .mono))
        if k.type == "ssh-rsa", k.bits < 2048 { rows.append(MetaRow("Warning", "RSA keys under 2048 bits are considered weak", style: .danger)) }
        if k.type == "ssh-dss" { rows.append(MetaRow("Warning", "DSA keys are deprecated and disabled in modern OpenSSH", style: .danger)) }
        if let key = try? CryptoKeys.load(text) {
            rows.append(MetaRow("PEM (SPKI)", CryptoKeys.pem(key), style: .mono))
        }
        return ToolOutput(text: art, facets: [OutputFacet("SHA-256", text: k.sha256), OutputFacet("MD5", text: k.md5)], metadata: rows)
    }

    static func pretty(_ t: String) -> String {
        switch t {
        case "ssh-rsa": "RSA"
        case "ssh-ed25519": "ED25519"
        case "ssh-dss": "DSA"
        case "sk-ssh-ed25519@openssh.com": "ED25519-SK"
        case "sk-ecdsa-sha2-nistp256@openssh.com": "ECDSA-SK"
        default: t.hasPrefix("ecdsa") ? "ECDSA" : t
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        s.range(of: "(^|\\s)(ssh-(rsa|ed25519|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\\.com) AAAA", options: .regularExpression) != nil ? DetectionScore(0.97, "OpenSSH public key") : nil
    }
}
