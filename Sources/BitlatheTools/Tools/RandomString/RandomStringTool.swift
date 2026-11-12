import Foundation
import Security
import BitlatheCore

public struct RandomStringTool: DevTool {
    public static let id = "random.string"
    public static let name = "Password & Random String"
    public static let summary = "Cryptographically random strings, passwords, PINs, hex/Base64 tokens and diceware passphrases with a strength meter"
    public static let category = ToolCategory.generate
    public static let symbol = "dice"
    public static let keywords = ["random", "password", "passphrase", "diceware", "token", "secret", "generate", "pin", "api key", "entropy"]
    public static let io = ToolIO.generator
    public static let optionFields: [OptionField] = [
        .picker("kind", "Kind", [.init("password", "Password"), .init("passphrase", "Passphrase (diceware)"), .init("hex", "Hex bytes"), .init("base64", "Base64 bytes"), .init("base64url", "Base64URL bytes"), .init("alnum", "Alphanumeric"), .init("pin", "Numeric PIN"), .init("custom", "Custom alphabet")], default: "password"),
        .stepper("length", "Length", min: 1, max: 1024, default: 20, visibleWhen: ("kind", ["password", "alnum", "pin", "custom"])),
        .stepper("bytes", "Bytes", min: 1, max: 1024, default: 32, visibleWhen: ("kind", ["hex", "base64", "base64url"])),
        .stepper("words", "Words", min: 2, max: 20, default: 6, visibleWhen: ("kind", ["passphrase"])),
        .text("separator", "Separator", placeholder: "-", default: "-", visibleWhen: ("kind", ["passphrase"])),
        .toggle("capitalize", "Capitalise words", visibleWhen: ("kind", ["passphrase"])),
        .toggle("addNumber", "Add a number", visibleWhen: ("kind", ["passphrase"])),
        .toggle("lower", "a-z", default: true, visibleWhen: ("kind", ["password"])),
        .toggle("upper", "A-Z", default: true, visibleWhen: ("kind", ["password"])),
        .toggle("digits", "0-9", default: true, visibleWhen: ("kind", ["password"])),
        .toggle("symbols", "!@#…", default: true, visibleWhen: ("kind", ["password"])),
        .toggle("excludeAmbiguous", "No ambiguous (0O1lI|)", default: true, visibleWhen: ("kind", ["password", "alnum"])),
        .text("alphabet", "Alphabet", placeholder: "characters to pick from", visibleWhen: ("kind", ["custom"])),
        .stepper("count", "Count", min: 1, max: 100, default: 5),
    ]
    public struct Options: ToolOptions {
        public var kind = "password"
        public var length = 20
        public var bytes = 32
        public var words = 6
        public var separator = "-"
        public var capitalize = false
        public var addNumber = false
        public var lower = true
        public var upper = true
        public var digits = true
        public var symbols = true
        public var excludeAmbiguous = true
        public var alphabet = ""
        public var count = 5
        public init() {}
    }
    public init() {}

