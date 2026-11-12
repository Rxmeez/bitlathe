import Foundation
import CryptoKit
import BitlatheCore

public struct AESGCMTool: DevTool {
    public static let id = "aes.gcm"
    public static let name = "AES-GCM Encrypt / Decrypt"
    public static let summary = "Authenticated encryption of text with a passphrase (PBKDF2-SHA256) or a raw key, plus ChaCha20-Poly1305"
    public static let category = ToolCategory.generate
    public static let symbol = "lock.rotation"
    public static let keywords = ["aes", "gcm", "encrypt", "decrypt", "chacha20", "poly1305", "passphrase", "cipher", "symmetric", "pbkdf2"]
    public static let historyEnabledByDefault = false
    public static let samples = [ToolSample("Encrypt", "Meet at the usual place at 9.", options: ["passphrase": .string("hunter2")])]
    public static let optionFields: [OptionField] = [
        .mode([.init("encrypt", "Encrypt"), .init("decrypt", "Decrypt")], default: "encrypt"),
        .segmented("cipher", "Cipher", [.init("aes256", "AES-256-GCM"), .init("aes128", "AES-128-GCM"), .init("chacha", "ChaCha20-Poly1305")], default: "aes256"),
        .segmented("keyMode", "Key", [.init("passphrase", "Passphrase"), .init("raw", "Raw key (hex/Base64)")], default: "passphrase"),
        .secret("passphrase", "Passphrase", placeholder: "passphrase", visibleWhen: ("keyMode", ["passphrase"])),
        .secret("rawKey", "Key", placeholder: "32 bytes as hex or Base64", visibleWhen: ("keyMode", ["raw"])),
        .segmented("encoding", "Output", [.init("base64", "Base64"), .init("hex", "Hex")], default: "base64", visibleWhen: ("mode", ["encrypt"])),
        .text("aad", "Associated data", placeholder: "optional, authenticated but not encrypted", advanced: true),
        .stepper("iterations", "PBKDF2 iterations", min: 1000, max: 2_000_000, step: 10000, default: 600_000, visibleWhen: ("keyMode", ["passphrase"]), advanced: true),
    ]
    public struct Options: ToolOptions {
        public var mode = "encrypt"
        public var cipher = "aes256"
        public var keyMode = "passphrase"
        public var passphrase = ""
        public var rawKey = ""
        public var encoding = "base64"
        public var aad = ""
        public var iterations = 600_000
        public init() {}
    }
    public init() {}

    static let magic = Data("BL1".utf8)   // format: "BL1" + cipherByte + salt(16) + nonce(12) + ciphertext + tag(16)

    func key(_ options: Options, salt: Data) throws -> SymmetricKey {
        let size = options.cipher == "aes128" ? 16 : 32
        if options.keyMode == "raw" {
            let raw = options.rawKey.trimmed()
            guard !raw.isEmpty else { throw ToolError("Enter the raw key") }
            let d = Data(hex: raw) ?? Data(base64Encoded: raw) ?? Data(base64URL: raw) ?? Data()
            guard d.count == size else { throw ToolError("Key must be \(size) bytes (\(size * 8)-bit); got \(d.count)") }
            return SymmetricKey(data: d)
        }
        guard !options.passphrase.isEmpty else { throw ToolError("Enter a passphrase") }
        return SymmetricKey(data: PBKDF2.sha256(password: Data(options.passphrase.utf8), salt: salt, iterations: options.iterations, length: size))
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let aad = Data(options.aad.utf8)
        if options.mode == "encrypt" {
            let plaintext = input.data
            guard !plaintext.isEmpty else { throw ToolError.emptyInput }
            let salt = RandomStringTool.randomBytes(16)
            let k = try key(options, salt: salt)
            var out = Self.magic + Data([options.cipher == "aes128" ? 1 : (options.cipher == "chacha" ? 2 : 0)]) + salt
            if options.cipher == "chacha" {
                let nonce = ChaChaPoly.Nonce()
                let box = try ChaChaPoly.seal(plaintext, using: k, nonce: nonce, authenticating: aad)
                out += Data(nonce) + box.ciphertext + box.tag
            } else {
                let nonce = AES.GCM.Nonce()
                let box = try AES.GCM.seal(plaintext, using: k, nonce: nonce, authenticating: aad)
                out += Data(nonce) + box.ciphertext + box.tag
            }
            let text = options.encoding == "hex" ? out.hexString : out.base64EncodedString()
            let rows = [MetaRow("Cipher", options.cipher == "chacha" ? "ChaCha20-Poly1305" : (options.cipher == "aes128" ? "AES-128-GCM" : "AES-256-GCM")),
                        MetaRow("Key derivation", options.keyMode == "raw" ? "Raw key" : "PBKDF2-HMAC-SHA256, \(options.iterations) iterations, 16-byte salt"),
                        MetaRow("Layout", "magic(3) · cipher(1) · salt(16) · nonce(12) · ciphertext(\(plaintext.count)) · tag(16)"), MetaRow("Output", "\(out.count) bytes")]
            return ToolOutput(text: text, metadata: rows, warnings: options.keyMode == "passphrase" && options.passphrase.count < 12 ? ["Short passphrase — use 12+ characters or a diceware passphrase"] : [])
        }
        let raw = input.text.trimmed()
        guard let blob = Data(base64Encoded: raw.filter { !$0.isWhitespace }) ?? Data(hex: raw) ?? Data(base64URL: raw), blob.count > 3 + 1 + 16 + 12 + 16 else {
            throw ToolError("Input is not a Bitlathe ciphertext", hint: "Expected Base64 or hex produced by this tool (starts with Qkwx in Base64 / 424c31 in hex)")
        }
        guard blob.prefix(3) == Self.magic else { throw ToolError("Missing BL1 header — this ciphertext was not produced by this tool") }
        let cipherByte = blob[3]
        var o = options
        o.cipher = cipherByte == 1 ? "aes128" : (cipherByte == 2 ? "chacha" : "aes256")
        let salt = blob.subdata(in: 4..<20)
        let nonce = blob.subdata(in: 20..<32)
        let tag = blob.suffix(16)
        let ciphertext = blob.subdata(in: 32..<(blob.count - 16))
        let k = try key(o, salt: salt)
        let plain: Data
        do {
            if o.cipher == "chacha" {
                plain = try ChaChaPoly.open(ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonce), ciphertext: ciphertext, tag: tag), using: k, authenticating: aad)
            } else {
                plain = try AES.GCM.open(AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag), using: k, authenticating: aad)
            }
        } catch {
            throw ToolError("Decryption failed: wrong passphrase/key, wrong associated data, or tampered data")
        }
        let rows = [MetaRow("Cipher", o.cipher == "chacha" ? "ChaCha20-Poly1305" : (o.cipher == "aes128" ? "AES-128-GCM" : "AES-256-GCM")), MetaRow("Authenticated", "Tag verified", style: .success), MetaRow("Plaintext", "\(plain.count) bytes")]
        if let s = String(data: plain, encoding: .utf8) { return ToolOutput(text: s, metadata: rows, isValid: true) }
        if let f = ImageFormat.sniff(plain) { return ToolOutput(.image(plain, f), metadata: rows, isValid: true) }
        return ToolOutput(.data(plain), metadata: rows, isValid: true)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        let t = s.filter { !$0.isWhitespace }
        if t.hasPrefix("Qkwx") || t.lowercased().hasPrefix("424c31") { return DetectionScore(0.9, "Bitlathe AES-GCM ciphertext", options: ["mode": .string("decrypt")]) }
        return nil
    }
}
