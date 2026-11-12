import Foundation
import BitlatheCore

public struct PasswordHashTool: DevTool {
    public static let id = "password.hash"
    public static let name = "Password Hashing"
    public static let summary = "Hash and verify passwords with bcrypt, scrypt and Argon2id"
    public static let category = ToolCategory.generate
    public static let symbol = "lock.shield"
    public static let keywords = ["password", "bcrypt", "scrypt", "argon2", "argon2id", "hash", "verify", "kdf", "salt"]
    public static let historyEnabledByDefault = false
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: false)
    public static let samples = [ToolSample("Hash", "correct horse battery staple"), ToolSample("Verify bcrypt", "password", options: ["mode": .string("verify"), "hash": .string("$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy")])]
    public static let optionFields: [OptionField] = [
        .mode([.init("hash", "Hash"), .init("verify", "Verify")], default: "hash"),
        .segmented("algorithm", "Algorithm", [.init("bcrypt", "bcrypt"), .init("scrypt", "scrypt"), .init("argon2id", "Argon2id")], default: "bcrypt", visibleWhen: ("mode", ["hash"])),
        .stepper("cost", "Cost", min: 4, max: 16, default: 10, help: "bcrypt work factor (2^cost rounds)", visibleWhen: ("algorithm", ["bcrypt"])),
        .picker("scryptN", "N", [.init("14", "2^14 (16 MiB)"), .init("15", "2^15 (32 MiB)"), .init("16", "2^16 (64 MiB)"), .init("17", "2^17 (128 MiB)")], default: "15", visibleWhen: ("algorithm", ["scrypt"])),
        .stepper("memoryMiB", "Memory (MiB)", min: 8, max: 512, step: 8, default: 64, visibleWhen: ("algorithm", ["argon2id"])),
        .stepper("iterations", "Iterations", min: 1, max: 10, default: 3, visibleWhen: ("algorithm", ["argon2id"])),
        .stepper("parallelism", "Parallelism", min: 1, max: 8, default: 1, visibleWhen: ("algorithm", ["argon2id"])),
        .text("hash", "Hash to verify", placeholder: "$2b$10$… / $argon2id$… / $scrypt$…", visibleWhen: ("mode", ["verify"])),
    ]
    public struct Options: ToolOptions {
        public var mode = "hash"
        public var algorithm = "bcrypt"
        public var cost = 10
        public var scryptN = "15"
        public var memoryMiB = 64
        public var iterations = 3
        public var parallelism = 1
        public var hash = ""
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let password = input.text.hasSuffix("\n") ? String(input.text.dropLast()) : input.text
        guard !password.isEmpty else { throw ToolError("Enter a password") }
        let clock = ContinuousClock()
        if options.mode == "verify" {
            let h = options.hash.trimmed()
            guard !h.isEmpty else { throw ToolError("Paste the stored hash in the options bar") }
            let start = clock.now
            let ok: Bool
            let algo: String
            if h.hasPrefix("$2") { ok = try Bcrypt.verify(password, hash: h); algo = "bcrypt" }
            else if h.hasPrefix("$argon2") { ok = try Argon2.verify(password: Data(password.utf8), encoded: h); algo = h.split(separator: "$").first.map(String.init) ?? "argon2" }
            else if h.hasPrefix("$scrypt$") || h.hasPrefix("$7$") { ok = try Self.verifyScrypt(password, h); algo = "scrypt" }
            else { throw ToolError("Unrecognised hash format", hint: "Supported: $2b$ (bcrypt), $argon2id$, $scrypt$ln=…") }
            let dur = clock.now - start
            return ToolOutput(text: ok ? "✓ Password matches" : "✗ Password does not match", metadata: [MetaRow("Algorithm", algo), MetaRow("Result", ok ? "Match" : "No match", style: ok ? .success : .danger), MetaRow("Time", DurationFormatter.ms(dur))], isValid: ok)
        }
        let start = clock.now
        var hash: String
        var rows: [MetaRow] = []
        switch options.algorithm {
        case "scrypt":
            let logN = Int(options.scryptN) ?? 15
            let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            let dk = try Scrypt.derive(password: Data(password.utf8), salt: salt, n: 1 << logN, r: 8, p: 1, length: 32)
            hash = "$scrypt$ln=\(logN),r=8,p=1$\(salt.base64URL)$\(dk.base64URL)"
            rows = [MetaRow("Parameters", "N=2^\(logN), r=8, p=1 · \((1 << logN) * 128 * 8 / 1_048_576) MiB"), MetaRow("Salt", salt.hexString, style: .mono)]
        case "argon2id":
            let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            hash = try Argon2.encoded(password: Data(password.utf8), salt: salt, iterations: options.iterations, memoryKiB: options.memoryMiB * 1024, parallelism: options.parallelism)
            rows = [MetaRow("Parameters", "m=\(options.memoryMiB) MiB, t=\(options.iterations), p=\(options.parallelism)"), MetaRow("Salt", salt.hexString, style: .mono)]
        default:
            hash = try Bcrypt.hash(password, cost: options.cost)
            rows = [MetaRow("Cost", "\(options.cost) (2^\(options.cost) = \(1 << options.cost) rounds)")]
            if password.utf8.count > 72 { rows.append(MetaRow("Warning", "bcrypt only uses the first 72 bytes of the password", style: .warning)) }
        }
        let dur = clock.now - start
        rows.insert(MetaRow("Algorithm", options.algorithm), at: 0)
        rows.append(MetaRow("Time", DurationFormatter.ms(dur) + (dur < .milliseconds(50) ? " — consider a higher cost for production" : "")))
        rows.append(MetaRow("Length", "\(hash.count) chars"))
        return ToolOutput(text: hash, metadata: rows)
    }

    static func verifyScrypt(_ password: String, _ h: String) throws -> Bool {
        let parts = h.split(separator: "$").map(String.init)
        guard parts.count == 4 else { throw ToolError("Invalid scrypt hash") }
        var ln = 15, r = 8, p = 1
        for kv in parts[1].split(separator: ",") {
            let x = kv.split(separator: "=")
            guard x.count == 2, let v = Int(x[1]) else { continue }
            switch x[0] { case "ln": ln = v; case "r": r = v; case "p": p = v; default: break }
        }
        guard let salt = Data(base64URL: parts[2]), let expected = Data(base64URL: parts[3]) else { throw ToolError("Invalid Base64 in scrypt hash") }
        let dk = try Scrypt.derive(password: Data(password.utf8), salt: salt, n: 1 << ln, r: r, p: p, length: expected.count)
        return dk == expected
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.range(of: "^\\$2[abxy]\\$\\d{2}\\$[./A-Za-z0-9]{53}$", options: .regularExpression) != nil { return DetectionScore(0.95, "bcrypt hash", options: ["mode": .string("verify"), "hash": .string(s)]) }
        if s.hasPrefix("$argon2") { return DetectionScore(0.95, "Argon2 hash", options: ["mode": .string("verify"), "hash": .string(s)]) }
        if s.hasPrefix("$scrypt$") { return DetectionScore(0.9, "scrypt hash", options: ["mode": .string("verify"), "hash": .string(s)]) }
        return nil
    }
}