    static func randomBytes(_ n: Int) -> Data {
        var d = Data(count: n)
        let status = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }   // swiftlint:disable:this force_unwrapping
        precondition(status == errSecSuccess)
        return d
    }

    /// Unbiased index in 0..<n.
    static func randomIndex(_ n: Int) -> Int { Int.random(in: 0..<n, using: &SystemRNG.shared) }

    struct SystemRNG: RandomNumberGenerator {
        nonisolated(unsafe) static var shared = SystemRNG()
        mutating func next() -> UInt64 { var v: UInt64 = 0; _ = withUnsafeMutableBytes(of: &v) { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }; return v }   // swiftlint:disable:this force_unwrapping
    }

    nonisolated(unsafe) static var wordlistCache: [String]?
    public static var wordlist: [String] {
        if let w = wordlistCache { return w }
        let text = JSBundles.resourceText("eff_short_wordlist.txt")
        var words = text.split(separator: "\n").map { $0.trimmed() }.filter { !$0.isEmpty }
        if words.count < 100 { words = ["apple", "river", "stone", "cloud", "amber", "quiet", "maple", "ocean", "pixel", "zebra", "lemon", "fjord", "cobalt", "ember", "harbor", "ivory", "jungle", "kettle", "lunar", "meadow", "nectar", "orbit", "prism", "quartz", "raven", "saffron", "tundra", "umbra", "velvet", "willow", "xenon", "yonder", "zephyr"] }
        wordlistCache = words
        return words
    }

    public static func entropyBits(poolSize: Int, length: Int) -> Double { Double(length) * log2(Double(max(poolSize, 1))) }

    public static func strength(bits: Double) -> (label: String, crackTime: String, style: MetaRow.Style) {
        // 10^10 guesses/second offline (fast hash), average case = half the keyspace.
        let seconds = pow(2, bits - 1) / 1e10
        let time: String
        switch seconds {
        case ..<1: time = "instantly"
        case ..<60: time = "\(Int(seconds)) seconds"
        case ..<3600: time = "\(Int(seconds / 60)) minutes"
        case ..<86400: time = "\(Int(seconds / 3600)) hours"
        case ..<31_557_600: time = "\(Int(seconds / 86400)) days"
        case ..<31_557_600e3: time = "\(Int(seconds / 31_557_600)) years"
        case ..<31_557_600e6: time = String(format: "%.0f thousand years", seconds / 31_557_600e3)
        case ..<31_557_600e9: time = String(format: "%.0f million years", seconds / 31_557_600e6)
        default: time = String(format: "%.1e years", seconds / 31_557_600)
        }
        let label = bits < 40 ? "Very weak" : (bits < 60 ? "Weak" : (bits < 80 ? "Fair" : (bits < 100 ? "Strong" : "Very strong")))
        let style: MetaRow.Style = bits < 60 ? .danger : (bits < 80 ? .warning : .success)
        return (label, "~\(time) at 10 billion guesses/s", style)
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        var results: [String] = []
        var bits = 0.0
        var detail = ""
        for _ in 0..<options.count {
            switch options.kind {
            case "passphrase":
                let words = Self.wordlist
                var picked = (0..<options.words).map { _ in words[Self.randomIndex(words.count)] }
                if options.capitalize { picked = picked.map { $0.capitalizedFirst() } }
                var s = picked.joined(separator: options.separator)
                if options.addNumber { s += options.separator + String(Self.randomIndex(100)) }
                results.append(s)
                bits = Self.entropyBits(poolSize: words.count, length: options.words) + (options.addNumber ? log2(100) : 0)
                detail = "\(words.count)-word list × \(options.words) words"
            case "hex":
                results.append(Self.randomBytes(options.bytes).hexString)
                bits = Double(options.bytes * 8); detail = "\(options.bytes) random bytes"
            case "base64":
                results.append(Self.randomBytes(options.bytes).base64EncodedString())
                bits = Double(options.bytes * 8); detail = "\(options.bytes) random bytes"
            case "base64url":
                results.append(Self.randomBytes(options.bytes).base64URL)
                bits = Double(options.bytes * 8); detail = "\(options.bytes) random bytes"
            case "pin":
                results.append(String((0..<options.length).map { _ in Character(String(Self.randomIndex(10))) }))
                bits = Self.entropyBits(poolSize: 10, length: options.length); detail = "digits only"
            default:
                var pool = ""
                switch options.kind {
                case "alnum": pool = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
                case "custom": pool = String(Set(options.alphabet).sorted())
                default:
                    if options.lower { pool += "abcdefghijklmnopqrstuvwxyz" }
                    if options.upper { pool += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
                    if options.digits { pool += "0123456789" }
                    if options.symbols { pool += "!@#$%^&*()-_=+[]{};:,.<>?/~" }
                }
                if options.excludeAmbiguous, options.kind != "custom" { pool = pool.filter { !"0O1lI|`'\"".contains($0) } }
                guard !pool.isEmpty else { throw ToolError("Choose at least one character set") }
                let chars = Array(pool)
                var s: String
                repeat {
                    s = String((0..<options.length).map { _ in chars[Self.randomIndex(chars.count)] })
                } while options.kind == "password" && options.length >= 4 && !Self.hasEachClass(s, options)
                results.append(s)
                bits = Self.entropyBits(poolSize: chars.count, length: options.length)
                detail = "\(chars.count)-character pool × \(options.length)"
            }
        }
        let st = Self.strength(bits: bits)
        let rows = [MetaRow("Entropy", String(format: "%.0f bits (%@)", bits, detail)), MetaRow("Strength", st.label, style: st.style), MetaRow("Offline crack time", st.crackTime), MetaRow("Source", "SecRandomCopyBytes (CSPRNG)")]
        return ToolOutput(text: results.joined(separator: "\n"), metadata: rows)
    }

    static func hasEachClass(_ s: String, _ o: Options) -> Bool {
        (!o.lower || s.contains { $0.isLowercase }) && (!o.upper || s.contains { $0.isUppercase }) && (!o.digits || s.contains { $0.isNumber }) && (!o.symbols || s.contains { !$0.isLetter && !$0.isNumber })
    }
}
