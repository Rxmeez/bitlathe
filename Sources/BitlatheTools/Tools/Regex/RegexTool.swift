import Foundation
import JavaScriptCore
import BitlatheCore

public struct RegexTool: DevTool {
    public static let id = "regex.test"
    public static let name = "RegExp Tester"
    public static let summary = "Live matches, capture groups, replacements and a plain-English explanation — ICU/PCRE-style or JavaScript semantics"
    public static let category = ToolCategory.inspect
    public static let symbol = "asterisk.circle"
    public static let keywords = ["regex", "regexp", "regular expression", "pattern", "match", "capture", "replace", "pcre", "icu", "javascript"]
    public static let io = ToolIO.text(.plain, .plain)
    public static let samples = [ToolSample("Emails", "Contact ada@example.com or grace.hopper@navy.mil; not bob@localhost.\nSupport: help@bitlathe.app", options: ["pattern": .string("(?<user>[\\w.+-]+)@(?<domain>[\\w-]+\\.[\\w.]+)"), "flags": .string("gi")]),
                                 ToolSample("Dates", "Released 2026-01-15, patched 2026-02-01 and 2026-3-9.", options: ["pattern": .string("(\\d{4})-(\\d{2})-(\\d{2})"), "replacement": .string("$3/$2/$1")])]
    public static let optionFields: [OptionField] = [
        .text("pattern", "Pattern", placeholder: "(\\w+)@(\\w+)\\.com", help: "The regular expression"),
        .text("flags", "Flags", placeholder: "gimsux", default: "g", help: "g global · i ignore case · m multiline · s dot matches newline · x extended · u unicode"),
        .segmented("engine", "Engine", [.init("icu", "ICU / PCRE"), .init("js", "JavaScript")], default: "icu"),
        .text("replacement", "Replace with", placeholder: "$1 or ${name}", help: "Leave empty to only match"),
    ]
    public struct Options: ToolOptions {
        public var pattern = ""
        public var flags = "g"
        public var engine = "icu"
        public var replacement = ""
        public init() {}
    }
    public init() {}

    public struct Match: Sendable, Equatable, Identifiable {
        public var id: Int { index }
        public var index: Int
        public var range: Range<Int>     // UTF-16
        public var text: String
        public var groups: [Group]
        public struct Group: Sendable, Equatable { public var index: Int; public var name: String?; public var range: Range<Int>?; public var text: String? }
    }

    public struct Result: Sendable {
        public var matches: [Match]
        public var groupNames: [String?]
        public var replaced: String?
        public var explanation: [String]
    }

