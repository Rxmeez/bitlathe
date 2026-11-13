import Foundation
import BitlatheCore

public struct EnvInspectTool: DevTool {
    public static let id = "env.inspect"
    public static let name = ".env Inspector"
    public static let summary = "Parse and validate .env files, flag duplicates, mask secrets, and convert to JSON, Docker, shell or Kubernetes"
    public static let category = ToolCategory.inspect
    public static let symbol = "key.viewfinder"
    public static let keywords = ["env", "dotenv", "environment", "variables", "secrets", "docker", "kubernetes", "secret", "export", "config"]
    public static let io = ToolIO.text(.dotenv, .json)
    public static let samples = [ToolSample("Sample .env", "# Database\nDATABASE_URL=postgres://user:pass@localhost:5432/app\nAPI_KEY=sk_live_51Hxxxxxxxxxxxxxxxxxxxxxx\nDEBUG=true\nPORT=3000\nMESSAGE=\"Hello ${USER}\"\nEMPTY=\nPORT=3001\nbad key=1\nexport NODE_ENV=production")]
    public static let optionFields: [OptionField] = [
        .picker("output", "Output", [.init("json", "JSON"), .init("docker", "docker run --env"), .init("compose", "Compose environment:"), .init("shell", "export …"), .init("k8s", "Kubernetes Secret"), .init("k8sconfig", "Kubernetes ConfigMap"), .init("dotenv", "Normalised .env"), .init("github", "GitHub Actions env")], default: "json"),
        .toggle("mask", "Mask secrets", default: true),
        .toggle("expand", "Expand ${VAR} references", default: true),
        .text("secretName", "Secret name", placeholder: "app-secrets", default: "app-secrets", visibleWhen: ("output", ["k8s", "k8sconfig"])),
    ]
    public struct Options: ToolOptions {
        public var output = "json"
        public var mask = true
        public var expand = true
        public var secretName = "app-secrets"
        public init() {}
    }
    public init() {}

    public struct Entry: Sendable, Equatable {
        public var key: String
        public var value: String
        public var line: Int
        public var quoted: Bool
        public var isSecret: Bool
        public var comment: String?
        /// Single-quoted values are literal: no `$VAR` expansion.
        public var literal = false
    }

    static let secretPattern = "(?i)(secret|password|passwd|pwd|token|api[_-]?key|private[_-]?key|auth|credential|access[_-]?key|client[_-]?secret|signing|salt|dsn|connection[_-]?string|_url$|^url$)"

