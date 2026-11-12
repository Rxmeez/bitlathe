import Foundation
import BitlatheCore

public struct URLEncodeTool: DevTool {
    public static let id = "url.encode"
    public static let name = "URL Encode / Decode"
    public static let summary = "Percent-encode a component or a full URL, and decode back"
    public static let category = ToolCategory.encode
    public static let symbol = "link"
    public static let keywords = ["url", "percent", "encode", "decode", "uri", "component", "escape"]
    public static let samples = [ToolSample("Encode", "name=Ada Lovelace&q=1+1=2 & café"), ToolSample("Decode", "https://example.com/search?q=caf%C3%A9%20au%20lait&x=%2Fpath", options: ["mode": .string("decode")])]
    public static let optionFields: [OptionField] = [
        .encodeDecode,
        .segmented("scope", "Scope", [.init("component", "Component"), .init("full", "Full URL"), .init("form", "Form (+ for space)"), .init("all", "All characters")], default: "component"),
        .toggle("perLine", "Each line", default: true),
    ]
    public struct Options: ToolOptions {
        public var mode = "encode"
        public var scope = "component"
        public var perLine = true
        public init() {}
    }
    public init() {}

    static let componentAllowed: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-_.~")
        return s
    }()
    static let fullURLAllowed: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-_.~:/?#[]@!$&'()*+,;=%")
        return s
    }()

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let pieces = options.perLine ? text.components(separatedBy: "\n") : [text]
        let out = try pieces.map { piece -> String in
            if options.mode == "encode" {
                switch options.scope {
                case "full": return piece.addingPercentEncoding(withAllowedCharacters: Self.fullURLAllowed) ?? piece
                case "form": return (piece.addingPercentEncoding(withAllowedCharacters: Self.componentAllowed) ?? piece).replacingOccurrences(of: "%20", with: "+")
                case "all": return piece.utf8.map { String(format: "%%%02X", $0) }.joined()
                default: return piece.addingPercentEncoding(withAllowedCharacters: Self.componentAllowed) ?? piece
                }
            }
            let source = options.scope == "form" ? piece.replacingOccurrences(of: "+", with: " ") : piece
            guard let d = source.removingPercentEncoding else {
                // Find the first bad escape for a helpful error.
                if let r = source.range(of: "%(?![0-9A-Fa-f]{2})", options: .regularExpression) {
                    let off = source.distance(from: source.startIndex, to: r.lowerBound)
                    throw ToolError("Invalid percent escape at offset \(off)", hint: "% must be followed by two hex digits")
                }
                throw ToolError("Invalid percent-encoded UTF-8")
            }
            return d
        }.joined(separator: "\n")
        var meta: [MetaRow] = []
        if options.mode == "decode", let url = URL(string: text.trimmed()), let host = url.host { meta.append(MetaRow("Host", host)) }
        return ToolOutput(text: out, metadata: meta)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        let n = s.matches(of: /%[0-9A-Fa-f]{2}/).count
        if n >= 2 { return DetectionScore(min(0.5 + Double(n) * 0.05, 0.85), "Percent-encoded text", options: ["mode": .string("decode")]) }
        return nil
    }
}
