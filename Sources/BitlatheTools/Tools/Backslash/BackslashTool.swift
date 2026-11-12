import Foundation
import BitlatheCore

public struct BackslashTool: DevTool {
    public static let id = "text.backslash"
    public static let name = "Backslash Escape"
    public static let summary = "Escape or unescape backslash sequences (\\n, \\t, \\\", \\\\, \\uXXXX)"
    public static let category = ToolCategory.encode
    public static let symbol = "arrow.turn.down.left"
    public static let keywords = ["backslash", "escape", "unescape", "newline", "\\n", "string literal"]
    public static let samples = [ToolSample("Escape", "Line one\nLine \"two\"\tTabbed \\ backslash"), ToolSample("Unescape", "Hello\\nWorld\\t\\\"quoted\\\" \\u00e9 \\x41", options: ["mode": .string("unescape")])]
    public static let optionFields: [OptionField] = [
        .mode([.init("escape", "Escape"), .init("unescape", "Unescape")], default: "escape"),
        .toggle("escapeUnicode", "Escape non-ASCII", visibleWhen: ("mode", ["escape"])),
        .toggle("escapeQuotes", "Escape quotes", default: true, visibleWhen: ("mode", ["escape"])),
    ]
    public struct Options: ToolOptions {
        public var mode = "escape"
        public var escapeUnicode = false
        public var escapeQuotes = true
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.isEmpty else { throw ToolError.emptyInput }
        if options.mode == "escape" {
            var out = ""
            for u in text.unicodeScalars {
                switch u {
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case "\u{08}": out += "\\b"
                case "\u{0C}": out += "\\f"
                case "\u{0B}": out += "\\v"
                case "\0": out += "\\0"
                case "\"": out += options.escapeQuotes ? "\\\"" : "\""
                case "'": out += options.escapeQuotes ? "\\'" : "'"
                default:
                    if u.value < 0x20 { out += String(format: "\\x%02x", u.value) }
                    else if options.escapeUnicode, u.value > 0x7E {
                        out += u.value > 0xFFFF ? String(format: "\\U%08x", u.value) : String(format: "\\u%04x", u.value)
                    } else { out.unicodeScalars.append(u) }
                }
            }
            return ToolOutput(text: out)
        }
        return ToolOutput(text: Self.unescape(text))
    }

    public static func unescape(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            guard c == "\\", s.index(after: i) < s.endIndex else { out.append(c); i = s.index(after: i); continue }
            let n = s[s.index(after: i)]
            var consumed = 2
            switch n {
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "v": out.append("\u{0B}")
            case "0": out.append("\0")
            case "a": out.append("\u{07}")
            case "e": out.append("\u{1B}")
            case "\\": out.append("\\")
            case "\"": out.append("\"")
            case "'": out.append("'")
            case "/": out.append("/")
            case "\n": break
            case "x":
                let afterX = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                let hex = s[afterX...].prefix(2)
                if hex.count == 2, let v = UInt32(hex, radix: 16), let u = UnicodeScalar(v) { out.unicodeScalars.append(u); consumed = 4 } else { out.append("\\x") }
            case "u":
                let afterU = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                let rest = s[afterU...]
                if rest.hasPrefix("{"), let close = rest.firstIndex(of: "}"), let v = UInt32(rest[rest.index(after: rest.startIndex)..<close], radix: 16), let u = UnicodeScalar(v) {
                    out.unicodeScalars.append(u)
                    consumed = 2 + rest.distance(from: rest.startIndex, to: close) + 1
                } else {
                    let hex = rest.prefix(4)
                    if hex.count == 4, let v = UInt32(hex, radix: 16) {
                        consumed = 6
                        if v >= 0xD800, v <= 0xDBFF, rest.dropFirst(4).hasPrefix("\\u"), let lo = UInt32(rest.dropFirst(6).prefix(4), radix: 16), lo >= 0xDC00, lo <= 0xDFFF {
                            let scalar = 0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00)
                            if let u = UnicodeScalar(scalar) { out.unicodeScalars.append(u) }
                            consumed = 12
                        } else if let u = UnicodeScalar(v) { out.unicodeScalars.append(u) } else { out.append("\u{FFFD}") }
                    } else { out.append("\\u") }
                }
            case "U":
                let afterBigU = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                let hex = s[afterBigU...].prefix(8)
                if hex.count == 8, let v = UInt32(hex, radix: 16), let u = UnicodeScalar(v) { out.unicodeScalars.append(u); consumed = 10 } else { out.append("\\U") }
            default:
                out.append("\\")
                out.append(n)
            }
            i = s.index(i, offsetBy: consumed, limitedBy: s.endIndex) ?? s.endIndex
        }
        return out
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard !s.contains("\n") || s.count < 2000 else { return nil }
        let n = s.matches(of: /\\(n|t|r|"|u[0-9A-Fa-f]{4}|x[0-9A-Fa-f]{2})/).count
        return n >= 2 && !s.hasPrefix("{") ? DetectionScore(min(0.45 + Double(n) * 0.05, 0.7), "Backslash escapes", options: ["mode": .string("unescape")]) : nil
    }
}
