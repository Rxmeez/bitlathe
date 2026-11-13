import Foundation
import BitlatheCore

public struct SemverTool: DevTool {
    public static let id = "semver.compare"
    public static let name = "Semver Comparator"
    public static let summary = "Parse, compare and sort semantic versions, and test them against npm/Cargo-style ranges"
    public static let category = ToolCategory.inspect
    public static let symbol = "number.circle"
    public static let keywords = ["semver", "version", "range", "caret", "tilde", "compare", "sort", "npm", "cargo", "bump"]
    public static let samples = [ToolSample("Sort versions", "1.10.0\n1.2.0\n1.2.0-beta.2\n1.2.0-beta.11\n2.0.0-rc.1\n1.2.0+build.5"), ToolSample("Range test", "^1.2.3", options: ["range": .string("^1.2.3"), "mode": .string("range")]),
                                 ToolSample("Single", "2.3.4-alpha.1+sha.abc")]
    public static let optionFields: [OptionField] = [
        .mode([.init("sort", "Parse & sort"), .init("range", "Test range")], default: "sort"),
        .text("range", "Range", placeholder: "^1.2.3 || >=2.0.0 <3.0.0", visibleWhen: ("mode", ["range"])),
        .toggle("includePrerelease", "Include pre-releases in ranges", visibleWhen: ("mode", ["range"])),
    ]
    public struct Options: ToolOptions {
        public var mode = "sort"
        public var range = ""
        public var includePrerelease = false
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let lines = text.components(separatedBy: "\n").map { $0.trimmed() }.filter { !$0.isEmpty }
        var versions: [Semver] = []
        var invalid: [String] = []
        for l in lines { if let v = Semver(l) { versions.append(v) } else { invalid.append(l) } }
        if options.mode == "range" {
            let rangeText = options.range.isEmpty ? (lines.count == 1 && Semver(lines[0]) == nil ? lines[0] : "") : options.range
            guard !rangeText.isEmpty else { throw ToolError("Enter a range in the options (e.g. ^1.2.3)") }
            let range = try SemverRange(rangeText)
            var rows = [MetaRow("Range", rangeText, style: .mono), MetaRow("Means", range.explanation)]
            if versions.isEmpty { return ToolOutput(text: range.explanation, metadata: rows) }
            var out: [String] = []
            for v in versions {
                let ok = range.satisfies(v, includePrerelease: options.includePrerelease)
                rows.append(MetaRow(v.description, ok ? "satisfies" : "does not satisfy", style: ok ? .success : .danger))
                out.append("\(ok ? "✓" : "✗") \(v)")
            }
            if let max = versions.filter({ range.satisfies($0, includePrerelease: options.includePrerelease) }).max() { rows.append(MetaRow("Max satisfying", max.description, style: .success)) }
            return ToolOutput(text: out.joined(separator: "\n"), metadata: rows)
        }
        guard !versions.isEmpty else { throw ToolError("No valid semantic versions found", hint: "Expected MAJOR.MINOR.PATCH[-prerelease][+build]") }
        if versions.count == 1, invalid.isEmpty {
            let v = versions[0]
            let rows = [
                MetaRow("Major", "\(v.major)"), MetaRow("Minor", "\(v.minor)"), MetaRow("Patch", "\(v.patch)"),
                MetaRow("Pre-release", v.prerelease.isEmpty ? "—" : v.prerelease.joined(separator: "."), style: .mono), MetaRow("Build metadata", v.build.isEmpty ? "—" : v.build.joined(separator: "."), style: .mono),
                MetaRow("Stability", v.major == 0 ? "Initial development (0.x): anything may change" : (v.prerelease.isEmpty ? "Stable" : "Pre-release")),
                MetaRow("Next patch", v.bumped(.patch).description, style: .mono), MetaRow("Next minor", v.bumped(.minor).description, style: .mono), MetaRow("Next major", v.bumped(.major).description, style: .mono),
                MetaRow("^ range", "\(v.caretRange)", style: .mono), MetaRow("~ range", "\(v.tildeRange)", style: .mono),
            ]
            return ToolOutput(text: v.description, metadata: rows)
        }
        let sorted = versions.sorted()
        var rows = [MetaRow("Versions", "\(versions.count) valid" + (invalid.isEmpty ? "" : ", \(invalid.count) invalid: \(invalid.joined(separator: ", "))"), style: invalid.isEmpty ? .plain : .warning)]
        if let lo = sorted.first, let hi = sorted.last { rows.append(MetaRow("Lowest", lo.description, style: .mono)); rows.append(MetaRow("Highest", hi.description, style: .mono)) }
        if let stable = sorted.last(where: { $0.prerelease.isEmpty }) { rows.append(MetaRow("Highest stable", stable.description, style: .mono)) }
        if versions.count == 2 {
            let c = versions[0] < versions[1] ? "<" : (versions[0] == versions[1] ? "==" : ">")
            rows.append(MetaRow("Comparison", "\(versions[0]) \(c) \(versions[1])", style: .mono))
            rows.append(MetaRow("Difference", versions[0].diffKind(versions[1])))
        }
        return ToolOutput(text: sorted.map(\.description).joined(separator: "\n"), metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        let lines = s.split(separator: "\n").map { $0.trimmed() }
        if lines.count >= 2, lines.allSatisfy({ Semver($0) != nil }) { return DetectionScore(0.85, "List of versions") }
        if lines.count == 1, Semver(lines[0]) != nil, s.contains(".") , s.range(of: "^v?\\d+\\.\\d+\\.\\d+", options: .regularExpression) != nil { return DetectionScore(s.contains("-") ? 0.7 : 0.5, "Semantic version") }
        if lines.count == 1, (try? SemverRange(lines[0])) != nil, s.range(of: "^[\\^~><=]", options: .regularExpression) != nil { return DetectionScore(0.7, "Version range", options: ["mode": .string("range")]) }
        return nil
    }
}

public struct Semver: Comparable, CustomStringConvertible, Sendable, Hashable {
    public var major: Int, minor: Int, patch: Int
    public var prerelease: [String]
    public var build: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = [], build: [String] = []) {
        self.major = major; self.minor = minor; self.patch = patch; self.prerelease = prerelease; self.build = build
    }