    public static func test(_ text: String, options: Options) throws -> Result {
        guard !options.pattern.isEmpty else { throw ToolError("Enter a pattern in the options bar", hint: "Example: (\\w+)@(\\w+)\\.com") }
        let explanation = RegexExplainer.explain(options.pattern)
        if options.engine == "js" { return try testJS(text, options: options, explanation: explanation) }
        var opts: NSRegularExpression.Options = []
        if options.flags.contains("i") { opts.insert(.caseInsensitive) }
        if options.flags.contains("m") { opts.insert(.anchorsMatchLines) }
        if options.flags.contains("s") { opts.insert(.dotMatchesLineSeparators) }
        if options.flags.contains("x") { opts.insert(.allowCommentsAndWhitespace) }
        let re: NSRegularExpression
        do { re = try NSRegularExpression(pattern: options.pattern, options: opts) } catch {
            throw ToolError("Invalid pattern: \(Self.icuMessage(error))", hint: "Check for unbalanced parentheses or brackets")
        }
        let ns = text as NSString
        let names = Self.groupNames(options.pattern)
        var matches: [Match] = []
        let all = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for (i, m) in (options.flags.contains("g") ? all : Array(all.prefix(1))).enumerated() {
            var groups: [Match.Group] = []
            for g in 1..<m.numberOfRanges {
                let r = m.range(at: g)
                groups.append(Match.Group(index: g, name: g - 1 < names.count ? names[g - 1] : nil, range: r.location == NSNotFound ? nil : r.location..<(r.location + r.length), text: r.location == NSNotFound ? nil : ns.substring(with: r)))
            }
            matches.append(Match(index: i, range: m.range.location..<(m.range.location + m.range.length), text: ns.substring(with: m.range), groups: groups))
            if i > 10_000 { break }
        }
        var replaced: String?
        if !options.replacement.isEmpty {
            var template = options.replacement
            for (i, n) in names.enumerated() { if let n { template = template.replacingOccurrences(of: "${\(n)}", with: "$\(i + 1)").replacingOccurrences(of: "$<\(n)>", with: "$\(i + 1)") } }
            if options.flags.contains("g") { replaced = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: template) }
            else if let first = all.first { replaced = ns.replacingCharacters(in: first.range, with: re.replacementString(for: first, in: text, offset: 0, template: template)) }
            else { replaced = text }
        }
        return Result(matches: matches, groupNames: names, replaced: replaced, explanation: explanation)
    }

    static func icuMessage(_ e: any Error) -> String {
        let ns = e as NSError
        if let d = ns.userInfo[NSLocalizedDescriptionKey] as? String, !d.contains("couldn’t be completed") { return d }
        return "pattern cannot be compiled (ICU error \(ns.code))"
    }

    static func testJS(_ text: String, options: Options, explanation: [String]) throws -> Result {
        guard let ctx = JSContext() else { throw ToolError("No JavaScript context") }
        ctx.setObject(options.pattern, forKeyedSubscript: "__p" as NSString)
        ctx.setObject(options.flags.filter { "gimsuyd".contains($0) }, forKeyedSubscript: "__f" as NSString)
        ctx.setObject(text, forKeyedSubscript: "__t" as NSString)
        ctx.setObject(options.replacement, forKeyedSubscript: "__r" as NSString)
        let script = """
        (function(){
          var out = { matches: [], names: [], replaced: null, error: null };
          var re;
          try { re = new RegExp(__p, __f.indexOf('d') >= 0 ? __f : __f + 'd'); } catch (e) { out.error = String(e.message || e); return JSON.stringify(out); }
          var m; var count = 0;
          if (re.global) {
            while ((m = re.exec(__t)) !== null && count < 10000) { out.matches.push(conv(m)); count++; if (m[0].length === 0) re.lastIndex++; }
          } else { m = re.exec(__t); if (m) out.matches.push(conv(m)); }
          function conv(m) {
            var groups = [];
            var names = m.groups ? Object.keys(m.groups) : [];
            for (var i = 1; i < m.length; i++) {
              var name = null;
              for (var k = 0; k < names.length; k++) { if (m.groups[names[k]] === m[i] && m.indices && m.indices.groups && m.indices.groups[names[k]] && m.indices[i] && m.indices.groups[names[k]][0] === m.indices[i][0]) { name = names[k]; break; } }
              groups.push({ index: i, name: name, start: m.indices && m.indices[i] ? m.indices[i][0] : null, end: m.indices && m.indices[i] ? m.indices[i][1] : null, text: m[i] === undefined ? null : m[i] });
            }
            return { start: m.index, end: m.index + m[0].length, text: m[0], groups: groups };
          }
          var nameRe = /\\(\\?<([A-Za-z_$][\\w$]*)>/g; var nm;
          while ((nm = nameRe.exec(__p)) !== null) out.names.push(nm[1]);
          if (__r.length > 0) { try { out.replaced = __t.replace(new RegExp(__p, __f.replace('d','')), __r); } catch (e) { out.error = String(e.message || e); } }
          return JSON.stringify(out);
        })()
        """
        guard let json = ctx.evaluateScript(script)?.toString(), let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ToolError("JavaScript regex evaluation failed") }
        if let e = obj["error"] as? String { throw ToolError("Invalid pattern: \(e)") }
        let names = (obj["names"] as? [String]) ?? []
        var matches: [Match] = []
        for (i, m) in ((obj["matches"] as? [[String: Any]]) ?? []).enumerated() {
            let groups = ((m["groups"] as? [[String: Any]]) ?? []).map { g in
                Match.Group(index: g["index"] as? Int ?? 0, name: g["name"] as? String, range: (g["start"] as? Int).flatMap { s in (g["end"] as? Int).map { s..<$0 } }, text: g["text"] as? String)
            }
            matches.append(Match(index: i, range: (m["start"] as? Int ?? 0)..<(m["end"] as? Int ?? 0), text: m["text"] as? String ?? "", groups: groups))
        }
        return Result(matches: matches, groupNames: names.map { Optional($0) }, replaced: obj["replaced"] as? String, explanation: explanation)
    }

    static func groupNames(_ pattern: String) -> [String?] {
        // Walk the pattern and record capture groups in order (named or nil).
        var names: [String?] = []
        let chars = Array(pattern)
        var i = 0
        var inClass = false
        while i < chars.count {
            let c = chars[i]
            if c == "\\" { i += 2; continue }
            if inClass { if c == "]" { inClass = false }; i += 1; continue }
            if c == "[" { inClass = true; i += 1; continue }
            if c == "(" {
                if i + 1 < chars.count, chars[i + 1] == "?" {
                    if i + 2 < chars.count, chars[i + 2] == "<" || chars[i + 2] == "P" {
                        var j = i + 3
                        if chars[i + 2] == "P", j < chars.count, chars[j] == "<" { j += 1 }
                        if j < chars.count, chars[j] != "=", chars[j] != "!" {
                            var name = ""
                            while j < chars.count, chars[j] != ">" { name.append(chars[j]); j += 1 }
                            names.append(name)
                        }
                    }
                } else { names.append(nil) }
            }
            i += 1
        }
        return names
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        let result = try Self.test(text, options: options)
        var rows: [MetaRow] = [MetaRow("Matches", "\(result.matches.count)")]
        var annotations: [Annotation] = []
        for m in result.matches.prefix(2000) {
            annotations.append(Annotation(.input, range: m.range, style: .match, tooltip: "Match \(m.index + 1)"))
            for g in m.groups { if let r = g.range { annotations.append(Annotation(.input, range: r, style: .group, tooltip: g.name.map { "\(g.index): \($0)" } ?? "Group \(g.index)")) } }
        }
        var lines: [String] = []
        for m in result.matches.prefix(500) {
            let (l, c) = text.lineAndColumn(utf16Offset: m.range.lowerBound)
            lines.append("Match \(m.index + 1) @ \(l):\(c)  \(JSONSerializer.quoted(m.text))")
            for g in m.groups { lines.append("   \(g.name.map { "<\($0)>" } ?? "$\(g.index)")  \(g.text.map(JSONSerializer.quoted) ?? "—")") }
        }
        if !result.explanation.isEmpty { rows.append(MetaRow("Explanation", result.explanation.joined(separator: "\n"))) }
        var facets: [OutputFacet] = []
        if let r = result.replaced { facets.append(OutputFacet("Replaced", text: r)) }
        facets.append(OutputFacet("Matches only", text: result.matches.map(\.text).joined(separator: "\n")))
        if !result.groupNames.isEmpty { facets.append(OutputFacet("Groups as CSV", text: CSV.write(header: result.groupNames.enumerated().map { $0.element ?? "group\($0.offset + 1)" }, rows: result.matches.map { $0.groups.map { $0.text ?? "" } }))) }
        let body = result.replaced ?? (lines.isEmpty ? "No matches" : lines.joined(separator: "\n"))
        return ToolOutput(text: body, facets: facets, metadata: rows, annotations: annotations, isValid: nil)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isSingleLine(s), s.count < 300 else { return nil }
        if s.hasPrefix("/"), s.range(of: "/[gimsuy]*$", options: .regularExpression) != nil, s.count > 3 { return DetectionScore(0.75, "Regex literal", options: ["pattern": .string(String(s.dropFirst().prefix { $0 != "/" }))]) }
        if s.hasPrefix("^") || s.hasSuffix("$"), s.contains("\\") || s.contains("[") || s.contains("(") , (try? NSRegularExpression(pattern: s)) != nil { return DetectionScore(0.6, "Regular expression", options: ["pattern": .string(s)]) }
        return nil
    }
}

