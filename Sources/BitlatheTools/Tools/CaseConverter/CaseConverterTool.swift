import Foundation
import BitlatheCore

public struct CaseConverterTool: DevTool {
    public static let id = "text.case"
    public static let name = "Case Converter"
    public static let summary = "camelCase, PascalCase, snake_case, kebab-case, CONSTANT_CASE, Title, Sentence, dot.case and path/case at once"
    public static let category = ToolCategory.convert
    public static let symbol = "textformat"
    public static let keywords = ["case", "camel", "pascal", "snake", "kebab", "constant", "title", "sentence", "upper", "lower", "dot", "path", "slug"]
    public static let samples = [ToolSample("Identifier", "userProfileImageURL"), ToolSample("Sentence", "The quick brown fox jumps over the lazy dog")]
    public static let optionFields: [OptionField] = [
        .picker("target", "Show", [.init("all", "All variants"), .init("camel", "camelCase"), .init("pascal", "PascalCase"), .init("snake", "snake_case"), .init("kebab", "kebab-case"),
                                   .init("constant", "CONSTANT_CASE"), .init("title", "Title Case"), .init("sentence", "Sentence case"), .init("dot", "dot.case"), .init("path", "path/case"),
                                   .init("upper", "UPPER CASE"), .init("lower", "lower case"), .init("header", "Header-Case"), .init("swap", "sWAP cASE"), .init("slug", "slug")], default: "all"),
        .toggle("perLine", "Convert each line", default: true),
    ]
    public struct Options: ToolOptions {
        public var target = "all"
        public var perLine = true
        public init() {}
    }
    public init() {}

    static let variants: [(String, String)] = [
        ("camel", "camelCase"), ("pascal", "PascalCase"), ("snake", "snake_case"), ("kebab", "kebab-case"), ("constant", "CONSTANT_CASE"),
        ("title", "Title Case"), ("sentence", "Sentence case"), ("dot", "dot.case"), ("path", "path/case"), ("header", "Header-Case"),
        ("upper", "UPPER CASE"), ("lower", "lower case"), ("swap", "sWAP cASE"), ("slug", "slug"),
    ]

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let lines = options.perLine ? text.components(separatedBy: "\n") : [text]
        func apply(_ v: String) -> String { lines.map { Self.convert($0, to: v) }.joined(separator: "\n") }
        if options.target == "all" {
            let facets = Self.variants.map { OutputFacet($0.1, text: apply($0.0)) }
            let listing = Self.variants.map { "\($0.1.padding(toLength: 16, withPad: " ", startingAt: 0)) \(apply($0.0))" }.joined(separator: "\n")
            return ToolOutput(text: listing, facets: facets, metadata: [MetaRow("Words", "\(Self.words(text).count)")])
        }
        return ToolOutput(text: apply(options.target))
    }

    static func words(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            if c.isLetter || c.isNumber {
                if !current.isEmpty, let last = current.last {
                    let boundary = (last.isLowercase && c.isUppercase)
                        || (last.isNumber != c.isNumber && !(last.isNumber && c.isNumber))
                        || (last.isUppercase && c.isUppercase && i + 1 < chars.count && chars[i + 1].isLowercase)
                    if boundary { out.append(current); current = "" }
                }
                current.append(c)
            } else if !current.isEmpty { out.append(current); current = "" }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static func convert(_ s: String, to target: String) -> String {
        let w = words(s)
        let lower = w.map { $0.lowercased() }
        switch target {
        case "camel": return lower.enumerated().map { $0.offset == 0 ? $0.element : $0.element.capitalizedFirst() }.joined()
        case "pascal": return lower.map { $0.capitalizedFirst() }.joined()
        case "snake": return lower.joined(separator: "_")
        case "kebab", "slug": return lower.joined(separator: "-")
        case "constant": return lower.map { $0.uppercased() }.joined(separator: "_")
        case "title": return lower.map { $0.capitalizedFirst() }.joined(separator: " ")
        case "sentence": return lower.enumerated().map { $0.offset == 0 ? $0.element.capitalizedFirst() : $0.element }.joined(separator: " ")
        case "dot": return lower.joined(separator: ".")
        case "path": return lower.joined(separator: "/")
        case "header": return lower.map { $0.capitalizedFirst() }.joined(separator: "-")
        case "upper": return s.uppercased()
        case "lower": return s.lowercased()
        case "swap": return String(s.map { $0.isUppercase ? Character($0.lowercased()) : Character($0.uppercased()) })
        default: return s
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isSingleLine(s), s.count < 80, s.range(of: "^[A-Za-z][A-Za-z0-9]*$", options: .regularExpression) != nil, words(s).count >= 2 else { return nil }
        return DetectionScore(0.4, "Identifier → other cases")
    }
}