    public init?(_ s: String) {
        var t = s.trimmed()
        if t.hasPrefix("v") || t.hasPrefix("V") || t.hasPrefix("=") { t.removeFirst() }
        guard let m = t.captures("^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(?:-([0-9A-Za-z.-]+))?(?:\\+([0-9A-Za-z.-]+))?$") else { return nil }
        major = Int(m[1]) ?? 0; minor = Int(m[2]) ?? 0; patch = Int(m[3]) ?? 0
        prerelease = m[4].isEmpty ? [] : m[4].split(separator: ".").map(String.init)
        build = m[5].isEmpty ? [] : m[5].split(separator: ".").map(String.init)
        if prerelease.contains(where: { $0.isEmpty || ($0.allSatisfy(\.isNumber) && $0.count > 1 && $0.hasPrefix("0")) }) { return nil }
    }

    public var description: String {
        var s = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty { s += "-" + prerelease.joined(separator: ".") }
        if !build.isEmpty { s += "+" + build.joined(separator: ".") }
        return s
    }

    public static func < (a: Semver, b: Semver) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        if a.patch != b.patch { return a.patch < b.patch }
        if a.prerelease.isEmpty != b.prerelease.isEmpty { return !a.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) {
            if x == y { continue }
            if let xi = Int(x), let yi = Int(y) { return xi < yi }
            if Int(x) != nil { return true }
            if Int(y) != nil { return false }
            return x < y
        }
        return a.prerelease.count < b.prerelease.count
    }

    public static func == (a: Semver, b: Semver) -> Bool { a.major == b.major && a.minor == b.minor && a.patch == b.patch && a.prerelease == b.prerelease }

    public enum Part { case major, minor, patch }
    public func bumped(_ p: Part) -> Semver {
        switch p {
        case .major: Semver(major: major + 1, minor: 0, patch: 0)
        case .minor: Semver(major: major, minor: minor + 1, patch: 0)
        case .patch: Semver(major: major, minor: minor, patch: prerelease.isEmpty ? patch + 1 : patch)
        }
    }
    public var caretRange: String {
        if major > 0 { return ">=\(description) <\(major + 1).0.0" }
        if minor > 0 { return ">=\(description) <0.\(minor + 1).0" }
        return ">=\(description) <0.0.\(patch + 1)"
    }
    public var tildeRange: String { ">=\(description) <\(major).\(minor + 1).0" }

    public func diffKind(_ other: Semver) -> String {
        if major != other.major { return "major" }
        if minor != other.minor { return "minor" }
        if patch != other.patch { return "patch" }
        if prerelease != other.prerelease { return "prerelease" }
        return "none"
    }
}

/// npm-style ranges: ^, ~, >, >=, <, <=, =, x/X/* wildcards, hyphen ranges, || unions.
public struct SemverRange: Sendable {
    struct Comparator { var op: String; var version: Semver }
    var sets: [[Comparator]]
    public var explanation: String

