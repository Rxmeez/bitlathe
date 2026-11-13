import Foundation
import BitlatheCore

public struct ByteSizeTool: DevTool {
    public static let id = "convert.bytesize"
    public static let name = "Byte Size Converter"
    public static let summary = "Bytes, KB/KiB, MB/MiB, GB/GiB, TB/TiB and bits — decimal and binary at once"
    public static let category = ToolCategory.convert
    public static let symbol = "externaldrive"
    public static let keywords = ["bytes", "kb", "mb", "gb", "kib", "mib", "gib", "size", "storage", "bits", "convert"]
    public static let samples = [ToolSample("Gigabytes", "1.5 GB"), ToolSample("Bytes", "1073741824"), ToolSample("Mebibytes", "512 MiB")]
    public static let optionFields: [OptionField] = [.stepper("precision", "Decimals", min: 0, max: 10, default: 3)]
    public struct Options: ToolOptions {
        public var precision = 3
        public init() {}
    }
    public init() {}

    static let units: [(String, Double)] = [
        ("B", 1), ("KB", 1e3), ("MB", 1e6), ("GB", 1e9), ("TB", 1e12), ("PB", 1e15),
        ("KiB", 1024), ("MiB", 1048576), ("GiB", 1073741824), ("TiB", 1099511627776), ("PiB", 1125899906842624),
    ]

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed().replacingOccurrences(of: ",", with: "")
        guard let m = text.captures("^((?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+))\\s*([A-Za-z]*)$") else { throw ToolError("Enter a size like 1.5 GB, 512 MiB or 1024") }
        guard let value = Double(m[1]) else { throw ToolError("Invalid number") }
        var unit = m[2].isEmpty ? "B" : m[2]
        var bytes: Double
        let lower = unit.lowercased()
        if lower == "bit" || lower == "bits" || lower == "b" && unit == "b" { bytes = value / 8; unit = "bits" }
        else if lower.hasSuffix("bit") { 
            let prefix = String(lower.dropLast(3))
            let mult: Double = ["k": 1e3, "m": 1e6, "g": 1e9, "t": 1e12, "ki": 1024, "mi": 1048576, "gi": 1073741824][prefix] ?? 1
            bytes = value * mult / 8
        } else {
            let normalized = lower.hasSuffix("ib") ? (lower.prefix(1).uppercased() + "iB") : (lower == "b" || lower == "bytes" || lower == "byte" ? "B" : lower.prefix(1).uppercased() + "B")
            guard let u = Self.units.first(where: { $0.0 == normalized }) else { throw ToolError("Unknown unit \"\(unit)\"", hint: "Use B, KB, MB, GB, TB, KiB, MiB, GiB, TiB or bits") }
            bytes = value * u.1
        }
        func f(_ d: Double) -> String {
            let s = String(format: "%.\(options.precision)f", d)
            return s.contains(".") ? s.replacingOccurrences(of: "0+$", with: "", options: .regularExpression).replacingOccurrences(of: "\\.$", with: "", options: .regularExpression) : s
        }
        var rows = [MetaRow("Bytes", f(bytes.rounded()), style: .mono), MetaRow("Bits", f((bytes * 8).rounded()), style: .mono)]
        for u in Self.units.dropFirst() { rows.append(MetaRow(u.0, f(bytes / u.1), style: .mono)) }
        rows.append(MetaRow("Human (decimal)", ByteFormatter.string(Int(bytes))))
        rows.append(MetaRow("Human (binary)", ByteFormatter.string(Int(bytes), binary: true)))
        return ToolOutput(text: "", metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        // Length guard + a regex without overlapping quantifiers: `[0-9]*\.?[0-9]+` is quadratic on a long run of digits.
        guard s.utf8.count <= 40 else { return nil }
        return s.range(of: "^(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)\\s*([KMGTP]i?B|[kmgt]b|bytes?|bits?)$", options: [.regularExpression, .caseInsensitive]) != nil ? DetectionScore(0.8, "Byte size") : nil
    }
}

