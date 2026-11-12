import Foundation
import BitlatheCore

public struct Base32Tool: DevTool {
    public static let id = "base32.text"
    public static let name = "Base32"
    public static let summary = "Base32 (RFC 4648), base32hex and Crockford encode / decode"
    public static let category = ToolCategory.encode
    public static let symbol = "3.square"
    public static let keywords = ["base32", "crockford", "totp", "encode", "decode"]
    public static let samples = [ToolSample("Encode", "Bitlathe secret"), ToolSample("Decode", "IJUXI3DBORUGKIDTMVRXEZLU", options: ["mode": .string("decode")])]
    public static let optionFields: [OptionField] = [
        .encodeDecode,
        .segmented("alphabet", "Alphabet", [.init("rfc", "RFC 4648"), .init("hex", "base32hex"), .init("crockford", "Crockford")], default: "rfc"),
        .toggle("padding", "Padding", default: true, visibleWhen: ("mode", ["encode"])),
    ]
    public struct Options: ToolOptions {
        public var mode = "encode"
        public var alphabet = "rfc"
        public var padding = true
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let alphabet = options.alphabet == "hex" ? BaseN.base32HexAlphabet : (options.alphabet == "crockford" ? BaseN.crockfordAlphabet : BaseN.base32Alphabet)
        if options.mode == "encode" {
            let data = input.data
            guard !data.isEmpty else { throw ToolError.emptyInput }
            return ToolOutput(text: BaseN.base32Encode(data, alphabet: alphabet, padding: options.padding), metadata: [MetaRow("Bytes", "\(data.count)")])
        }
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let data = try BaseN.base32Decode(text, alphabet: alphabet)
        if let s = String(data: data, encoding: .utf8) { return ToolOutput(text: s, metadata: [MetaRow("Bytes", "\(data.count)")]) }
        return ToolOutput(.data(data), metadata: [MetaRow("Bytes", "\(data.count)")], warnings: ["Decoded data is not UTF-8 text"])
    }
    public static func detect(_ s: String) -> DetectionScore? {
        let t = s.filter { !$0.isWhitespace }
        guard t.count >= 16, t.range(of: "^[A-Z2-7]+=*$", options: .regularExpression) != nil, t.count % 8 == 0 || t.hasSuffix("=") else { return nil }
        return DetectionScore(0.6, "Base32 text", options: ["mode": .string("decode")])
    }
}

public struct Base58Tool: DevTool {
    public static let id = "base58.text"
    public static let name = "Base58"
    public static let summary = "Base58 (Bitcoin alphabet) encode / decode, with optional Base58Check"
    public static let category = ToolCategory.encode
    public static let symbol = "bitcoinsign.circle"
    public static let keywords = ["base58", "bitcoin", "ipfs", "solana", "encode", "decode", "base58check"]
    public static let samples = [ToolSample("Encode", "Hello Base58"), ToolSample("Decode", "2NEpo7TZRFNEKpLHM", options: ["mode": .string("decode")])]
    public static let optionFields: [OptionField] = [
        .encodeDecode,
        .toggle("check", "Base58Check (SHA-256d checksum)"),
        .toggle("inputHex", "Input is hex", visibleWhen: ("mode", ["encode"])),
    ]
    public struct Options: ToolOptions {
        public var mode = "encode"
        public var check = false
        public var inputHex = false
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        if options.mode == "encode" {
            var data = options.inputHex ? (Data(hex: input.text.trimmed()) ?? Data()) : input.data
            guard !data.isEmpty else { throw ToolError(options.inputHex ? "Invalid hex input" : "Nothing to process") }
            if options.check { data += Hashing.sha256d(data).prefix(4) }
            return ToolOutput(text: BaseN.base58Encode(data), metadata: [MetaRow("Bytes", "\(data.count)")])
        }
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        var data = try BaseN.base58Decode(text)
        var meta = [MetaRow("Bytes", "\(data.count)")]
        if options.check {
            guard data.count >= 4 else { throw ToolError("Too short for Base58Check") }
            let payload = data.prefix(data.count - 4)
            let checksum = data.suffix(4)
            let ok = Hashing.sha256d(payload).prefix(4) == checksum
            meta.append(MetaRow("Checksum", ok ? "Valid" : "Invalid", style: ok ? .success : .danger))
            data = Data(payload)
            if !ok { throw ToolError("Base58Check checksum does not match") }
        }
        meta.append(MetaRow("Hex", data.hexString, style: .mono))
        if let s = String(data: data, encoding: .utf8), s.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0 == "\n" || $0 == "\t" }) {
            return ToolOutput(text: s, facets: [OutputFacet("Hex", text: data.hexString)], metadata: meta)
        }
        return ToolOutput(text: data.hexString, language: .hex, metadata: meta, warnings: ["Decoded data is binary; showing hex"])
    }
    public static func detect(_ s: String) -> DetectionScore? {
        guard s.count >= 20, s.count <= 120, Detect.isSingleLine(s), s.range(of: "^[1-9A-HJ-NP-Za-km-z]+$", options: .regularExpression) != nil else { return nil }
        if s.hasPrefix("1") || s.hasPrefix("3") || s.hasPrefix("Qm") || s.hasPrefix("bc1") == false && s.count >= 32 { return DetectionScore(0.45, "Base58 string", options: ["mode": .string("decode")]) }
        return nil
    }
}

