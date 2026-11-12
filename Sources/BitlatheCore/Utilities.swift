import Foundation

public extension String {
    /// 1-based line and column for a UTF-16 offset.
    func lineAndColumn(utf16Offset: Int) -> (line: Int, column: Int) {
        var line = 1
        var col = 1
        var i = 0
        for u in utf16 {
            if i >= utf16Offset { break }
            if u == 10 { line += 1; col = 1 } else { col += 1 }
            i += 1
        }
        return (line, col)
    }

    /// UTF-16 offset of the start of a 1-based line.
    func utf16Offset(line: Int, column: Int = 1) -> Int {
        var current = 1
        var i = 0
        for u in utf16 {
            if current == line { return i + max(column - 1, 0) }
            if u == 10 { current += 1 }
            i += 1
        }
        return utf16.count
    }

    var lineCount: Int { isEmpty ? 0 : reduce(into: 1) { if $1 == "\n" { $0 += 1 } } }

    var nsRange: NSRange { NSRange(location: 0, length: utf16.count) }


    /// Detects the line ending style of the text.
    var lineEndingKinds: Set<String> {
        var kinds: Set<String> = []
        var prev: Character?
        for c in self {
            if c == "\r\n" { kinds.insert("CRLF") }
            else if c == "\n" { kinds.insert("LF") }
            else if c == "\r" { kinds.insert("CR") }
            prev = c
        }
        _ = prev
        return kinds
    }

    func indented(by prefix: String) -> String {
        split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : prefix + $0 }.joined(separator: "\n")
    }


    func matches(_ regex: String) -> Bool { range(of: regex, options: .regularExpression) != nil }

    /// All regex captures for the first match.
    func captures(_ regex: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: regex), let m = re.firstMatch(in: self, range: nsRange) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : (self as NSString).substring(with: r)
        }
    }
}

public extension StringProtocol {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
    func removingPrefix(_ p: String) -> String { hasPrefix(p) ? String(dropFirst(p.count)) : String(self) }
    func removingSuffix(_ s: String) -> String { hasSuffix(s) ? String(dropLast(s.count)) : String(self) }
    func capitalizedFirst() -> String {
        guard let f = first else { return String(self) }
        return f.uppercased() + dropFirst()
    }
}

public extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        let clean = hex.filter { !$0.isWhitespace && $0 != ":" }.removingPrefix("0x")
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let b = UInt8(clean[idx..<next], radix: 16) else { return nil }
            data.append(b)
            idx = next
        }
        self = data
    }

    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL s: String) {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        t = Detect.padBase64(t)
        self.init(base64Encoded: t)
    }
}

public enum ByteFormatter {
    public static func string(_ bytes: Int, binary: Bool = false) -> String {
        let units = binary ? ["B", "KiB", "MiB", "GiB", "TiB"] : ["B", "KB", "MB", "GB", "TB"]
        let base: Double = binary ? 1024 : 1000
        var v = Double(bytes)
        var i = 0
        while v >= base && i < units.count - 1 { v /= base; i += 1 }
        return i == 0 ? "\(bytes) B" : String(format: "%.1f %@", v, units[i])
    }
}

public enum DurationFormatter {
    public static func ms(_ d: Duration) -> String {
        let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        if ms < 1 { return String(format: "%.2f ms", ms) }
        if ms < 1000 { return String(format: "%.0f ms", ms) }
        return String(format: "%.2f s", ms / 1000)
    }
}

/// Seedable random generator (SplitMix64) for reproducible fake data.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public extension Task where Success == Never, Failure == Never {
    /// Cooperative yield point for long loops.
    static func checkpoint() throws {
        try Task.checkCancellation()
    }
}
