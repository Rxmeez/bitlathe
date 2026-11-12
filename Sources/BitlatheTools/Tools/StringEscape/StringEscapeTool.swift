import Foundation
import BitlatheCore

public struct StringEscapeTool: DevTool {
    public static let id = "string.escape"
    public static let name = "String Escaper"
    public static let summary = "Escape text as a literal for JSON, Swift, JavaScript, Python, Go, SQL, shell, regex, CSV, C, Java or HTML attributes"
    public static let category = ToolCategory.encode
    public static let symbol = "quote.closing"
    public static let keywords = ["escape", "unescape", "string", "literal", "quote", "json", "swift", "javascript", "python", "go", "sql", "shell", "bash", "regex", "csv"]
    public static let samples = [ToolSample("Escape", "She said \"hi\" — it's a C:\\path\nwith a newline, a $var and a *.star?"),
                                 ToolSample("Unescape JSON", #""Line 1\nLine \"2\" \u00e9""#, options: ["mode": .string("unescape"), "language": .string("json")])]
    public static let optionFields: [OptionField] = [
        .mode([.init("escape", "Escape"), .init("unescape", "Unescape")], default: "escape"),
        .picker("language", "Target", [.init("json", "JSON"), .init("swift", "Swift"), .init("javascript", "JavaScript"), .init("python", "Python"), .init("go", "Go"), .init("java", "Java / Kotlin / C#"),
                                       .init("c", "C / C++"), .init("sql", "SQL"), .init("shell", "Shell (POSIX)"), .init("powershell", "PowerShell"), .init("regex", "Regex"), .init("csv", "CSV"), .init("html", "HTML attribute"), .init("xml", "XML"), .init("yaml", "YAML"), .init("php", "PHP")], default: "json"),
        .toggle("quotes", "Include quotes", default: true),
    ]
    public struct Options: ToolOptions {
        public var mode = "escape"
        public var language = "json"
        public var quotes = true
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.isEmpty else { throw ToolError.emptyInput }
        if options.mode == "unescape" {
            return ToolOutput(text: try Self.unescape(text, language: options.language))
        }
        let out = Self.escape(text, language: options.language, quotes: options.quotes)
        let lang: CodeLanguage = switch options.language {
        case "json": .json
        case "swift": .swift
        case "javascript": .javascript
        case "python": .python
        case "go": .go
        case "java": .java
        case "sql": .sql
        case "shell": .shell
        case "regex": .regex
        case "csv": .csv
        case "html", "xml": .html
        case "yaml": .yaml
        case "php": .php
        default: .plain
        }
        let allFacets = ["json", "swift", "javascript", "python", "go", "sql", "shell", "regex", "csv", "html"].map { OutputFacet($0, text: Self.escape(text, language: $0, quotes: options.quotes)) }
        return ToolOutput(text: out, language: lang, facets: allFacets)
    }

    static func cStyle(_ s: String, quote: Character, unicode: Bool = true, swiftStyle: Bool = false) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\0": out += "\\0"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u == quote.unicodeScalars.first! { out += "\\" + String(quote) }   // swiftlint:disable:this force_unwrapping
                else if u.value < 0x20 || u.value == 0x7F { out += swiftStyle ? String(format: "\\u{%X}", u.value) : String(format: "\\u%04x", u.value) }
                else { out.unicodeScalars.append(u) }
            }
        }
        return out
    }

    static func escape(_ s: String, language: String, quotes: Bool) -> String {
        func wrap(_ body: String, _ q: String) -> String { quotes ? q + body + q : body }
        switch language {
        case "json": return quotes ? JSONSerializer.quoted(s) : String(JSONSerializer.quoted(s).dropFirst().dropLast())
        case "swift": return wrap(cStyle(s, quote: "\"", swiftStyle: true), "\"")
        case "javascript":
            let body = cStyle(s, quote: "'").replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            return wrap(body, "'")
        case "python":
            let body = cStyle(s, quote: "'")
            return wrap(body, "'")
        case "go": return wrap(cStyle(s, quote: "\""), "\"")
        case "java", "c": return wrap(cStyle(s, quote: "\""), "\"")
        case "php": return wrap(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'"), "'")
        case "sql": return wrap(s.replacingOccurrences(of: "'", with: "''"), "'")
        case "shell":
            if s.range(of: "^[A-Za-z0-9_./:=@%+,-]+$", options: .regularExpression) != nil { return s }
            return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
        case "powershell": return wrap(s.replacingOccurrences(of: "'", with: "''"), "'")
        case "regex": return NSRegularExpression.escapedPattern(for: s)
        case "csv":
            if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") { return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            return s
        case "html": return wrap(s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "'", with: "&#39;"), "\"")
        case "xml": return s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
        case "yaml": return JSONSerializer.quoted(s)
        default: return s
        }
    }

    static func unescape(_ s: String, language: String) throws -> String {
        var t = s.trimmed()
        switch language {
        case "json", "yaml":
            if !t.hasPrefix("\"") { t = "\"" + t + "\"" }
            guard case .string(let v) = try JSONParser.parse(t) else { throw ToolError("Not a JSON string") }
            return v
        case "sql", "powershell":
            if t.hasPrefix("'"), t.hasSuffix("'"), t.count >= 2 { t = String(t.dropFirst().dropLast()) }
            return t.replacingOccurrences(of: "''", with: "'")
        case "shell":
            if t.hasPrefix("'"), t.hasSuffix("'") { return String(t.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'") }
            if t.hasPrefix("\""), t.hasSuffix("\"") { return BackslashTool.unescape(String(t.dropFirst().dropLast())) }
            return BackslashTool.unescape(t)
        case "csv":
            if t.hasPrefix("\""), t.hasSuffix("\"") { return String(t.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"") }
            return t
        case "html", "xml": return HTMLEntityTable.decode(t).0
        case "regex":
            return t.replacingOccurrences(of: "\\\\([.*+?^${}()|\\[\\]\\\\/-])", with: "$1", options: .regularExpression)
        case "php":
            if t.hasPrefix("'"), t.hasSuffix("'") { return String(t.dropFirst().dropLast()).replacingOccurrences(of: "\\'", with: "'").replacingOccurrences(of: "\\\\", with: "\\") }
            if t.hasPrefix("\""), t.hasSuffix("\"") { t = String(t.dropFirst().dropLast()) }
            return BackslashTool.unescape(t)
        default:
            for q in ["\"\"\"", "\"", "'", "`"] where t.hasPrefix(q) && t.hasSuffix(q) && t.count >= 2 * q.count { t = String(t.dropFirst(q.count).dropLast(q.count)); break }
            return BackslashTool.unescape(t)
        }
    }
}