public struct UnitConverterTool: DevTool {
    public static let id = "convert.units"
    public static let name = "Developer Units"
    public static let summary = "Time durations, data rates and CSS px/pt/rem/em"
    public static let category = ToolCategory.convert
    public static let symbol = "ruler"
    public static let keywords = ["units", "duration", "milliseconds", "seconds", "data rate", "mbps", "px", "pt", "rem", "em", "css", "convert"]
    public static let samples = [ToolSample("Duration", "90061001 ms"), ToolSample("Data rate", "100 Mbps"), ToolSample("CSS", "24px", options: ["kind": .string("css")])]
    public static let optionFields: [OptionField] = [
        .segmented("kind", "Kind", [.init("auto", "Auto"), .init("duration", "Duration"), .init("rate", "Data rate"), .init("css", "CSS units")], default: "auto"),
        .stepper("baseFont", "Base px", min: 8, max: 32, default: 16, visibleWhen: ("kind", ["css", "auto"])),
    ]
    public struct Options: ToolOptions {
        public var kind = "auto"
        public var baseFont = 16
        public init() {}
    }
    public init() {}

    static let durations: [(String, [String], Double)] = [
        ("Nanoseconds", ["ns", "nanosecond", "nanoseconds"], 1e-9), ("Microseconds", ["us", "µs", "μs", "microsecond", "microseconds"], 1e-6),
        ("Milliseconds", ["ms", "millisecond", "milliseconds"], 1e-3), ("Seconds", ["s", "sec", "secs", "second", "seconds"], 1),
        ("Minutes", ["m", "min", "mins", "minute", "minutes"], 60), ("Hours", ["h", "hr", "hrs", "hour", "hours"], 3600),
        ("Days", ["d", "day", "days"], 86400), ("Weeks", ["w", "wk", "week", "weeks"], 604800), ("Years", ["y", "yr", "year", "years"], 31557600),
    ]
    static let rates: [(String, [String], Double)] = [
        ("bit/s", ["bps", "bit/s"], 1), ("Kbit/s", ["kbps", "kbit/s"], 1e3), ("Mbit/s", ["mbps", "mbit/s"], 1e6), ("Gbit/s", ["gbps", "gbit/s"], 1e9),
        ("B/s", ["b/s", "bytes/s"], 8), ("KB/s", ["kb/s", "kbs"], 8e3), ("MB/s", ["mb/s", "mbs"], 8e6), ("GB/s", ["gb/s", "gbs"], 8e9),
        ("KiB/s", ["kib/s"], 8 * 1024), ("MiB/s", ["mib/s"], 8 * 1048576), ("GiB/s", ["gib/s"], 8 * 1073741824),
    ]

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed().replacingOccurrences(of: ",", with: "")
        guard let m = text.captures("^(-?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+))\\s*([A-Za-zµμ/]*)$") else { throw ToolError("Enter a value with a unit, e.g. 1500 ms, 100 Mbps or 24px") }
        guard let value = Double(m[1]) else { throw ToolError("Invalid number") }
        let unit = m[2].lowercased()
        var kind = options.kind
        if kind == "auto" {
            if ["px", "pt", "rem", "em", "%", "vw", "vh"].contains(unit) || unit.isEmpty && value < 200 { kind = "css" }
            else if unit.contains("/") || unit.hasSuffix("bps") || unit.hasSuffix("bs") { kind = "rate" }
            else { kind = "duration" }
        }
        func f(_ d: Double) -> String {
            if d == 0 { return "0" }
            if abs(d) >= 1e15 || abs(d) < 1e-6 { return String(format: "%.4g", d) }
            let s = String(format: "%.6f", d)
            return s.replacingOccurrences(of: "0+$", with: "", options: .regularExpression).replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }
        switch kind {
        case "css":
            let base = Double(options.baseFont)
            let px: Double = switch unit {
            case "pt": value * 4 / 3
            case "rem", "em": value * base
            case "pc": value * 16
            case "in": value * 96
            case "cm": value * 96 / 2.54
            case "mm": value * 96 / 25.4
            case "", "px": value
            default: throw ToolError("Unknown CSS unit \"\(unit)\"", hint: "Supported: px, pt, rem, em, pc, in, cm, mm")
            }
            return ToolOutput(text: "", metadata: [
                MetaRow("px", f(px), style: .mono), MetaRow("pt", f(px * 3 / 4), style: .mono), MetaRow("rem (base \(options.baseFont))", f(px / base), style: .mono),
                MetaRow("em (base \(options.baseFont))", f(px / base), style: .mono), MetaRow("pc", f(px / 16), style: .mono), MetaRow("in", f(px / 96), style: .mono),
                MetaRow("cm", f(px / 96 * 2.54), style: .mono), MetaRow("mm", f(px / 96 * 25.4), style: .mono), MetaRow("@2x px", f(px * 2), style: .mono), MetaRow("@3x px", f(px * 3), style: .mono),
            ])
        case "rate":
            guard let r = Self.rates.first(where: { $0.1.contains(unit) }) else { throw ToolError("Unknown data rate unit \"\(unit)\"", hint: "Supported: bps, Kbps, Mbps, Gbps, B/s, KB/s, MB/s, GB/s, MiB/s") }
            let bits = value * r.2
            var rows = Self.rates.map { MetaRow($0.0, f(bits / $0.2), style: .mono) }
            rows.append(MetaRow("1 GB takes", Self.human(seconds: 8e9 / bits)))
            rows.append(MetaRow("1 GiB takes", Self.human(seconds: 8 * 1073741824 / bits)))
            return ToolOutput(text: "", metadata: rows)
        default:
            guard let d = Self.durations.first(where: { $0.1.contains(unit) }) ?? (unit.isEmpty ? Self.durations[3] : nil) else {
                throw ToolError("Unknown duration unit \"\(unit)\"", hint: "Supported: ns, µs, ms, s, min, h, d, w, y")
            }
            let seconds = value * d.2
            var rows = Self.durations.map { MetaRow($0.0, f(seconds / $0.2), style: .mono) }
            rows.append(MetaRow("Human", Self.human(seconds: seconds)))
            rows.append(MetaRow("HH:MM:SS", Self.clock(seconds: seconds), style: .mono))
            rows.append(MetaRow("ISO 8601", Self.iso(seconds: seconds), style: .mono))
            return ToolOutput(text: "", metadata: rows)
        }
    }

    static func human(seconds: Double) -> String {
        guard seconds.isFinite else { return "∞" }
        if seconds < 1e-3 { return String(format: "%.0f µs", seconds * 1e6) }
        if seconds < 1 { return String(format: "%.0f ms", seconds * 1e3) }
        var rem = seconds
        var parts: [String] = []
        for (name, secs) in [("y", 31557600.0), ("d", 86400.0), ("h", 3600.0), ("m", 60.0)] {
            let n = floor(rem / secs)
            if n > 0 { parts.append("\(Int(n))\(name)"); rem -= n * secs }
        }
        if rem > 0 || parts.isEmpty { parts.append(rem == rem.rounded() ? "\(Int(rem))s" : String(format: "%.3fs", rem)) }
        return parts.joined(separator: " ")
    }
    static func clock(seconds: Double) -> String {
        let total = Int(seconds)
        let ms = Int((seconds - Double(total)) * 1000)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) + (ms > 0 ? String(format: ".%03d", ms) : "")
    }
    static func iso(seconds: Double) -> String {
        var rem = Int(seconds)
        let d = rem / 86400; rem %= 86400
        let h = rem / 3600; rem %= 3600
        let m = rem / 60; rem %= 60
        var s = "P"
        if d > 0 { s += "\(d)D" }
        if h > 0 || m > 0 || rem > 0 || d == 0 { s += "T" }
        if h > 0 { s += "\(h)H" }
        if m > 0 { s += "\(m)M" }
        if rem > 0 || (d == 0 && h == 0 && m == 0) { s += "\(rem)S" }
        return s
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard s.utf8.count <= 40 else { return nil }
        if s.range(of: "^-?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)\\s*(ms|ns|µs|us|sec|secs|seconds?|mins?|minutes?|hours?|hrs?|days?|weeks?|[KMG]?bps|[KMG]i?B/s|px|pt|rem|em)$", options: [.regularExpression, .caseInsensitive]) != nil {
            return DetectionScore(0.75, "Value with a unit")
        }
        return nil
    }
}
