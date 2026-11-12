import Foundation
import BitlatheCore

public struct PunycodeTool: DevTool {
    public static let id = "punycode.idn"
    public static let name = "Punycode / IDN"
    public static let summary = "Convert internationalised domain names to xn-- Punycode and back"
    public static let category = ToolCategory.encode
    public static let symbol = "globe"
    public static let keywords = ["punycode", "idn", "idna", "xn--", "domain", "unicode", "encode", "decode"]
    public static let samples = [ToolSample("Encode", "münchen.de\nbücher.example\n例え.テスト"), ToolSample("Decode", "xn--mnchen-3ya.de\nxn--r8jz45g.xn--zckzah", options: ["mode": .string("decode")])]
    public static let optionFields: [OptionField] = [
        .encodeDecode,
        .toggle("rawPunycode", "Raw Punycode (no xn--, not a domain)", help: "Encode the whole string as one Punycode label"),
    ]
    public struct Options: ToolOptions {
        public var mode = "encode"
        public var rawPunycode = false
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let lines = text.components(separatedBy: "\n")
        let out = try lines.map { line -> String in
            let l = line.trimmed()
            if l.isEmpty { return "" }
            if options.rawPunycode { return options.mode == "encode" ? try Punycode.encode(l) : try Punycode.decode(l) }
            return options.mode == "encode" ? try Punycode.encodeDomain(l) : try Punycode.decodeDomain(l)
        }.joined(separator: "\n")
        return ToolOutput(text: out)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.contains("xn--"), s.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil { return DetectionScore(0.9, "Punycode domain", options: ["mode": .string("decode")]) }
        if Detect.isSingleLine(s), s.contains("."), !s.contains(" "), s.unicodeScalars.contains(where: { $0.value > 0x7F }), s.range(of: "^[\\p{L}\\p{N}.-]+$", options: .regularExpression) != nil {
            return DetectionScore(0.7, "Internationalised domain")
        }
        return nil
    }
}

/// RFC 3492 Punycode.
public enum Punycode {
    static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700, initialBias = 72, initialN = 128

    static func adapt(_ delta: Int, _ numPoints: Int, _ first: Bool) -> Int {
        var d = first ? delta / damp : delta / 2
        d += d / numPoints
        var k = 0
        while d > ((base - tMin) * tMax) / 2 { d /= base - tMin; k += base }
        return k + (base - tMin + 1) * d / (d + skew)
    }

    static func digit(_ d: Int) -> Character { Character(UnicodeScalar(d < 26 ? d + 97 : d - 26 + 48)!) }   // swiftlint:disable:this force_unwrapping
    static func value(_ c: Character) -> Int? {
        guard let a = c.asciiValue else { return nil }
        if a >= 48 && a <= 57 { return Int(a) - 22 }
        if a >= 65 && a <= 90 { return Int(a) - 65 }
        if a >= 97 && a <= 122 { return Int(a) - 97 }
        return nil
    }

    public static func encode(_ input: String) throws -> String {
        let scalars = input.unicodeScalars.map { Int($0.value) }
        var output = scalars.filter { $0 < 0x80 }.map { Character(UnicodeScalar($0)!) }   // swiftlint:disable:this force_unwrapping
        let basicCount = output.count
        if basicCount > 0 { output.append("-") }
        var n = initialN, delta = 0, bias = initialBias
        var handled = basicCount
        while handled < scalars.count {
            let m = scalars.filter { $0 >= n }.min()!   // swiftlint:disable:this force_unwrapping
            delta += (m - n) * (handled + 1)
            n = m
            for c in scalars {
                if c < n { delta += 1 }
                if c == n {
                    var q = delta
                    var k = base
                    while true {
                        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                        if q < t { break }
                        output.append(digit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(digit(q))
                    bias = adapt(delta, handled + 1, handled == basicCount)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return String(output)
    }

    public static func decode(_ input: String) throws -> String {
        var output: [Int] = []
        var rest = Array(input)
        if let dash = input.lastIndex(of: "-") {
            output = input[..<dash].unicodeScalars.map { Int($0.value) }
            rest = Array(input[input.index(after: dash)...])
        }
        var n = initialN, i = 0, bias = initialBias
        var idx = 0
        while idx < rest.count {
            let oldI = i
            var w = 1
            var k = base
            while true {
                guard idx < rest.count, let d = value(rest[idx]) else { throw ToolError("Invalid Punycode digit") }
                idx += 1
                i += d * w
                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if d < t { break }
                w *= base - t
                k += base
            }
            bias = adapt(i - oldI, output.count + 1, oldI == 0)
            n += i / (output.count + 1)
            i %= output.count + 1
            guard let _ = UnicodeScalar(UInt32(n)) else { throw ToolError("Invalid code point in Punycode") }
            output.insert(n, at: i)
            i += 1
        }
        return String(String.UnicodeScalarView(output.compactMap { UnicodeScalar(UInt32($0)) }))
    }

    public static func encodeDomain(_ domain: String) throws -> String {
        try domain.split(separator: ".", omittingEmptySubsequences: false).map { label -> String in
            let l = String(label)
            if l.unicodeScalars.allSatisfy({ $0.isASCII }) { return l }
            return "xn--" + (try encode(l.lowercased()))
        }.joined(separator: ".")
    }

    public static func decodeDomain(_ domain: String) throws -> String {
        try domain.split(separator: ".", omittingEmptySubsequences: false).map { label -> String in
            let l = String(label)
            if l.lowercased().hasPrefix("xn--") { return try decode(String(l.dropFirst(4))) }
            return l
        }.joined(separator: ".")
    }
}
