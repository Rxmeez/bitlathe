import Foundation
import BitlatheCore

public struct ChmodTool: DevTool {
    public static let id = "chmod.calc"
    public static let name = "chmod Calculator"
    public static let summary = "Convert between octal (755), symbolic (rwxr-xr-x) and chmod flags, with setuid/setgid/sticky"
    public static let category = ToolCategory.inspect
    public static let symbol = "lock.doc"
    public static let keywords = ["chmod", "permissions", "octal", "rwx", "unix", "file mode", "umask", "setuid", "sticky"]
    public static let samples = [ToolSample("Octal", "755"), ToolSample("Symbolic", "rw-r--r--"), ToolSample("ls -l", "-rwsr-xr-x"), ToolSample("Modifiers", "u=rwx,g=rx,o=")]
    public struct Options: ToolOptions { public init() {} }
    public init() {}

    public struct Mode: Sendable, Equatable {
        public var bits: Int   // 12 bits: special(3) owner(3) group(3) other(3)
        public init(bits: Int) { self.bits = bits & 0o7777 }
        public var octal: String { bits > 0o777 ? String(format: "%04o", bits) : String(format: "%03o", bits) }
        public var symbolic: String {
            var s = ""
            for (i, who) in [(6, 0o4000), (3, 0o2000), (0, 0o1000)].enumerated() {
                let r = bits & (4 << who.0) != 0, w = bits & (2 << who.0) != 0, x = bits & (1 << who.0) != 0
                let special = bits & who.1 != 0
                s += r ? "r" : "-"
                s += w ? "w" : "-"
                if i == 2 { s += special ? (x ? "t" : "T") : (x ? "x" : "-") } else { s += special ? (x ? "s" : "S") : (x ? "x" : "-") }
            }
            return s
        }
        public func has(_ mask: Int) -> Bool { bits & mask != 0 }
        public var ugo: String {
            func part(_ shift: Int) -> String {
                var s = ""
                if bits & (4 << shift) != 0 { s += "r" }
                if bits & (2 << shift) != 0 { s += "w" }
                if bits & (1 << shift) != 0 { s += "x" }
                return s
            }
            return "u=\(part(6)),g=\(part(3)),o=\(part(0))"
        }
    }

    public static func parse(_ raw: String) throws -> Mode {
        var s = raw.trimmed()
        if s.hasPrefix("chmod ") {
            // `chmod [-R] <mode> <file…>`: keep only the mode argument.
            let args = s.dropFirst(6).split(whereSeparator: \.isWhitespace).map(String.init)
            s = args.first { $0.range(of: "^-[A-Za-z]{1,3}$", options: .regularExpression) == nil } ?? ""
        }
        if let r = s.range(of: "^[0-7]{3,4}$", options: .regularExpression) {
            return Mode(bits: Int(s[r], radix: 8) ?? 0)
        }
        if s.count == 10, "-dlcbps".contains(s.first!) { s = String(s.dropFirst()) }   // swiftlint:disable:this force_unwrapping
        if s.range(of: "^[rwxsStT-]{9}$", options: .regularExpression) != nil {
            var bits = 0
            let c = Array(s)
            for (i, shift) in [6, 3, 0].enumerated() {
                if c[i * 3] == "r" { bits |= 4 << shift }
                if c[i * 3 + 1] == "w" { bits |= 2 << shift }
                let x = c[i * 3 + 2]
                if x == "x" || x == "s" || x == "t" { bits |= 1 << shift }
                if x == "s" || x == "S" { bits |= i == 0 ? 0o4000 : 0o2000 }
                if x == "t" || x == "T" { bits |= 0o1000 }
            }
            return Mode(bits: bits)
        }
        if s.range(of: "^[ugoa]*[=+-][rwxXst]*(,[ugoa]*[=+-][rwxXst]*)*$", options: .regularExpression) != nil {
            var bits = 0
            for clause in s.split(separator: ",") {
                guard let opIdx = clause.firstIndex(where: { "=+-".contains($0) }) else { continue }
                var who = String(clause[..<opIdx])
                if who.isEmpty || who == "a" { who = "ugo" }
                let op = clause[opIdx]
                let perms = clause[clause.index(after: opIdx)...]
                var mask = 0
                for w in who {
                    let shift = w == "u" ? 6 : (w == "g" ? 3 : 0)
                    var p = 0
                    if perms.contains("r") { p |= 4 }
                    if perms.contains("w") { p |= 2 }
                    if perms.contains("x") || perms.contains("X") { p |= 1 }
                    mask |= p << shift
                    if perms.contains("s") { mask |= w == "u" ? 0o4000 : (w == "g" ? 0o2000 : 0) }
                    if perms.contains("t") { mask |= 0o1000 }
                    if op == "=" { bits &= ~(7 << shift) }
                }
                switch op {
                case "+", "=": bits |= mask
                default: bits &= ~mask
                }
            }
            return Mode(bits: bits)
        }
        throw ToolError("Enter an octal mode (755), symbolic string (rwxr-xr-x) or clauses (u=rwx,go=rx)")
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let m = try Self.parse(text)
        func who(_ shift: Int) -> String {
            [("read", 4), ("write", 2), ("execute", 1)].filter { m.bits & ($0.1 << shift) != 0 }.map(\.0).joined(separator: ", ").ifEmpty("none")
        }
        var rows = [
            MetaRow("Octal", m.octal, style: .mono), MetaRow("Symbolic", m.symbolic, style: .mono), MetaRow("Clauses", m.ugo, style: .mono),
            MetaRow("Owner", who(6)), MetaRow("Group", who(3)), MetaRow("Others", who(0)),
            MetaRow("Command", "chmod \(m.octal) <file>", style: .mono),
            MetaRow("umask equivalent", String(format: "%03o", (~m.bits) & 0o777), style: .mono),
        ]
        if m.has(0o4000) { rows.append(MetaRow("setuid", "Runs as the file owner", style: .warning)) }
        if m.has(0o2000) { rows.append(MetaRow("setgid", "Runs as the group / new files inherit the group", style: .warning)) }
        if m.has(0o1000) { rows.append(MetaRow("sticky", "Only owners can delete files in this directory", style: .warning)) }
        if m.bits & 0o002 != 0 { rows.append(MetaRow("Warning", "World-writable", style: .danger)) }
        return ToolOutput(text: m.octal, facets: [OutputFacet("Symbolic", text: m.symbolic), OutputFacet("Clauses", text: m.ugo)], metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.range(of: "^-?[rwxsStT-]{9}$", options: .regularExpression) != nil { return DetectionScore(0.9, "Unix permission string") }
        if s.range(of: "^chmod ", options: .regularExpression) != nil { return DetectionScore(0.8, "chmod command") }
        if s.range(of: "^[0-7]{3,4}$", options: .regularExpression) != nil, ["755", "644", "600", "700", "777", "664", "775", "400", "440", "444", "2755", "4755", "1777", "0644", "0755"].contains(s) { return DetectionScore(0.6, "Octal file mode") }
        return nil
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