/// Produces a plain-English outline of a regular expression.
public enum RegexExplainer {
    public static func explain(_ pattern: String) -> [String] {
        var out: [String] = []
        let chars = Array(pattern)
        var i = 0
        var depth = 0
        func pad() -> String { String(repeating: "  ", count: depth) }
        func quantifier() -> String {
            guard i < chars.count else { return "" }
            var q = ""
            switch chars[i] {
            case "*": q = "zero or more times"; i += 1
            case "+": q = "one or more times"; i += 1
            case "?": q = "optionally"; i += 1
            case "{":
                var j = i + 1
                var body = ""
                while j < chars.count, chars[j] != "}" { body.append(chars[j]); j += 1 }
                if j < chars.count, body.range(of: "^\\d*(,\\d*)?$", options: .regularExpression) != nil, !body.isEmpty {
                    i = j + 1
                    let parts = body.split(separator: ",", omittingEmptySubsequences: false)
                    if parts.count == 1 { q = "exactly \(parts[0]) times" }
                    else if parts[1].isEmpty { q = "at least \(parts[0]) times" }
                    else if parts[0].isEmpty { q = "up to \(parts[1]) times" }
                    else { q = "between \(parts[0]) and \(parts[1]) times" }
                }
            default: break
            }
            if !q.isEmpty, i < chars.count {
                if chars[i] == "?" { q += " (lazy)"; i += 1 } else if chars[i] == "+" { q += " (possessive)"; i += 1 }
            }
            return q.isEmpty ? "" : " — \(q)"
        }
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "^": out.append(pad() + "^ start of line/string"); i += 1
            case "$": out.append(pad() + "$ end of line/string"); i += 1
            case ".": i += 1; out.append(pad() + ". any character" + quantifier())
            case "|": out.append(pad() + "| OR"); i += 1
            case "(":
                var label = "group"
                var j = i + 1
                if j < chars.count, chars[j] == "?" {
                    j += 1
                    if j < chars.count {
                        switch chars[j] {
                        case ":": label = "non-capturing group"; j += 1
                        case "=": label = "lookahead (must be followed by)"; j += 1
                        case "!": label = "negative lookahead (must not be followed by)"; j += 1
                        case "<":
                            if j + 1 < chars.count, chars[j + 1] == "=" { label = "lookbehind (must be preceded by)"; j += 2 }
                            else if j + 1 < chars.count, chars[j + 1] == "!" { label = "negative lookbehind"; j += 2 }
                            else {
                                var name = ""
                                j += 1
                                while j < chars.count, chars[j] != ">" { name.append(chars[j]); j += 1 }
                                j += 1
                                label = "named group «\(name)»"
                            }
                        case "P":
                            var name = ""
                            j += 2
                            while j < chars.count, chars[j] != ">" { name.append(chars[j]); j += 1 }
                            j += 1
                            label = "named group «\(name)»"
                        case ">": label = "atomic group"; j += 1
                        default:
                            var flags = ""
                            while j < chars.count, chars[j] != ":" && chars[j] != ")" { flags.append(chars[j]); j += 1 }
                            label = "inline flags \(flags)"
                            if j < chars.count, chars[j] == ")" { out.append(pad() + "(?\(flags)) set flags \(flags)"); i = j + 1; continue }
                            j += 1
                        }
                    }
                }
                out.append(pad() + "( " + label)
                depth += 1
                i = j
            case ")":
                depth = max(0, depth - 1)
                i += 1
                out.append(pad() + ")" + quantifier())
            case "[":
                var j = i + 1
                var negated = false
                if j < chars.count, chars[j] == "^" { negated = true; j += 1 }
                var body = ""
                if j < chars.count, chars[j] == "]" { body.append("]"); j += 1 }
                while j < chars.count, chars[j] != "]" {
                    if chars[j] == "\\", j + 1 < chars.count { body.append(chars[j]); body.append(chars[j + 1]); j += 2; continue }
                    body.append(chars[j]); j += 1
                }
                i = j + 1
                out.append(pad() + "[\(negated ? "^" : "")\(body)] " + (negated ? "any character except " : "one of ") + describeClass(body) + quantifier())
            case "\\":
                guard i + 1 < chars.count else { out.append(pad() + "\\ (dangling backslash)"); i += 1; continue }
                let n = chars[i + 1]
                var desc: String
                var consumed = 2
                switch n {
                case "d": desc = "a digit 0-9"
                case "D": desc = "a non-digit"
                case "w": desc = "a word character (letter, digit, underscore)"
                case "W": desc = "a non-word character"
                case "s": desc = "whitespace"
                case "S": desc = "non-whitespace"
                case "b": desc = "a word boundary"
                case "B": desc = "not a word boundary"
                case "n": desc = "a newline"
                case "t": desc = "a tab"
                case "r": desc = "a carriage return"
                case "A": desc = "start of string"
                case "z", "Z": desc = "end of string"
                case "u", "x":
                    var hex = ""
                    var j = i + 2
                    if j < chars.count, chars[j] == "{" { j += 1; while j < chars.count, chars[j] != "}" { hex.append(chars[j]); j += 1 }; j += 1 }
                    else { while j < chars.count, hex.count < (n == "u" ? 4 : 2), chars[j].isHexDigit { hex.append(chars[j]); j += 1 } }
                    consumed = j - i
                    desc = "the character U+\(hex.uppercased())" + (UInt32(hex, radix: 16).flatMap(UnicodeScalar.init).map { " (\($0))" } ?? "")
                case "p", "P":
                    var name = ""
                    var j = i + 2
                    if j < chars.count, chars[j] == "{" { j += 1; while j < chars.count, chars[j] != "}" { name.append(chars[j]); j += 1 }; j += 1 } else if j < chars.count { name.append(chars[j]); j += 1 }
                    consumed = j - i
                    desc = (n == "P" ? "not a " : "a ") + "character with Unicode property \(name)"
                case "k":
                    var name = ""
                    var j = i + 2
                    if j < chars.count, chars[j] == "<" { j += 1; while j < chars.count, chars[j] != ">" { name.append(chars[j]); j += 1 }; j += 1 }
                    consumed = j - i
                    desc = "the same text as group «\(name)»"
                default:
                    if n.isNumber { desc = "the same text as group \(n)" }
                    else { desc = "the literal character '\(n)'" }
                }
                i += consumed
                out.append(pad() + "\\\(n) " + desc + quantifier())
            default:
                var literal = String(c)
                i += 1
                while i < chars.count, !"^$.|()[\\*+?{".contains(chars[i]), !(i + 1 < chars.count && "*+?{".contains(chars[i + 1])) || (i + 1 < chars.count && chars[i + 1] == "{" && !isQuantifierBrace(chars, i + 1)) {
                    literal.append(chars[i]); i += 1
                }
                out.append(pad() + "\"\(literal)\" literally" + quantifier())
            }
        }
        return out
    }

    static func isQuantifierBrace(_ chars: [Character], _ i: Int) -> Bool {
        var j = i + 1
        var body = ""
        while j < chars.count, chars[j] != "}" { body.append(chars[j]); j += 1 }
        return j < chars.count && body.range(of: "^\\d+(,\\d*)?$|^,\\d+$", options: .regularExpression) != nil
    }

    static func describeClass(_ body: String) -> String {
        var parts: [String] = []
        let chars = Array(body)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count {
                let n = chars[i + 1]
                let names: [Character: String] = ["d": "digits", "w": "word characters", "s": "whitespace", "D": "non-digits", "W": "non-word characters", "S": "non-whitespace", "n": "newline", "t": "tab"]
                parts.append(names[n] ?? "'\(n)'")
                i += 2
            } else if i + 2 < chars.count, chars[i + 1] == "-" {
                parts.append("\(chars[i])–\(chars[i + 2])")
                i += 3
            } else {
                parts.append("'\(chars[i])'")
                i += 1
            }
        }
        return parts.joined(separator: ", ")
    }

    public static let cheatSheet: [(String, [(String, String)])] = [
        ("Characters", [(".", "any character except newline"), ("\\d \\D", "digit / non-digit"), ("\\w \\W", "word char / non-word"), ("\\s \\S", "whitespace / non-whitespace"), ("\\t \\n \\r", "tab, newline, return"), ("\\uXXXX", "Unicode code point"), ("\\p{L}", "Unicode letter (property)")]),
        ("Classes", [("[abc]", "a, b or c"), ("[^abc]", "not a, b or c"), ("[a-z]", "range"), ("[\\w.-]", "mixed class")]),
        ("Anchors", [("^ $", "start / end of line (m) or string"), ("\\b \\B", "word boundary / not"), ("\\A \\z", "start / end of string")]),
        ("Quantifiers", [("* + ?", "0+, 1+, 0–1"), ("{n} {n,} {n,m}", "exact, at least, between"), ("*? +? ??", "lazy versions"), ("*+ ++", "possessive (ICU)")]),
        ("Groups", [("(…)", "capture group"), ("(?:…)", "non-capturing"), ("(?<name>…)", "named group"), ("\\1 \\k<name>", "back-reference"), ("a|b", "alternation")]),
        ("Lookaround", [("(?=…)", "lookahead"), ("(?!…)", "negative lookahead"), ("(?<=…)", "lookbehind"), ("(?<!…)", "negative lookbehind")]),
        ("Flags", [("i", "case-insensitive"), ("m", "^ $ match at line breaks"), ("s", ". matches newline"), ("x", "ignore whitespace, allow # comments"), ("g", "all matches (not just first)"), ("u", "Unicode (JS)")]),
        ("Replacement", [("$1 $2", "group by number"), ("${name} / $<name>", "group by name"), ("$0 / $&", "whole match"), ("\\$", "literal dollar")]),
    ]
}
