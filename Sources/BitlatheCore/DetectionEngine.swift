import Foundation

public struct DetectionResult: Sendable, Identifiable, Equatable {
    public var id: String { tool.id }
    public let tool: AnyTool
    public let score: DetectionScore
}

public struct DetectionReport: Sendable {
    public var results: [DetectionResult]
    public var duration: Duration
    public var truncated: Bool
    public var best: DetectionResult? { results.first }
    public var alsoTry: [DetectionResult] { Array(results.dropFirst().prefix(4)) }
}

/// Runs every tool's `detect` over a sample and ranks the matches.
public enum DetectionEngine {
    public static let sampleLimit = 64 * 1024
    public static let maxInputBytes = 8 * 1024 * 1024

    public static func detect(_ text: String, tools: [AnyTool], ignoring ignored: Set<String> = [],
                              minimumConfidence: Double = 0.3) -> DetectionReport {
        let clock = ContinuousClock()
        let start = clock.now
        var truncated = false
        var sample = text
        if sample.utf8.count > sampleLimit {
            sample = String(sample.utf8.prefix(sampleLimit)) ?? String(sample.prefix(sampleLimit))
            truncated = true
        }
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [DetectionResult] = []
        guard !trimmed.isEmpty else {
            return DetectionReport(results: [], duration: clock.now - start, truncated: truncated)
        }
        for tool in tools where !tool.sideEffects && !ignored.contains(tool.id) {
            if let score = tool.detect(trimmed), score.confidence >= minimumConfidence {
                results.append(DetectionResult(tool: tool, score: score))
            }
        }
        results.sort { lhs, rhs in
            if lhs.score.confidence != rhs.score.confidence { return lhs.score.confidence > rhs.score.confidence }
            return lhs.tool.name < rhs.tool.name
        }
        return DetectionReport(results: results, duration: clock.now - start, truncated: truncated)
    }
}

// MARK: - Shared detection helpers used by many tools

public enum Detect {
    public static let base64Chars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
    public static let base64URLChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=")
    public static let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

    public static func isBase64(_ s: String, minLength: Int = 8) -> Bool {
        let t = s.filter { !$0.isWhitespace }
        guard t.count >= minLength, t.count % 4 == 0 || t.hasSuffix("=") == false else { return false }
        guard t.unicodeScalars.allSatisfy({ base64Chars.contains($0) }) else { return false }
        return Data(base64Encoded: padBase64(t)) != nil
    }

    public static func isBase64URL(_ s: String, minLength: Int = 8) -> Bool {
        guard s.count >= minLength else { return false }
        return s.unicodeScalars.allSatisfy { base64URLChars.contains($0) }
    }

    public static func padBase64(_ s: String) -> String {
        let r = s.count % 4
        return r == 0 ? s : s + String(repeating: "=", count: 4 - r)
    }

    public static func isHex(_ s: String, minLength: Int = 2) -> Bool {
        let t = s.filter { !$0.isWhitespace && $0 != ":" }
        guard t.count >= minLength, t.count % 2 == 0 else { return false }
        return t.unicodeScalars.allSatisfy { hexChars.contains($0) }
    }

    public static func looksLikeJSON(_ s: String) -> Bool {
        guard let f = s.first, let l = s.last else { return false }
        return (f == "{" && l == "}") || (f == "[" && l == "]")
    }

    public static func isSingleLine(_ s: String) -> Bool { !s.contains("\n") }

    public static func matches(_ pattern: String, _ s: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    public static func wholeMatch(_ pattern: String, _ s: String) -> Bool {
        guard let r = s.range(of: "^(?:\(pattern))$", options: .regularExpression) else { return false }
        return r.lowerBound == s.startIndex && r.upperBound == s.endIndex
    }
}
