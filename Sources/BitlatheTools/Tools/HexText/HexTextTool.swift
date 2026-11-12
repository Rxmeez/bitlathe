import Foundation
import BitlatheCore

public struct HexTextTool: DevTool {
    public static let id = "hex.text"
    public static let name = "Hex ⇄ Text"
    public static let summary = "Convert text to hex, UTF-8 bytes, binary, decimal bytes and back"
    public static let category = ToolCategory.convert
    public static let symbol = "textformat.123"
    public static let keywords = ["hex", "ascii", "utf8", "bytes", "binary", "decimal", "octal", "convert", "dump"]
    public static let samples = [ToolSample("Text", "Hello, Bitlathe! é ✓"), ToolSample("Hex", "48 65 6c 6c 6f 2c 20 42 69 74 6c 61 74 68 65", options: ["mode": .string("decode")]),
                                 ToolSample("Binary", "01001000 01101001", options: ["mode": .string("decode"), "format": .string("binary")])]
    public static let optionFields: [OptionField] = [
        .mode([.init("encode", "Text → Bytes"), .init("decode", "Bytes → Text")], default: "encode"),
        .segmented("format", "Format", [.init("hex", "Hex"), .init("binary", "Binary"), .init("decimal", "Decimal"), .init("octal", "Octal")], default: "hex"),
        .picker("separator", "Separator", [.init("space", "Space"), .init("none", "None"), .init("colon", "Colon"), .init("comma", "0x.., 0x.."), .init("escape", "\\x..")], default: "space", visibleWhen: ("mode", ["encode"])),
        .toggle("uppercase", "Uppercase", visibleWhen: ("mode", ["encode"])),
        .picker("encoding", "Encoding", [.init("utf8", "UTF-8"), .init("utf16", "UTF-16 BE"), .init("utf16le", "UTF-16 LE"), .init("latin1", "Latin-1"), .init("ascii", "ASCII")], default: "utf8", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var mode = "encode"
        public var format = "hex"
        public var separator = "space"
        public var uppercase = false
        public var encoding = "utf8"
        public init() {}
    }
    public init() {}

    static func encoding(_ s: String) -> String.Encoding {
        switch s {
        case "utf16": .utf16BigEndian
        case "utf16le": .utf16LittleEndian
        case "latin1": .isoLatin1
        case "ascii": .ascii
        default: .utf8
        }
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let enc = Self.encoding(options.encoding)
        if options.mode == "encode" {
            guard let data = text.data(using: enc) else { throw ToolError("Text cannot be represented in \(options.encoding.uppercased())") }
            let bytes = [UInt8](data)
            let radix = options.format == "binary" ? 2 : (options.format == "decimal" ? 10 : (options.format == "octal" ? 8 : 16))
            let width = options.format == "binary" ? 8 : (options.format == "hex" ? 2 : (options.format == "octal" ? 3 : 0))
            var parts = bytes.map { b -> String in
                var s = String(b, radix: radix)
                if options.uppercase { s = s.uppercased() }
                if width > 0 { s = String(repeating: "0", count: max(0, width - s.count)) + s }
                return s
            }
            let out: String
            switch options.separator {
            case "none": out = parts.joined()
            case "colon": out = parts.joined(separator: ":")
            case "comma": out = parts.map { (options.format == "hex" ? "0x" : (options.format == "binary" ? "0b" : "")) + $0 }.joined(separator: ", ")
            case "escape": parts = parts.map { "\\x" + $0 }; out = parts.joined()
            default: out = parts.joined(separator: " ")
            }
            return ToolOutput(text: out, language: .hex, metadata: [MetaRow("Bytes", "\(bytes.count)"), MetaRow("Characters", "\(text.count)")])
        }
        // decode
        var clean = text.replacingOccurrences(of: "0x", with: " ").replacingOccurrences(of: "0b", with: " ").replacingOccurrences(of: "\\x", with: " ")
        clean = clean.replacingOccurrences(of: "[,:;\\n\\t]", with: " ", options: .regularExpression)
        var bytes: [UInt8] = []
        let radix = options.format == "binary" ? 2 : (options.format == "decimal" ? 10 : (options.format == "octal" ? 8 : 16))
        let chunks = clean.split(separator: " ").map(String.init)
        if chunks.count == 1, options.format == "hex" || options.format == "binary" {
            let width = options.format == "binary" ? 8 : 2
            let s = chunks[0]
            guard s.count % width == 0 else { throw ToolError("Expected groups of \(width) \(options.format) digits (got \(s.count) characters)") }
            var idx = s.startIndex
            while idx < s.endIndex {
                let end = s.index(idx, offsetBy: width)
                guard let b = UInt8(s[idx..<end], radix: radix) else { throw ToolError("\"\(s[idx..<end])\" is not valid \(options.format)") }
                bytes.append(b)
                idx = end
            }
        } else {
            for c in chunks {
                guard let b = UInt8(c, radix: radix) else { throw ToolError("\"\(c)\" is not a valid \(options.format) byte") }
                bytes.append(b)
            }
        }
        guard let out = String(data: Data(bytes), encoding: enc) else {
            throw ToolError("Bytes are not valid \(options.encoding.uppercased())", hint: "Try another encoding in the advanced options")
        }
        return ToolOutput(text: out, metadata: [MetaRow("Bytes", "\(bytes.count)"), MetaRow("Characters", "\(out.count)")])
    }

    public static func detect(_ s: String) -> DetectionScore? {
        let compact = s.replacingOccurrences(of: "[\\s:,]|0x|\\\\x", with: "", options: .regularExpression)
        guard compact.count >= 8 else { return nil }
        if compact.range(of: "^[01]+$", options: .regularExpression) != nil, compact.count % 8 == 0, s.contains(" ") { return DetectionScore(0.7, "Binary bytes", options: ["mode": .string("decode"), "format": .string("binary")]) }
        if s.contains(" ") || s.contains(":") || s.contains("\\x"), compact.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil, compact.count % 2 == 0, compact.count < 2000,
           let d = Data(hex: compact), String(data: d, encoding: .utf8)?.allSatisfy({ !$0.isASCII || $0.isLetter || $0.isNumber || $0.isPunctuation || $0.isWhitespace || $0.isSymbol }) == true {
            return DetectionScore(0.6, "Hex bytes", options: ["mode": .string("decode")])
        }
        return nil
    }
}
