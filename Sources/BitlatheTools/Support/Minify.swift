import Foundation

enum Minify {
    /// Conservative CSS minifier: strips comments and whitespace, keeps strings and url() intact.
    static func css(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        let chars = Array(input)
        var i = 0
        var inString: Character?
        var pendingSpace = false
        func last() -> Character? { out.last }
        while i < chars.count {
            let c = chars[i]
            if let q = inString {
                out.append(c)
                if c == "\\", i + 1 < chars.count { out.append(chars[i + 1]); i += 2; continue }
                if c == q { inString = nil }
                i += 1
                continue
            }
            if c == "\"" || c == "'" { inString = c; if pendingSpace, let l = last(), !"{};:,>+~(".contains(l) { out.append(" ") }; pendingSpace = false; out.append(c); i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
                continue
            }
            if c.isWhitespace { pendingSpace = true; i += 1; continue }
            if "{};:,>+~".contains(c) {
                if c == "}" , last() == ";" { out.removeLast() }
                pendingSpace = false
                out.append(c)
                i += 1
                continue
            }
            if pendingSpace, let l = last(), !"{};:,>+~(".contains(l) { out.append(" ") }
            pendingSpace = false
            out.append(c)
            i += 1
        }
        return out.replacingOccurrences(of: ";}", with: "}").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// HTML minifier: removes comments, collapses whitespace between tags; preserves pre/textarea/script/style.
    static func html(_ input: String) -> String {
        var out = ""
        let ns = input as NSString
        let protectPattern = try? NSRegularExpression(pattern: "<(pre|textarea|script|style)\\b[^>]*>[\\s\\S]*?</\\1>", options: .caseInsensitive)
        var cursor = 0
        var segments: [(String, Bool)] = []
        protectPattern?.enumerateMatches(in: input, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            segments.append((ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)), false))
            segments.append((ns.substring(with: m.range), true))
            cursor = NSMaxRange(m.range)
        }
        segments.append((ns.substring(from: cursor), false))
        for (seg, protected) in segments {
            if protected { out += seg; continue }
            var s = seg.replacingOccurrences(of: "<!--(?!\\[if)[\\s\\S]*?-->", with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\n", with: "", options: .regularExpression)
            out += s
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
