import AppKit
import BitlatheCore

/// Regex-based syntax highlighter. Fast enough for the outputs tools produce; skipped above 512 KB.
public struct Highlighter: Sendable {
    public enum Token: Sendable { case keyword, string, number, comment, key, punctuation, tag, attribute }

    struct Rule: Sendable {
        let regex: NSRegularExpression
        let token: Token
        let group: Int
    }

    public static let sizeLimit = 512 * 1024

    nonisolated(unsafe) private static var cache: [CodeLanguage: [Rule]] = [:]
    private static let lock = NSLock()

    static func rules(for language: CodeLanguage) -> [Rule] {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[language] { return r }
        let r = buildRules(language)
        cache[language] = r
        return r
    }

    private static func rule(_ pattern: String, _ token: Token, group: Int = 0, options: NSRegularExpression.Options = []) -> Rule? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        return Rule(regex: re, token: token, group: group)
    }

    private static let cKeywords = "\\b(?:abstract|as|async|await|break|case|catch|class|const|continue|def|default|defer|do|else|elif|enum|export|extends|extension|false|final|finally|fn|for|from|func|function|guard|if|impl|import|in|init|interface|internal|is|let|match|mut|new|nil|None|not|null|or|and|override|package|private|protected|protocol|pub|public|return|self|Self|static|struct|super|switch|this|throw|throws|trait|true|try|type|typealias|undefined|use|var|val|void|where|while|yield|int|string|bool|float|double|String|Int|Bool|Double)\\b"

    private static func buildRules(_ language: CodeLanguage) -> [Rule] {
        var out: [Rule?] = []
        switch language {
        case .json:
            out = [
                rule("\"(?:[^\"\\\\]|\\\\.)*\"\\s*(?=:)", .key),
                rule("\"(?:[^\"\\\\]|\\\\.)*\"", .string),
                rule("-?\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", .number),
                rule("\\b(?:true|false|null)\\b", .keyword),
                rule("[{}\\[\\]:,]", .punctuation),
                rule("//[^\\n]*|/\\*[\\s\\S]*?\\*/", .comment),
            ]
        case .yaml:
            out = [
                rule("^\\s*-?\\s*[A-Za-z0-9_.\\-\"' ]+?(?=\\s*:(?:\\s|$))", .key, options: .anchorsMatchLines),
                rule("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^']|'')*'", .string),
                rule("\\b-?\\d+(?:\\.\\d+)?\\b", .number),
                rule("\\b(?:true|false|null|yes|no|~)\\b", .keyword),
                rule("#[^\\n]*", .comment),
                rule("^---|^\\.\\.\\.", .punctuation, options: .anchorsMatchLines),
            ]
        case .toml:
            out = [
                rule("^\\s*\\[\\[?[^\\]]+\\]\\]?", .tag, options: .anchorsMatchLines),
                rule("^\\s*[A-Za-z0-9_.\\-\"']+(?=\\s*=)", .key, options: .anchorsMatchLines),
                rule("\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"(?:[^\"\\\\]|\\\\.)*\"|'[^']*'", .string),
                rule("\\b-?\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b|\\d{4}-\\d{2}-\\d{2}[T ]?[\\d:.Z+-]*", .number),
                rule("\\b(?:true|false|inf|nan)\\b", .keyword),
                rule("#[^\\n]*", .comment),
            ]
        case .xml, .html:
            out = [
                rule("<!--[\\s\\S]*?-->", .comment),
                rule("<!\\[CDATA\\[[\\s\\S]*?\\]\\]>", .string),
                rule("</?[A-Za-z][A-Za-z0-9:._-]*|/?>|<\\?|\\?>|<!DOCTYPE", .tag),
                rule("\\b[A-Za-z_:][A-Za-z0-9:._-]*(?==)", .attribute),
                rule("\"[^\"]*\"|'[^']*'", .string),
                rule("&[a-zA-Z#0-9]+;", .number),
            ]
        case .css:
            out = [
                rule("/\\*[\\s\\S]*?\\*/", .comment),
                rule("[.#]?[A-Za-z_-][\\w-]*(?=[^{}]*\\{)", .tag),
                rule("[A-Za-z-]+(?=\\s*:)", .key),
                rule("\"[^\"]*\"|'[^']*'", .string),
                rule("#[0-9a-fA-F]{3,8}\\b|-?\\b\\d+(?:\\.\\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg|pt)?\\b", .number),
                rule("!important|@[a-z-]+", .keyword),
                rule("[{};:]", .punctuation),
            ]
        case .javascript, .typescript, .swift, .go, .rust, .kotlin, .java, .csharp, .php, .python, .ruby:
            out = [
                rule("//[^\\n]*|/\\*[\\s\\S]*?\\*/|#(?![\\[{])[^\\n]*", .comment),
                rule("\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'|`(?:[^`\\\\]|\\\\.)*`|\"\"\"[\\s\\S]*?\"\"\"", .string),
                rule(cKeywords, .keyword),
                rule("\\b0x[0-9a-fA-F_]+\\b|\\b\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?[fFLuUn]?\\b", .number),
                rule("@[A-Za-z_]\\w*|\\b[A-Z][A-Za-z0-9_]*\\b", .tag),
                rule("[{}()\\[\\];,]", .punctuation),
            ]
        case .sql:
            out = [
                rule("--[^\\n]*|/\\*[\\s\\S]*?\\*/", .comment),
                rule("'(?:[^']|'')*'", .string),
                rule("\\b(?i:select|from|where|insert|into|values|update|set|delete|create|table|drop|alter|add|column|index|view|join|inner|left|right|full|outer|on|as|and|or|not|null|is|in|like|between|group|by|order|having|limit|offset|union|all|distinct|case|when|then|else|end|exists|primary|key|foreign|references|default|constraint|unique|check|with|over|partition|desc|asc|returning|begin|commit|rollback|if|int|integer|varchar|text|boolean|timestamp|date|serial|bigint|decimal|numeric|true|false|cast|count|sum|avg|min|max|coalesce)\\b", .keyword),
                rule("\\b\\d+(?:\\.\\d+)?\\b", .number),
                rule("[();,]", .punctuation),
            ]
        case .markdown:
            out = [
                rule("^#{1,6} .*$", .keyword, options: .anchorsMatchLines),
                rule("\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__", .tag),
                rule("`[^`\\n]+`|```[\\s\\S]*?```", .string),
                rule("\\[[^\\]]*\\]\\([^)]*\\)", .key),
                rule("^\\s*(?:[-*+]|\\d+\\.) ", .punctuation, options: .anchorsMatchLines),
                rule("^>.*$", .comment, options: .anchorsMatchLines),
            ]
        case .graphql:
            out = [
                rule("#[^\\n]*", .comment),
                rule("\"(?:[^\"\\\\]|\\\\.)*\"|\"\"\"[\\s\\S]*?\"\"\"", .string),
                rule("\\b(?:query|mutation|subscription|fragment|on|type|input|enum|interface|union|scalar|schema|extend|directive|implements|true|false|null)\\b", .keyword),
                rule("\\$[A-Za-z_]\\w*|@[A-Za-z_]\\w*", .attribute),
                rule("\\b[A-Z][A-Za-z0-9_]*\\b", .tag),
                rule("\\b\\d+(?:\\.\\d+)?\\b", .number),
                rule("[{}()\\[\\]:!]", .punctuation),
            ]
        case .shell:
            out = [
                rule("#[^\\n]*", .comment),
                rule("\"(?:[^\"\\\\]|\\\\.)*\"|'[^']*'", .string),
                rule("(?<=\\s|^)-{1,2}[A-Za-z][\\w-]*", .attribute, options: .anchorsMatchLines),
                rule("\\$\\{?[A-Za-z_]\\w*\\}?", .key),
                rule("^\\s*[a-z][\\w.-]*", .keyword, options: .anchorsMatchLines),
                rule("\\\\$", .punctuation, options: .anchorsMatchLines),
            ]
        case .dotenv, .properties:
            out = [
                rule("#[^\\n]*|^;[^\\n]*", .comment, options: .anchorsMatchLines),
                rule("^\\s*(?:export\\s+)?[A-Za-z_][A-Za-z0-9_.]*(?=\\s*[=:])", .key, options: .anchorsMatchLines),
                rule("\"(?:[^\"\\\\]|\\\\.)*\"|'[^']*'", .string),
                rule("[=:]", .punctuation),
            ]
        case .csv:
            out = [
                rule("\"(?:[^\"]|\"\")*\"", .string),
                rule("(?<=^|,|;|\\t)-?\\d+(?:\\.\\d+)?(?=,|;|\\t|$)", .number, options: .anchorsMatchLines),
                rule("[,;\\t]", .punctuation),
            ]
        case .diff:
            out = [
                rule("^\\+.*$", .string, options: .anchorsMatchLines),
                rule("^-.*$", .tag, options: .anchorsMatchLines),
                rule("^@@.*@@.*$", .key, options: .anchorsMatchLines),
                rule("^(?:diff|index|---|\\+\\+\\+) .*$", .comment, options: .anchorsMatchLines),
            ]
        case .hex:
            out = [
                rule("^[0-9a-fA-F]{8}", .comment, options: .anchorsMatchLines),
                rule("\\|.*\\|$", .string, options: .anchorsMatchLines),
            ]
        case .regex:
            out = [
                rule("\\\\[dDwWsSbB.]|\\\\[0-9]", .keyword),
                rule("\\[(?:[^\\]\\\\]|\\\\.)*\\]", .string),
                rule("[()|]", .tag),
                rule("[*+?]\\??|\\{\\d+(?:,\\d*)?\\}", .number),
                rule("\\^|\\$", .attribute),
            ]
        case .plain:
            out = []
        }
        return out.compactMap { $0 }
    }

    /// Applies colours to the attributed string in place (foreground colour only).
    public static func highlight(_ storage: NSMutableAttributedString, language: CodeLanguage, colors: EditorTheme.Colors, range: NSRange? = nil) {
        let full = range ?? NSRange(location: 0, length: storage.length)
        // Above the size limit (or for plain text) one base-colour run is all the work we do: no per-token
        // attribute runs, no regex passes, no `storage.string` copy. This keeps a 10 MB output instant.
        if storage.length > sizeLimit || language == .plain {
            storage.addAttribute(.foregroundColor, value: NSColor(hex: colors.text), range: full)
            return
        }
        storage.removeAttribute(.foregroundColor, range: full)
        storage.addAttribute(.foregroundColor, value: NSColor(hex: colors.text), range: full)
        let string = storage.string
        let rules = rules(for: language)
        // Paint a token map first (later rules win, as before), then apply colour runs in ascending order.
        // Calling addAttribute once per regex match in match order is quadratic in the number of attribute runs.
        var map = [UInt8](repeating: 0, count: full.length)
        for (index, r) in rules.enumerated() {
            let tag = UInt8(index + 1)
            r.regex.enumerateMatches(in: string, options: [], range: full) { m, _, _ in
                guard let m else { return }
                let mr = m.range(at: r.group)
                guard mr.location != NSNotFound, mr.length > 0 else { return }
                let lo = mr.location - full.location
                for k in lo..<min(lo + mr.length, map.count) { map[k] = tag }
            }
        }
        let colorsByTag = rules.map { NSColor(hex: Self.color(for: $0.token, colors)) }
        var runStart = 0
        var current = map.first ?? 0
        for k in 1...max(map.count, 1) {
            let tag = k < map.count ? map[k] : UInt8.max
            if tag != current {
                if current != 0, runStart < map.count {
                    storage.addAttribute(.foregroundColor, value: colorsByTag[Int(current) - 1], range: NSRange(location: full.location + runStart, length: k - runStart))
                }
                runStart = k
                current = tag
            }
        }
    }

    static func color(for token: Token, _ c: EditorTheme.Colors) -> UInt32 {
        switch token {
        case .keyword: c.keyword
        case .string: c.string
        case .number: c.number
        case .comment: c.comment
        case .key: c.key
        case .punctuation: c.punctuation
        case .tag: c.tag
        case .attribute: c.attribute
        }
    }
}
