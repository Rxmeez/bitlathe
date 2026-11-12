import Foundation
import BitlatheCore

public struct QuotedPrintableTool: DevTool {
    public static let id = "quoted.printable"
    public static let name = "Quoted-Printable"
    public static let summary = "Encode and decode MIME quoted-printable text (and =?UTF-8?Q?…?= headers)"
    public static let category = ToolCategory.encode
    public static let symbol = "envelope"
    public static let keywords = ["quoted-printable", "mime", "email", "encode", "decode", "=?utf-8?q?"]
    public static let samples = [ToolSample("Encode", "Grüße aus München — a line that is long enough to need a soft line break somewhere around here."),
                                 ToolSample("Decode", "Gr=C3=BC=C3=9Fe aus M=C3=BCnchen =E2=80=94 soft=\nline break", options: ["mode": .string("decode")])]
    public static let optionFields: [OptionField] = [.encodeDecode]
    public struct Options: ToolOptions {
        public var mode = "encode"
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.isEmpty else { throw ToolError.emptyInput }
        if options.mode == "encode" {
            var out = ""
            var lineLen = 0
            func emit(_ s: String) {
                if lineLen + s.count > 75 { out += "=\r\n"; lineLen = 0 }
                out += s
                lineLen += s.count
            }
            let bytes = Array(text.utf8)
            for (i, b) in bytes.enumerated() {
                if b == 0x0D, i + 1 < bytes.count, bytes[i + 1] == 0x0A { continue }
                if b == 0x0A { out += "\r\n"; lineLen = 0; continue }
                let isLast = i == bytes.count - 1 || bytes[i + 1] == 0x0A || (bytes[i + 1] == 0x0D)
                if (b >= 33 && b <= 126 && b != 61) || ((b == 32 || b == 9) && !isLast) { emit(String(UnicodeScalar(b))) }
                else { emit(String(format: "=%02X", b)) }
            }
            return ToolOutput(text: out.replacingOccurrences(of: "\r\n", with: "\n"))
        }
        var s = text
        var ignored = 0
        // Encoded-word headers
        s = UnicodeEscapeTool.replace(s, pattern: "=\\?([^?]+)\\?[Qq]\\?([^?]*)\\?=", count: &ignored) { m in
            guard let inner = m.captures("=\\?([^?]+)\\?[Qq]\\?([^?]*)\\?=") else { return nil }
            return Self.decodeQP(inner[2].replacingOccurrences(of: "_", with: " "))
        }
        s = UnicodeEscapeTool.replace(s, pattern: "=\\?([^?]+)\\?[Bb]\\?([^?]*)\\?=", count: &ignored) { m in
            guard let inner = m.captures("=\\?([^?]+)\\?[Bb]\\?([^?]*)\\?="), let d = Data(base64Encoded: inner[2]) else { return nil }
            return String(data: d, encoding: .utf8)
        }
        return ToolOutput(text: Self.decodeQP(s))
    }

    static func decodeQP(_ s: String) -> String {
        var bytes: [UInt8] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "=" {
                let next = s.index(after: i)
                if next < s.endIndex, s[next] == "\n" || s[next] == "\r\n" { i = s.index(after: next); continue }
                if next < s.endIndex, s[next] == "\r" { i = s.index(after: next); if i < s.endIndex, s[i] == "\n" { i = s.index(after: i) }; continue }
                if let end = s.index(i, offsetBy: 3, limitedBy: s.endIndex), let b = UInt8(s[next..<end], radix: 16) { bytes.append(b); i = end; continue }
            }
            bytes.append(contentsOf: Array(String(c).utf8))
            i = s.index(after: i)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.contains("=?UTF-8?Q?") || s.contains("=?utf-8?q?") || s.contains("=?UTF-8?B?") { return DetectionScore(0.9, "MIME encoded-word", options: ["mode": .string("decode")]) }
        let n = s.matches(of: /=[0-9A-F]{2}/).count
        return n >= 3 && !s.contains("%") ? DetectionScore(0.6, "Quoted-printable", options: ["mode": .string("decode")]) : nil
    }
}
