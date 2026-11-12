import Foundation

/// Small, fast fuzzy matcher used by the sidebar and the palette.
public enum Fuzzy {
    /// Returns a score (higher is better) or nil when the query does not match.
    public static func score(query: String, in primary: String, secondary: String? = nil) -> Int? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }
        let name = primary.lowercased()
        let ql = query.lowercased()
        if name.hasPrefix(ql) { return 3000 - name.count }
        if name.contains(ql) { return 2000 - name.count }
        if let s = subsequenceScore(q, Array(name), weight: 3), isTight(q, Array(name)) { return s + 1000 }
        if let secondary {
            // Whole-word or substring containment in id, keywords and summary — never scattered letters.
            let lower = secondary.lowercased()
            let words = lower.split { !$0.isLetter && !$0.isNumber }
            if words.contains(where: { $0.hasPrefix(ql) }) { return 600 }
            if ql.count >= 3, lower.contains(ql) { return 400 }
        }
        return nil
    }

    /// A subsequence match is "tight" when every matched character starts a word or follows the previous match.
    /// This accepts "jf" → "JSON Formatter" and "b64" → "Base64" but rejects "base" → "SCSS Formatter".
    private static func isTight(_ q: [Character], _ t: [Character]) -> Bool {
        var qi = 0
        var last = -2
        for (i, c) in t.enumerated() where qi < q.count && c == q[qi] {
            let wordStart = i == 0 || !(t[i - 1].isLetter || t[i - 1].isNumber) || (t[i].isNumber && !t[i - 1].isNumber)
            guard wordStart || i == last + 1 else { continue }
            last = i
            qi += 1
        }
        return qi == q.count
    }

    private static func subsequenceScore(_ q: [Character], _ t: [Character], weight: Int) -> Int? {
        var qi = 0
        var score = 0
        var lastMatch = -2
        var i = 0
        while i < t.count, qi < q.count {
            if t[i] == q[qi] {
                var s = 10
                if i == 0 || t[i - 1] == " " || t[i - 1] == "." || t[i - 1] == "-" { s += 15 }   // word start
                if i == lastMatch + 1 { s += 10 }                                              // consecutive
                score += s * weight
                lastMatch = i
                qi += 1
            }
            i += 1
        }
        guard qi == q.count else { return nil }
        // Prefer shorter targets.
        return score - t.count / 4
    }

    /// Indices of matched characters, for highlighting.
    public static func matchIndices(query: String, in text: String) -> [Int] {
        let q = Array(query.lowercased())
        let t = Array(text.lowercased())
        var out: [Int] = []
        var qi = 0
        for (i, c) in t.enumerated() where qi < q.count && c == q[qi] {
            out.append(i)
            qi += 1
        }
        return qi == q.count ? out : []
    }
}
