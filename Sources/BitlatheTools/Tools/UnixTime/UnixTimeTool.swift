import Foundation
import BitlatheCore

public struct UnixTimeTool: DevTool {
    public static let id = "time.unix"
    public static let name = "Unix Time Converter"
    public static let summary = "Seconds, milliseconds, microseconds and nanoseconds ⇄ dates in any time zone, with relative time"
    public static let category = ToolCategory.inspect
    public static let symbol = "clock"
    public static let keywords = ["unix", "epoch", "timestamp", "date", "time", "iso 8601", "rfc 2822", "utc", "timezone", "milliseconds", "relative"]
    public static let samples = [ToolSample("Seconds", "1700000000"), ToolSample("Milliseconds", "1700000000123"), ToolSample("ISO 8601", "2026-11-12T15:30:00+01:00"), ToolSample("Now", "now")]
    public static let optionFields: [OptionField] = [
        .picker("unit", "Input unit", [.init("auto", "Auto"), .init("s", "Seconds"), .init("ms", "Milliseconds"), .init("us", "Microseconds"), .init("ns", "Nanoseconds")], default: "auto"),
        .text("timeZone", "Time zone", placeholder: "Europe/London", default: "", help: "IANA identifier; blank = system zone"),
        .text("cities", "Compare", placeholder: "America/New_York, Asia/Tokyo", default: "America/Los_Angeles, America/New_York, Europe/London, Europe/Berlin, Asia/Kolkata, Asia/Tokyo, Australia/Sydney", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var unit = "auto"
        public var timeZone = ""
        public var cities = "America/Los_Angeles, America/New_York, Europe/London, Europe/Berlin, Asia/Kolkata, Asia/Tokyo, Australia/Sydney"
        public init() {}
    }
    public init() {}

    public struct Parsed: Sendable {
        public var date: Date
        public var source: String
        public var fractional: Bool
    }

    public static func parse(_ raw: String, unit: String = "auto") -> Parsed? {
        let text = raw.trimmed()
        if text.isEmpty { return nil }
        if ["now", "today"].contains(text.lowercased()) { return Parsed(date: .now, source: "now", fractional: false) }
        let digits = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "_", with: "")
        if let d = Double(digits), digits.range(of: "^-?\\d+(\\.\\d+)?$", options: .regularExpression) != nil {
            let magnitude = abs(d)
            var seconds: Double
            var source: String
            switch unit {
            case "s": seconds = d; source = "seconds"
            case "ms": seconds = d / 1e3; source = "milliseconds"
            case "us": seconds = d / 1e6; source = "microseconds"
            case "ns": seconds = d / 1e9; source = "nanoseconds"
            default:
                if digits.contains(".") || magnitude < 1e11 { seconds = d; source = "seconds" }
                else if magnitude < 1e14 { seconds = d / 1e3; source = "milliseconds" }
                else if magnitude < 1e17 { seconds = d / 1e6; source = "microseconds" }
                else { seconds = d / 1e9; source = "nanoseconds" }
            }
            return Parsed(date: Date(timeIntervalSince1970: seconds), source: "Unix \(source)", fractional: seconds != seconds.rounded())
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: text) { return Parsed(date: d, source: "ISO 8601", fractional: true) }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: text) { return Parsed(date: d, source: "ISO 8601", fractional: false) }
        iso.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withTimeZone]
        if let d = iso.date(from: text) { return Parsed(date: d, source: "ISO 8601", fractional: false) }
        iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: text) { return Parsed(date: d, source: "Date", fractional: false) }
        let formats = ["yyyy-MM-dd HH:mm:ss.SSSZZZZZ", "yyyy-MM-dd HH:mm:ssZZZZZ", "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSXXXXX",
                       "yyyy-MM-dd'T'HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd", "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "MM/dd/yyyy", "EEE, dd MMM yyyy HH:mm:ss Z", "EEE MMM dd HH:mm:ss zzz yyyy",
                       "dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy", "MMM d, yyyy", "MMMM d, yyyy", "d MMMM yyyy", "yyyyMMdd'T'HHmmss'Z'", "yyyyMMddHHmmss", "yyyyMMdd", "HH:mm:ss", "@yyyy-MM-dd"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        for f in formats {
            df.dateFormat = f
            if let d = df.date(from: text) { return Parsed(date: d, source: f.contains("EEE") ? "RFC 2822" : "Date string", fractional: false) }
        }
        // Natural language via Foundation data detector
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let m = detector.firstMatch(in: text, range: text.nsRange), let d = m.date, m.range.length >= text.count - 2 {
            return Parsed(date: d, source: "Natural language", fractional: false)
        }
        return nil
    }

    public static func relative(_ date: Date, to now: Date = .now) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        let delta = date.timeIntervalSince(now)
        if abs(delta) < 5 { return "just now" }
        return f.localizedString(fromTimeInterval: delta)
    }

    public static func rows(for date: Date, zone: TimeZone, cities: [TimeZone]) -> [MetaRow] {
        let utc = TimeZone(identifier: "UTC")!   // swiftlint:disable:this force_unwrapping
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoLocal = ISO8601DateFormatter()
        isoLocal.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoLocal.timeZone = zone
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        rfc.timeZone = zone
        let human = DateFormatter()
        human.dateStyle = .full
        human.timeStyle = .long
        human.timeZone = zone
        let t = date.timeIntervalSince1970
        let cal = Calendar(identifier: .iso8601)
        var c = cal
        c.timeZone = zone
        let comps = c.dateComponents([.weekOfYear, .yearForWeekOfYear, .weekday], from: date)
        let dayOfYear = c.ordinality(of: .day, in: .year, for: date) ?? 0
        let weekday = human.weekdaySymbols[(comps.weekday ?? 1) - 1]
        var rows: [MetaRow] = [
            MetaRow("Local (\(zone.identifier))", human.string(from: date)),
            MetaRow("Relative", relative(date)),
            MetaRow("ISO 8601 (UTC)", iso.string(from: date), style: .mono),
            MetaRow("ISO 8601 (local)", isoLocal.string(from: date), style: .mono),
            MetaRow("RFC 2822", rfc.string(from: date), style: .mono),
            MetaRow("Unix seconds", String(Int64(t.rounded(.down))), style: .mono),
            MetaRow("Unix milliseconds", String(Int64((t * 1000).rounded(.down))), style: .mono),
            MetaRow("Unix microseconds", String(Int64((t * 1e6).rounded(.down))), style: .mono),
            MetaRow("Unix nanoseconds", String(Int64((t * 1e9).rounded(.down))), style: .mono),
            MetaRow("Day", "\(weekday), day \(dayOfYear) of the year, ISO week \(comps.weekOfYear ?? 0) of \(comps.yearForWeekOfYear ?? 0)"),
            MetaRow("UTC offset", Self.offset(zone, date) + (zone.isDaylightSavingTime(for: date) ? " (DST)" : "")),
            MetaRow("Excel serial", String(format: "%.6f", t / 86400 + 25569), style: .mono),
            MetaRow("Mac absolute time", String(format: "%.3f", date.timeIntervalSinceReferenceDate), style: .mono),
            MetaRow("Julian day", String(format: "%.5f", t / 86400 + 2440587.5), style: .mono),
        ]
        _ = utc
        let cityFmt = DateFormatter()
        cityFmt.locale = Locale.current
        cityFmt.dateFormat = "EEE HH:mm (dd MMM)"
        for tz in cities {
            cityFmt.timeZone = tz
            let city: String = tz.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tz.identifier
            rows.append(MetaRow("🌍 " + city, cityFmt.string(from: date) + "  " + Self.offset(tz, date)))
        }
        return rows
    }

    public static func offset(_ zone: TimeZone, _ date: Date) -> String {
        let s = zone.secondsFromGMT(for: date)
        let sign = s < 0 ? "-" : "+"
        return String(format: "UTC%@%02d:%02d", sign, abs(s) / 3600, (abs(s) % 3600) / 60)
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let lines = text.components(separatedBy: "\n").map { $0.trimmed() }.filter { !$0.isEmpty }
        let zone = options.timeZone.isEmpty ? TimeZone.current : (TimeZone(identifier: options.timeZone) ?? TimeZone(abbreviation: options.timeZone))
        guard let zone else { throw ToolError("Unknown time zone \"\(options.timeZone)\"", hint: "Use an IANA name like Europe/Paris or an abbreviation like EST") }
        let cities = options.cities.split(separator: ",").compactMap { TimeZone(identifier: $0.trimmed()) }
        if lines.count > 1 {
            // Batch mode: one line per timestamp.
            let iso = ISO8601DateFormatter()
            iso.timeZone = zone
            var out: [String] = []
            for l in lines {
                if let p = Self.parse(l, unit: options.unit) { out.append("\(l)  →  \(iso.string(from: p.date))  (\(Self.relative(p.date)))") } else { out.append("\(l)  →  ?") }
            }
            return ToolOutput(text: out.joined(separator: "\n"))
        }
        guard let parsed = Self.parse(text, unit: options.unit) else {
            throw ToolError("Could not understand \"\(text)\" as a time", hint: "Try a Unix timestamp, ISO 8601, RFC 2822 or 'now'")
        }
        var rows = [MetaRow("Interpreted as", parsed.source)]
        rows += Self.rows(for: parsed.date, zone: zone, cities: cities)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = zone
        return ToolOutput(text: "", facets: [OutputFacet("ISO 8601", text: iso.string(from: parsed.date)), OutputFacet("Unix seconds", text: String(Int64(parsed.date.timeIntervalSince1970)))], metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isSingleLine(s), s.count <= 40 else { return nil }
        if s.range(of: "^\\d{9,19}$", options: .regularExpression) != nil, let v = Double(s) {
            if v >= 1e8 && v < 1e11 { return DetectionScore(0.85, "Unix timestamp (seconds)") }
            if v >= 1e11 && v < 1e14 { return DetectionScore(0.85, "Unix timestamp (milliseconds)") }
            if v >= 1e14 && v < 1e17 { return DetectionScore(0.7, "Unix timestamp (microseconds)") }
            if v >= 1e17 { return DetectionScore(0.7, "Unix timestamp (nanoseconds)") }
        }
        if s.range(of: "^\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}", options: .regularExpression) != nil { return DetectionScore(0.85, "ISO 8601 date") }
        if s.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil { return DetectionScore(0.6, "Date") }
        if s.range(of: "^[A-Z][a-z]{2}, \\d{1,2} [A-Z][a-z]{2} \\d{4}", options: .regularExpression) != nil { return DetectionScore(0.85, "RFC 2822 date") }
        return nil
    }
}
