import Foundation

/// Small, fast fuzzy matcher used by the sidebar and the palette.
public enum Fuzzy {
    /// Returns a score (higher is better) or nil when the query does not match.
    public static func score(query: String, in primary: String, secondary: String? = nil) -> Int? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }
        if let s = subsequenceScore(q, Array(primary.lowercased()), weight: 3) { return s + 1000 }
        if let secondary {
            // Word-level containment in keywords/summary.
            let lower = secondary.lowercased()
            if lower.contains(query.lowercased()) { return 500 }
            if let s = subsequenceScore(q, Array(lower), weight: 1) { return s }
        }
        return nil
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