    public static func parse(_ text: String) -> (entries: [Entry], warnings: [(line: Int, message: String)]) {
        var entries: [Entry] = []
        var warnings: [(Int, String)] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            var line = lines[i].removingSuffix("\r")
            let lineNo = i + 1
            i += 1
            let trimmed = line.trimmed()
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("export ") { line = String(trimmed.dropFirst(7)) }
            guard let eq = line.firstIndex(of: "=") else { warnings.append((lineNo, "No '=' found: \"\(trimmed.prefix(40))\"")); continue }
            let key = line[..<eq].trimmed()
            var rawValue = String(line[line.index(after: eq)...])
            if key.isEmpty { warnings.append((lineNo, "Empty key")); continue }
            if key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) == nil { warnings.append((lineNo, "Invalid key \"\(key)\" (use letters, digits and _)")) }
            else if key != key.uppercased(), key.range(of: "[a-z]", options: .regularExpression) != nil { warnings.append((lineNo, "Key \"\(key)\" is not UPPER_CASE")) }
            var value = rawValue.trimmed()
            var quoted = false
            var literal = false
            var comment: String?
            if value.hasPrefix("\"") {
                // Multi-line double-quoted value
                var body = String(value.dropFirst())
                while !Self.endsQuoted(body, "\""), i < lines.count { body += "\n" + lines[i].removingSuffix("\r"); i += 1 }
                if let end = Self.closingQuote(body, "\"") {
                    let rest = body[body.index(after: end)...].trimmed()
                    if rest.hasPrefix("#") { comment = String(rest.dropFirst()).trimmed() } else if !rest.isEmpty { warnings.append((lineNo, "Unexpected text after closing quote")) }
                    body = String(body[..<end])
                } else { warnings.append((lineNo, "Unterminated double quote")) }
                value = BackslashTool.unescape(body)
                quoted = true
            } else if value.hasPrefix("'") {
                var body = String(value.dropFirst())
                while !body.contains("'"), i < lines.count { body += "\n" + lines[i].removingSuffix("\r"); i += 1 }
                if let end = body.firstIndex(of: "'") {
                    let rest = body[body.index(after: end)...].trimmed()
                    if rest.hasPrefix("#") { comment = String(rest.dropFirst()).trimmed() }
                    body = String(body[..<end])
                } else { warnings.append((lineNo, "Unterminated single quote")) }
                value = body
                quoted = true
                literal = true
            } else {
                if let hash = value.range(of: " #") { comment = String(value[hash.upperBound...]).trimmed(); value = String(value[..<hash.lowerBound]).trimmed() }
                if value.contains(" "), !value.hasPrefix("`") { warnings.append((lineNo, "Unquoted value with spaces for \(key); quote it")) }
            }
            rawValue = ""
            let isSecret = key.range(of: secretPattern, options: .regularExpression) != nil || value.range(of: "^(sk|pk|rk|ghp|gho|xox[abp]|AKIA|AIza|ya29)[_-]?[A-Za-z0-9]{8,}", options: .regularExpression) != nil
                || value.range(of: "://[^/:@]+:[^@/]+@", options: .regularExpression) != nil
            if let dup = entries.firstIndex(where: { $0.key == key }) {
                warnings.append((lineNo, "Duplicate key \(key) (first defined on line \(entries[dup].line)); last value wins"))
                entries.remove(at: dup)
            }
            if value.isEmpty { warnings.append((lineNo, "\(key) is empty")) }
            entries.append(Entry(key: key, value: value, line: lineNo, quoted: quoted, isSecret: isSecret, comment: comment, literal: literal))
        }
        return (entries, warnings)
    }

    static func endsQuoted(_ s: String, _ q: Character) -> Bool { closingQuote(s, q) != nil }
    static func closingQuote(_ s: String, _ q: Character) -> String.Index? {
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\\" { i = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex; continue }
            if s[i] == q { return i }
            i = s.index(after: i)
        }
        return nil
    }

    public static func expand(_ entries: [Entry]) -> [Entry] {
        var map: [String: String] = [:]
        var out = entries
        for (idx, e) in entries.enumerated() {
            var v = e.value
            for _ in 0..<5 {
                let before = v
                v = v.replacingOccurrences(of: "\\$\\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\\}", with: "$1", options: .regularExpression)
                _ = before
                break
            }
            // manual expansion (regex replacement cannot look up values)
            var result = ""
            var i = e.value.startIndex
            let s = e.value
            while i < s.endIndex {
                if s[i] == "$", s.index(after: i) < s.endIndex {
                    let n = s.index(after: i)
                    if s[n] == "{", let close = s[n...].firstIndex(of: "}") {
                        let inner = String(s[s.index(after: n)..<close])
                        let parts = inner.components(separatedBy: ":-")
                        result += map[parts[0]] ?? (parts.count > 1 ? parts[1] : "")
                        i = s.index(after: close)
                        continue
                    }
                    let name = String(s[n...].prefix { $0.isLetter || $0.isNumber || $0 == "_" })
                    if !name.isEmpty, let val = map[name] { result += val; i = s.index(n, offsetBy: name.count); continue }
                }
                result.append(s[i])
                i = s.index(after: i)
            }
            out[idx].value = e.literal ? e.value : result
            map[e.key] = out[idx].value
        }
        return out
    }

    public static func mask(_ v: String) -> String {
        guard v.count > 8 else { return String(repeating: "•", count: max(v.count, 4)) }
        return v.prefix(3) + String(repeating: "•", count: min(v.count - 6, 12)) + v.suffix(3)
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        var (entries, warns) = Self.parse(text)
        if options.expand { entries = Self.expand(entries) }
        let display = entries.map { e in options.mask && e.isSecret ? Entry(key: e.key, value: Self.mask(e.value), line: e.line, quoted: e.quoted, isSecret: true, comment: e.comment, literal: e.literal) : e }
        var out = ""
        var lang: CodeLanguage = .plain
        let name = options.secretName.isEmpty ? "app-secrets" : options.secretName
        switch options.output {
        case "docker":
            out = "docker run \\\n" + display.map { "  --env \($0.key)=\(CurlParser.shellQuote($0.value))" }.joined(separator: " \\\n") + " \\\n  image:tag"
            lang = .shell
        case "compose":
            out = "environment:\n" + display.map { "  \($0.key): \(JSONSerializer.quoted($0.value))" }.joined(separator: "\n")
            lang = .yaml
        case "shell":
            out = display.map { "export \($0.key)=\(CurlParser.shellQuote($0.value))" }.joined(separator: "\n")
            lang = .shell
        case "k8s":
            out = "apiVersion: v1\nkind: Secret\nmetadata:\n  name: \(name)\ntype: Opaque\ndata:\n" + entries.map { "  \($0.key): \(Data($0.value.utf8).base64EncodedString())" }.joined(separator: "\n")
            if options.mask { out += "\n# stringData (masked preview):\n" + display.map { "#  \($0.key): \($0.value)" }.joined(separator: "\n") }
            lang = .yaml
        case "k8sconfig":
            out = "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: \(name)\ndata:\n" + display.map { "  \($0.key): \(JSONSerializer.quoted($0.value))" }.joined(separator: "\n")
            lang = .yaml
        case "dotenv":
            out = display.map { e in
                let needsQuotes = e.value.contains(" ") || e.value.contains("#") || e.value.contains("\n") || e.value.isEmpty || e.value.contains("\"")
                return "\(e.key)=\(needsQuotes ? JSONSerializer.quoted(e.value) : e.value)" + (e.comment.map { "  # \($0)" } ?? "")
            }.joined(separator: "\n")
            lang = .dotenv
        case "github":
            out = "env:\n" + display.map { "  \($0.key): \($0.isSecret ? "${{ secrets.\($0.key) }}" : JSONSerializer.quoted($0.value))" }.joined(separator: "\n")
            lang = .yaml
        default:
            out = JSONSerializer.string(.object(display.map { (key: $0.key, value: .string($0.value)) }))
            lang = .json
        }
        var rows = [MetaRow("Variables", "\(entries.count)"), MetaRow("Secrets detected", "\(entries.filter(\.isSecret).count)", style: entries.contains(where: \.isSecret) ? .warning : .plain)]
        for e in display { rows.append(MetaRow(e.key, e.value + (e.isSecret ? "  🔒" : ""), style: .mono)) }
        var annotations: [Annotation] = []
        for w in warns {
            let start = text.utf16Offset(line: w.line)
            let end = text.utf16Offset(line: w.line + 1)
            annotations.append(Annotation(.input, range: start..<max(start + 1, end - 1), style: .warning, tooltip: w.message))
        }
        return ToolOutput(text: out, language: lang, metadata: rows, annotations: annotations, warnings: warns.map { "Line \($0.line): \($0.message)" }, isValid: warns.isEmpty)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        let lines = s.split(separator: "\n").map { $0.trimmed() }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard lines.count >= 2 else { return nil }
        let kv = lines.filter { $0.range(of: "^(export )?[A-Z][A-Z0-9_]*=", options: .regularExpression) != nil }.count
        return kv >= 2 && kv * 10 >= lines.count * 7 ? DetectionScore(0.85, ".env variables") : nil
    }
}
