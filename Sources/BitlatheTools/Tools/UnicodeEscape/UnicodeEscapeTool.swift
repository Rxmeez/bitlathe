import Foundation
import BitlatheCore

public struct UnicodeEscapeTool: DevTool {
    public static let id = "unicode.escape"
    public static let name = "Unicode Escape"
    public static let summary = "Convert between é, \\u00e9, \\u{e9}, &#233;, &#xE9;, %C3%A9, U+00E9 and \\xC3\\xA9"
    public static let category = ToolCategory.encode
    public static let symbol = "character.textbox"
    public static let keywords = ["unicode", "escape", "\\u", "code point", "utf-8", "percent", "entity", "emoji", "encode", "decode"]
    public static let samples = [ToolSample("Encode", "Café ✓ 👋 — naïve"), ToolSample("Decode", "Caf\\u00e9 \\u{2713} \\ud83d\\udc4b &#8212; na%C3%AFve U+1F600", options: ["mode": .string("decode")])]
    public static let optionFields: [OptionField] = [
        .encodeDecode,
        .picker("format", "Format", [.init("js", "\\uXXXX (JS/JSON, surrogates)"), .init("es6", "\\u{X} (ES6/Swift)"), .init("python", "\\UXXXXXXXX (Python/C)"), .init("decimal", "&#NNN; (HTML decimal)"),
                                     .init("hex", "&#xHH; (HTML hex)"), .init("percent", "%XX (UTF-8 percent)"), .init("codepoint", "U+XXXX"), .init("bytes", "\\xHH (UTF-8 bytes)"), .init("css", "\\HHHH (CSS)")], default: "js", visibleWhen: ("mode", ["encode"])),
        .segmented("scope", "Escape", [.init("nonascii", "Non-ASCII"), .init("all", "Everything")], default: "nonascii", visibleWhen: ("mode", ["encode"])),
    ]
    public struct Options: ToolOptions {
        public var mode = "encode"
        public var format = "js"
        public var scope = "nonascii"
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.isEmpty else { throw ToolError.emptyInput }
        if options.mode == "encode" {
            var out = ""
            var count = 0
            for u in text.unicodeScalars {
                let v = u.value
                if options.scope == "nonascii", v < 0x7F, v >= 0x20 || u == "\n" || u == "\t" || u == "\r" { out.unicodeScalars.append(u); continue }
                count += 1
                switch options.format {
                case "es6": out += String(format: "\\u{%X}", v)
                case "python": out += v > 0xFFFF ? String(format: "\\U%08X", v) : String(format: "\\u%04X", v)
                case "decimal": out += "&#\(v);"
                case "hex": out += String(format: "&#x%X;", v)
                case "percent": out += String(u).utf8.map { String(format: "%%%02X", $0) }.joined()
                case "codepoint": out += String(format: "U+%04X", v)
                case "bytes": out += String(u).utf8.map { String(format: "\\x%02X", $0) }.joined()
                case "css": out += String(format: "\\%04X ", v)
                default:
                    if v > 0xFFFF {
                        let x = v - 0x10000
                        out += String(format: "\\u%04x\\u%04x", 0xD800 + (x >> 10), 0xDC00 + (x & 0x3FF))
                    } else { out += String(format: "\\u%04x", v) }
                }
            }
            return ToolOutput(text: out.trimmingCharacters(in: options.format == "codepoint" || options.format == "css" ? .whitespaces : []), metadata: [MetaRow("Escaped", "\(count) code points")])
        }
        var out = text
        var count = 0
        // HTML entities
        let (ent, n1) = HTMLEntityTable.decode(out)
        out = ent; count += n1
        // Percent-encoded UTF-8 sequences (only runs of %XX)
        out = Self.replace(out, pattern: "(?:%[0-9A-Fa-f]{2})+", count: &count) { m in
            let bytes = m.split(separator: "%").compactMap { UInt8($0, radix: 16) }
            return String(data: Data(bytes), encoding: .utf8)
        }
        // \xHH runs as UTF-8 bytes
        out = Self.replace(out, pattern: "(?:\\\\x[0-9A-Fa-f]{2})+", count: &count) { m in
            let bytes = m.components(separatedBy: "\\x").filter { !$0.isEmpty }.compactMap { UInt8($0, radix: 16) }
            return String(data: Data(bytes), encoding: .utf8) ?? String(bytes.compactMap { UnicodeScalar($0) }.map(Character.init))
        }
        // U+XXXX
        out = Self.replace(out, pattern: "U\\+([0-9A-Fa-f]{4,6})", count: &count) { m in
            UInt32(m.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init).map { String($0) }
        }
        // CSS \HHHH 
        out = Self.replace(out, pattern: "\\\\([0-9A-Fa-f]{4,6}) ?", count: &count) { m in
            UInt32(m.dropFirst().trimmed(), radix: 16).flatMap(UnicodeScalar.init).map { String($0) }
        }
        // \u, \u{}, \U
        let before = out
        out = BackslashTool.unescape(out)
        if before != out { count += before.matches(of: /\\[uU]/).count }
        return ToolOutput(text: out, metadata: [MetaRow("Decoded", "\(count) sequences")])
    }

    static func replace(_ s: String, pattern: String, count: inout Int, _ f: (String) -> String?) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var cursor = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let matched = ns.substring(with: m.range)
            if let r = f(matched) { out += r; count += 1 } else { out += matched }
            cursor = NSMaxRange(m.range)
        }
        out += ns.substring(from: cursor)
        return out
    }

    public static func detect(_ s: String) -> DetectionScore? {
        let n = s.matches(of: /\\u[0-9A-Fa-f]{4}|\\u\{[0-9A-Fa-f]+\}|U\+[0-9A-Fa-f]{4,6}|&#x?[0-9A-Fa-f]+;/).count
        return n >= 1 && !s.hasPrefix("{") ? DetectionScore(min(0.5 + Double(n) * 0.1, 0.8), "Unicode escapes", options: ["mode": .string("decode")]) : nil
    }
}