    public init(_ text: String) throws {
        var sets: [[Comparator]] = []
        var explanations: [String] = []
        for alt in text.components(separatedBy: "||") {
            let t = alt.trimmed()
            var comps: [Comparator] = []
            var parts: [String] = []
            if t.isEmpty || t == "*" || t.lowercased() == "x" || t == "latest" {
                comps.append(Comparator(op: ">=", version: Semver(major: 0, minor: 0, patch: 0)))
                parts.append("any version")
            } else if let r = t.range(of: " - ") {
                let lo = Self.coerce(String(t[..<r.lowerBound]))
                let hiRaw = String(t[r.upperBound...]).trimmed()
                guard let lo else { throw ToolError("Invalid range \(t)") }
                comps.append(Comparator(op: ">=", version: lo))
                let hiParts = Self.significantParts(hiRaw)
                if let hi = Semver(hiRaw), hiParts == 3 { comps.append(Comparator(op: "<=", version: hi)) }
                else if let hi = Self.coerce(hiRaw) { comps.append(Comparator(op: "<", version: hiParts == 1 ? hi.bumped(.major) : hi.bumped(.minor))) }
                parts.append("from \(lo) up to \(hiRaw) inclusive")
            } else {
                for token in t.split(separator: " ").map(String.init) {
                    let (op, rest) = Self.splitOp(token)
                    let numParts = Self.significantParts(rest)
                    let hasWild = numParts < 3
                    guard let v = Self.coerce(rest) else { throw ToolError("Invalid version \"\(rest)\" in range") }
                    switch op {
                    case "^":
                        comps.append(Comparator(op: ">=", version: v))
                        let upper: Semver = v.major > 0 || numParts == 1 ? Semver(major: v.major + 1, minor: 0, patch: 0) : (v.minor > 0 || numParts == 2 ? Semver(major: 0, minor: v.minor + 1, patch: 0) : Semver(major: 0, minor: 0, patch: v.patch + 1))
                        comps.append(Comparator(op: "<", version: upper))
                        parts.append("\(v) or newer, without breaking changes (< \(upper))")
                    case "~":
                        comps.append(Comparator(op: ">=", version: v))
                        let upper = numParts == 1 ? Semver(major: v.major + 1, minor: 0, patch: 0) : Semver(major: v.major, minor: v.minor + 1, patch: 0)
                        comps.append(Comparator(op: "<", version: upper))
                        parts.append("\(v) or newer patch releases (< \(upper))")
                    case ">", ">=", "<", "<=":
                        if hasWild, op == ">" { comps.append(Comparator(op: ">=", version: numParts == 1 ? v.bumped(.major) : v.bumped(.minor))) }
                        else if hasWild, op == "<=" { comps.append(Comparator(op: "<", version: numParts == 1 ? v.bumped(.major) : v.bumped(.minor))) }
                        else { comps.append(Comparator(op: op, version: v)) }
                        parts.append("\(Self.word(op)) \(v)")
                    default:
                        if numParts == 0 {
                            comps.append(Comparator(op: ">=", version: v))
                            parts.append("any version")
                        } else if hasWild {
                            comps.append(Comparator(op: ">=", version: v))
                            comps.append(Comparator(op: "<", version: numParts == 1 ? v.bumped(.major) : v.bumped(.minor)))
                            parts.append("any \(rest) release")
                        } else {
                            comps.append(Comparator(op: "=", version: v))
                            parts.append("exactly \(v)")
                        }
                    }
                }
            }
            sets.append(comps)
            explanations.append(parts.joined(separator: " and "))
        }
        self.sets = sets
        explanation = explanations.joined(separator: ", or ").capitalizedFirst()
    }

    static func word(_ op: String) -> String {
        switch op {
        case ">": "greater than"
        case ">=": "at least"
        case "<": "less than"
        case "<=": "at most"
        default: "exactly"
        }
    }

    static func splitOp(_ t: String) -> (String, String) {
        for op in [">=", "<=", "^", "~>", "~", ">", "<", "="] where t.hasPrefix(op) { return (op == "~>" ? "~" : op, String(t.dropFirst(op.count)).trimmed()) }
        return ("", t)
    }

    /// Number of leading version parts that are concrete: "1.2.x" → 2, "1.x" → 1, "*" → 0, "1.2.3-next" → 3.
    static func significantParts(_ s: String) -> Int {
        var t = s.trimmed()
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        let core = t.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? ""
        var n = 0
        for part in core.split(separator: ".", omittingEmptySubsequences: false) {
            if part.isEmpty || part == "x" || part == "X" || part == "*" { break }
            n += 1
        }
        return n
    }

    /// Fill missing parts with 0: "1" → 1.0.0, "1.2.x" → 1.2.0
    static func coerce(_ s: String) -> Semver? {
        var t = s.trimmed()
        if t.hasPrefix("v") { t.removeFirst() }
        if let v = Semver(t) { return v }
        var pre = ""
        if let dash = t.firstIndex(of: "-") { pre = String(t[dash...]); t = String(t[..<dash]) }
        var parts = t.split(separator: ".").map { String($0) }.map { ($0 == "x" || $0 == "X" || $0 == "*") ? "0" : $0 }
        while parts.count < 3 { parts.append("0") }
        return Semver(parts.prefix(3).joined(separator: ".") + pre)
    }

    public func satisfies(_ v: Semver, includePrerelease: Bool = false) -> Bool {
        sets.contains { set in
            let ok = set.allSatisfy { c in
                switch c.op {
                case ">": v > c.version
                case ">=": v >= c.version
                case "<": v < c.version
                case "<=": v <= c.version
                default: v == c.version
                }
            }
            guard ok else { return false }
            if !v.prerelease.isEmpty, !includePrerelease {
                // Pre-release only matches if a comparator has the same major.minor.patch with a prerelease.
                return set.contains { !$0.version.prerelease.isEmpty && $0.version.major == v.major && $0.version.minor == v.minor && $0.version.patch == v.patch }
            }
            return true
        }
    }
}