public struct Base85Tool: DevTool {
    public static let id = "base85.text"
    public static let name = "Base85 / Ascii85"
    public static let summary = "Ascii85 (Adobe), Z85 and RFC 1924 Base85 encode / decode"
    public static let category = ToolCategory.encode
    public static let symbol = "8.square"
    public static let keywords = ["base85", "ascii85", "z85", "encode", "decode", "pdf", "git"]
    public static let samples = [ToolSample("Encode", "Hello, Bitlathe!"), ToolSample("Decode", "<~87cURD_*\"tBln0\"FD,5/~>", options: ["mode": .string("decode")])]
    public static let optionFields: [OptionField] = [
        .encodeDecode,
        .segmented("variant", "Variant", [.init("ascii85", "Ascii85"), .init("z85", "Z85"), .init("rfc1924", "RFC 1924")], default: "ascii85"),
        .toggle("delimiters", "<~ ~> delimiters", default: true, visibleWhen: ("variant", ["ascii85"])),
    ]
    public struct Options: ToolOptions {
        public var mode = "encode"
        public var variant = "ascii85"
        public var delimiters = true
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        if options.mode == "encode" {
            let data = input.data
            guard !data.isEmpty else { throw ToolError.emptyInput }
            let out: String = switch options.variant {
            case "z85": BaseN.base85Encode(data, alphabet: BaseN.z85Alphabet)
            case "rfc1924": BaseN.base85Encode(data, alphabet: BaseN.rfc1924Alphabet)
            default: BaseN.ascii85Encode(data, delimiters: options.delimiters)
            }
            return ToolOutput(text: out, metadata: [MetaRow("Bytes", "\(data.count)")])
        }
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let data: Data = switch options.variant {
        case "z85": try BaseN.base85Decode(text, alphabet: BaseN.z85Alphabet)
        case "rfc1924": try BaseN.base85Decode(text, alphabet: BaseN.rfc1924Alphabet)
        default: try BaseN.ascii85Decode(text)
        }
        if let s = String(data: data, encoding: .utf8) { return ToolOutput(text: s, metadata: [MetaRow("Bytes", "\(data.count)")]) }
        return ToolOutput(.data(data), metadata: [MetaRow("Bytes", "\(data.count)")], warnings: ["Decoded data is not UTF-8 text"])
    }
    public static func detect(_ s: String) -> DetectionScore? {
        s.hasPrefix("<~") && s.hasSuffix("~>") ? DetectionScore(0.9, "Ascii85 with delimiters", options: ["mode": .string("decode")]) : nil
    }
}
