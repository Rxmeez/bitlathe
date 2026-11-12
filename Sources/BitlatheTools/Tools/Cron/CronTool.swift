import Foundation
import BitlatheCore

public struct CronTool: DevTool {
    public static let id = "cron.parse"
    public static let name = "Cron Parser"
    public static let summary = "Explain cron expressions in plain English and list the next run times (standard, Quartz and AWS EventBridge)"
    public static let category = ToolCategory.inspect
    public static let symbol = "calendar.badge.clock"
    public static let keywords = ["cron", "crontab", "schedule", "quartz", "eventbridge", "aws", "next run", "every"]
    public static let samples = [ToolSample("Weekdays at 9:30", "30 9 * * 1-5"), ToolSample("Every 15 min", "*/15 * * * *"), ToolSample("Quartz", "0 0/5 14,18 * * ?", options: ["syntax": .string("quartz")]),
                                 ToolSample("EventBridge", "cron(0 12 ? * MON-FRI *)", options: ["syntax": .string("eventbridge")]), ToolSample("Macro", "@daily")]
    public static let optionFields: [OptionField] = [
        .segmented("syntax", "Syntax", [.init("auto", "Auto"), .init("standard", "Standard"), .init("quartz", "Quartz"), .init("eventbridge", "EventBridge")], default: "auto"),
        .stepper("count", "Next runs", min: 1, max: 50, default: 10),
        .text("timeZone", "Time zone", placeholder: "UTC", default: "", help: "IANA identifier; blank = system zone"),
    ]
    public struct Options: ToolOptions {
        public var syntax = "auto"
        public var count = 10
        public var timeZone = ""
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let zone = options.timeZone.isEmpty ? TimeZone.current : TimeZone(identifier: options.timeZone)
        guard let zone else { throw ToolError("Unknown time zone \"\(options.timeZone)\"") }
        let expr = try CronExpression.parse(text, syntax: options.syntax)
        let runs = expr.next(count: options.count, after: .now, zone: zone)
        let df = DateFormatter()
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss"
        df.timeZone = zone
        var rows = [MetaRow("Description", expr.description), MetaRow("Syntax", expr.syntax.title), MetaRow("Fields", expr.fieldSummary)]
        if let first = runs.first { rows.append(MetaRow("Next run", df.string(from: first) + " (" + UnixTimeTool.relative(first) + ")")) }
        if runs.count >= 2 {
            let gap = runs[1].timeIntervalSince(runs[0])
            rows.append(MetaRow("Interval", UnitConverterTool.human(seconds: gap)))
        }
        let listing = runs.enumerated().map { "\(String($0.offset + 1).padding(toLength: 3, withPad: " ", startingAt: 0))\(df.string(from: $0.element))  \(zone.abbreviation(for: $0.element) ?? "")" }.joined(separator: "\n")
        return ToolOutput(text: listing, metadata: rows, isValid: true)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isSingleLine(s) else { return nil }
        if s.hasPrefix("cron(") { return DetectionScore(0.95, "EventBridge cron") }
        if s.hasPrefix("@") , ["@yearly", "@annually", "@monthly", "@weekly", "@daily", "@midnight", "@hourly", "@reboot"].contains(s.lowercased()) { return DetectionScore(0.9, "Cron macro") }
        let parts = s.split(separator: " ")
        guard parts.count >= 5, parts.count <= 7, parts.allSatisfy({ $0.range(of: "^[\\d*/,\\-?LW#A-Za-z]+$", options: .regularExpression) != nil }) else { return nil }
        guard parts.contains(where: { $0.contains("*") || $0.contains("/") || $0.contains("-") || $0.contains(",") || $0 == "?" }) else { return nil }
        return (try? CronExpression.parse(s, syntax: "auto")) != nil ? DetectionScore(0.9, "Cron expression") : nil
    }
}

/// Cron parsing with standard (5/6 field), Quartz (6/7 field with ? L W #) and EventBridge semantics.
public struct CronExpression: Sendable {
    public enum Syntax: String, Sendable { case standard, quartz, eventbridge
        var title: String { rawValue == "eventbridge" ? "AWS EventBridge" : rawValue.capitalized }
    }

    public struct Field: Sendable {
        var values: Set<Int>
        var any: Bool
        var raw: String
        var lastDay = false            // L in day-of-month
        var lastWeekday: Int?          // nL in day-of-week
        var nearestWeekday: Int?       // nW
        var nth: (weekday: Int, n: Int)?   // d#n
        var lastDayOffset = 0          // L-3
        func matches(_ v: Int) -> Bool { any || values.contains(v) }
    }

    public var seconds: Field
    public var minutes: Field
    public var hours: Field
    public var dayOfMonth: Field
    public var month: Field
    public var dayOfWeek: Field
    public var year: Field?
    public var syntax: Syntax
    public var original: String

    static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    static let dayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    static let macros: [String: String] = ["@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *", "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *"]

    public static func parse(_ raw: String, syntax: String = "auto") throws -> CronExpression {
        var text = raw.trimmed()
        var mode = Syntax(rawValue: syntax)
        if text.lowercased().hasPrefix("cron(") , text.hasSuffix(")") { text = String(text.dropFirst(5).dropLast()); mode = .eventbridge }
        if text.lowercased() == "@reboot" { throw ToolError("@reboot runs once at startup and has no schedule") }
        if let m = macros[text.lowercased()] { text = m }
        let parts = text.split(separator: " ").map(String.init)
        if mode == nil {
            if parts.count == 5 { mode = .standard }
            else if parts.count == 7 { mode = .quartz }
            else if parts.count == 6 {
                // Quartz: `?` sits in the day-of-month (index 3) or day-of-week (index 5) slot.
                // EventBridge: `?` sits at index 2 or 4 and the last field is a year.
                if parts[3] == "?" || parts[5] == "?" { mode = .quartz }
                else if parts[2] == "?" || parts[4] == "?" || parts[5].range(of: "^(\\*|\\d{4}(-\\d{4})?(,\\d{4})*|\\d{4}/\\d+)$", options: .regularExpression) != nil { mode = .eventbridge }
                else { mode = parts[0].range(of: "^[0-5]?\\d$|^\\*$|^[0-9,/*-]+$", options: .regularExpression) != nil && parts[5].range(of: "^[A-Za-z]{3}", options: .regularExpression) != nil ? .quartz : .standard }
            }
            else { throw ToolError("Expected 5 fields (minute hour day month weekday), got \(parts.count)", hint: "Quartz uses 6–7 fields starting with seconds; EventBridge uses 6 fields ending with year") }
        }
        let s = mode!   // swiftlint:disable:this force_unwrapping
        var fields = parts
        var sec = Field(values: [0], any: false, raw: "0")
        var year: Field?
        switch s {
        case .standard:
            if fields.count == 6 { sec = try parseField(fields.removeFirst(), min: 0, max: 59, name: "second") }
            guard fields.count == 5 else { throw ToolError("Standard cron needs 5 fields (minute hour day month weekday), got \(parts.count)") }
        case .quartz:
            guard fields.count == 6 || fields.count == 7 else { throw ToolError("Quartz cron needs 6 or 7 fields (second minute hour day month weekday [year])") }
            sec = try parseField(fields.removeFirst(), min: 0, max: 59, name: "second")
            if fields.count == 6 { year = try parseField(fields.removeLast(), min: 1970, max: 2199, name: "year") }
        case .eventbridge:
            guard fields.count == 6 else { throw ToolError("EventBridge cron needs 6 fields (minutes hours day-of-month month day-of-week year)") }
            year = try parseField(fields.removeLast(), min: 1970, max: 2199, name: "year")
        }
        let min = try parseField(fields[0], min: 0, max: 59, name: "minute")
        let hr = try parseField(fields[1], min: 0, max: 23, name: "hour")
        let dom = try parseField(fields[2], min: 1, max: 31, name: "day of month", isDayOfMonth: true)
        let mon = try parseField(fields[3], min: 1, max: 12, name: "month", names: monthNames)
        let dow = try parseField(fields[4], min: 0, max: 7, name: "day of week", names: dayNames, isDayOfWeek: true, quartzDays: s != .standard)
        if s != .standard, dom.raw != "?", dow.raw != "?", !dom.any, !dow.any { throw ToolError("Specify ? for either day-of-month or day-of-week", hint: "Quartz and EventBridge do not allow both to be set") }
        return CronExpression(seconds: sec, minutes: min, hours: hr, dayOfMonth: dom, month: mon, dayOfWeek: dow, year: year, syntax: s, original: raw)
    }

    static func parseField(_ raw: String, min: Int, max: Int, name: String, names: [String] = [], isDayOfMonth: Bool = false, isDayOfWeek: Bool = false, quartzDays: Bool = false) throws -> Field {
        var f = Field(values: [], any: false, raw: raw)
        let upper = raw.uppercased()
        if upper == "*" || upper == "?" { f.any = true; return f }
        func value(_ s: String) throws -> Int {
            var t = s
            if let idx = names.firstIndex(of: t.uppercased()) { return idx + (isDayOfWeek ? 0 : 1) }
            if isDayOfWeek, quartzDays, let n = Int(t) { t = String(n - 1) }   // Quartz 1-7 → 0-6
            guard let n = Int(t) else { throw ToolError("Invalid \(name) value \"\(s)\"") }
            let v = isDayOfWeek && n == 7 ? 0 : n
            guard v >= min, v <= (isDayOfWeek ? 6 : max) else { throw ToolError("\(name.capitalizedFirst()) \(s) is out of range \(min)–\(isDayOfWeek ? 6 : max)") }
            return v
        }
        for part in upper.split(separator: ",").map(String.init) {
            if isDayOfMonth, part == "L" { f.lastDay = true; continue }
            if isDayOfMonth, part.hasPrefix("L-"), let n = Int(part.dropFirst(2)) { f.lastDay = true; f.lastDayOffset = n; continue }
            if isDayOfMonth, part == "LW" { f.lastDay = true; f.nearestWeekday = -1; continue }
            if isDayOfMonth, part.hasSuffix("W"), let n = Int(part.dropLast()) { f.nearestWeekday = n; continue }
            if isDayOfWeek, part == "L" { f.values.insert(6); continue }
            if isDayOfWeek, part.hasSuffix("L"), let d = try? value(String(part.dropLast())) { f.lastWeekday = d; continue }
            if isDayOfWeek, part.contains("#") {
                let kv = part.split(separator: "#")
                guard kv.count == 2, let n = Int(kv[1]), n >= 1, n <= 5 else { throw ToolError("Invalid nth weekday \"\(part)\"") }
                f.nth = (try value(String(kv[0])), n)
                continue
            }
            var rangePart = part
            var step = 1
            if let slash = part.firstIndex(of: "/") {
                rangePart = String(part[..<slash])
                guard let s = Int(part[part.index(after: slash)...]), s > 0 else { throw ToolError("Invalid step in \"\(part)\"") }
                step = s
            }
            var lo = min, hi = isDayOfWeek ? 6 : max
            if rangePart == "*" || rangePart == "?" {}
            else if let dash = rangePart.firstIndex(of: "-") {
                lo = try value(String(rangePart[..<dash]))
                hi = try value(String(rangePart[rangePart.index(after: dash)...]))
                if isDayOfWeek, hi < lo { f.values.formUnion(Array(lo...6) + Array(0...hi)); continue }
                guard lo <= hi else { throw ToolError("Range \(rangePart) is reversed") }
            } else {
                lo = try value(rangePart)
                hi = part.contains("/") ? (isDayOfWeek ? 6 : max) : lo
            }
            var v = lo
            while v <= hi { f.values.insert(v); v += step }
        }
        if f.values.isEmpty, !f.lastDay, f.nearestWeekday == nil, f.lastWeekday == nil, f.nth == nil { throw ToolError("Empty \(name) field") }
        return f
    }

    // MARK: Matching

    func matchesDay(_ date: Date, cal: Calendar) -> Bool {
        let comps = cal.dateComponents([.day, .weekday, .month, .year], from: date)
        let day = comps.day!, weekday = comps.weekday! - 1   // swiftlint:disable:this force_unwrapping
        let daysInMonth = cal.range(of: .day, in: .month, for: date)!.count   // swiftlint:disable:this force_unwrapping
        var domMatch = dayOfMonth.any
        if !domMatch {
            if dayOfMonth.values.contains(day) { domMatch = true }
            if dayOfMonth.lastDay {
                if dayOfMonth.nearestWeekday == -1 {
                    var last = daysInMonth
                    var wd = (weekday - (day - last)) %% 7
                    if wd == 6 { last -= 1 } else if wd == 0 { last -= 2 }
                    wd = 0
                    if day == last { domMatch = true }
                } else if day == daysInMonth - dayOfMonth.lastDayOffset { domMatch = true }
            }
            if let w = dayOfMonth.nearestWeekday, w > 0 {
                let targetWeekday = (weekday - (day - w)) %% 7
                var target = w
                if targetWeekday == 6 { target = w == 1 ? 3 : w - 1 } else if targetWeekday == 0 { target = w == daysInMonth ? w - 2 : w + 1 }
                if day == target { domMatch = true }
            }
        }
        var dowMatch = dayOfWeek.any
        if !dowMatch {
            if dayOfWeek.values.contains(weekday) { dowMatch = true }
            if let lw = dayOfWeek.lastWeekday, weekday == lw, day + 7 > daysInMonth { dowMatch = true }
            if let nth = dayOfWeek.nth, weekday == nth.weekday, (day - 1) / 7 + 1 == nth.n { dowMatch = true }
        }
        if syntax == .standard {
            // Vixie cron: if both restricted, either matches.
            if !dayOfMonth.any && !dayOfWeek.any { return domMatch || dowMatch }
            return domMatch && dowMatch
        }
        return dayOfMonth.raw == "?" ? dowMatch : (dayOfWeek.raw == "?" ? domMatch : (domMatch && dowMatch))
    }

    public func next(count: Int, after start: Date, zone: TimeZone) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        var results: [Date] = []
        let hasSeconds = syntax == .quartz || !seconds.values.isSubset(of: [0]) || seconds.any
        var t = cal.date(bySetting: .nanosecond, value: 0, of: start) ?? start
        t = t.addingTimeInterval(hasSeconds ? 1 : 60 - Double(cal.component(.second, from: t)))
        if !hasSeconds { t = cal.date(bySetting: .second, value: 0, of: t) ?? t }
        var iterations = 0
        let limit = cal.date(byAdding: .year, value: 30, to: start) ?? start
        while results.count < count, iterations < 2_000_000, t < limit {
            iterations += 1
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: t)
            if let y = year, !y.matches(c.year!) {   // swiftlint:disable:this force_unwrapping
                guard let nextYear = cal.date(from: DateComponents(year: c.year! + 1, month: 1, day: 1)) else { break }   // swiftlint:disable:this force_unwrapping
                t = nextYear
                continue
            }
            if !month.matches(c.month!) {   // swiftlint:disable:this force_unwrapping
                let firstOfNext = cal.date(from: DateComponents(year: c.year, month: c.month! + 1, day: 1))!   // swiftlint:disable:this force_unwrapping
                t = firstOfNext
                continue
            }
            if !matchesDay(t, cal: cal) {
                t = cal.date(from: DateComponents(year: c.year, month: c.month, day: c.day! + 1))!   // swiftlint:disable:this force_unwrapping
                continue
            }
            if !hours.matches(c.hour!) {   // swiftlint:disable:this force_unwrapping
                t = cal.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: c.hour! + 1))!   // swiftlint:disable:this force_unwrapping
                continue
            }
            if !minutes.matches(c.minute!) {   // swiftlint:disable:this force_unwrapping
                t = cal.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: c.hour, minute: c.minute! + 1))!   // swiftlint:disable:this force_unwrapping
                continue
            }
            if hasSeconds, !seconds.matches(c.second!) {   // swiftlint:disable:this force_unwrapping
                t = t.addingTimeInterval(1)
                continue
            }
            results.append(t)
            t = t.addingTimeInterval(hasSeconds ? 1 : 60)
        }
        return results
    }

    // MARK: Description

    public var fieldSummary: String {
        var parts = ["minute \(minutes.raw)", "hour \(hours.raw)", "day \(dayOfMonth.raw)", "month \(month.raw)", "weekday \(dayOfWeek.raw)"]
        if syntax == .quartz { parts.insert("second \(seconds.raw)", at: 0) }
        if let y = year { parts.append("year \(y.raw)") }
        return parts.joined(separator: " · ")
    }

    public var description: String {
        func list(_ values: [Int], _ f: (Int) -> String) -> String {
            let items = values.map(f)
            if items.count <= 1 { return items.first ?? "" }
            return items.dropLast().joined(separator: ", ") + " and " + items.last!   // swiftlint:disable:this force_unwrapping
        }
        func pad(_ n: Int) -> String { String(format: "%02d", n) }
        func stepOf(_ f: Field, max: Int) -> Int? {
            let sorted = f.values.sorted()
            guard sorted.count >= 2 else { return nil }
            let step = sorted[1] - sorted[0]
            guard step > 1, zip(sorted, sorted.dropFirst()).allSatisfy({ $1 - $0 == step }), sorted.first == 0 || f.raw.contains("/") else { return nil }
            return step
        }
        var time: String
        if minutes.any && hours.any {
            time = seconds.any ? "every second" : "every minute"
            if let s = stepOf(seconds, max: 59) { time = "every \(s) seconds" }
        } else if hours.any {
            if let step = stepOf(minutes, max: 59) { time = "every \(step) minutes" }
            else if minutes.values.count == 1 { time = "at minute \(minutes.values.first!) past every hour" }   // swiftlint:disable:this force_unwrapping
            else { time = "at minutes \(list(minutes.values.sorted()) { String($0) }) past every hour" }
        } else if minutes.values.count == 1 || minutes.any {
            let m = minutes.any ? nil : minutes.values.first
            if let step = stepOf(hours, max: 23) { time = "every \(step) hours" + (m.map { " at minute \($0)" } ?? "") }
            else if m == nil { time = "every minute during hour\(hours.values.count > 1 ? "s" : "") \(list(hours.values.sorted()) { pad($0) })" }
            else { time = "at " + list(hours.values.sorted()) { "\(pad($0)):\(pad(m!))" } }   // swiftlint:disable:this force_unwrapping
        } else {
            time = "at minutes \(list(minutes.values.sorted()) { String($0) }) past hour\(hours.values.count > 1 ? "s" : "") \(list(hours.values.sorted()) { pad($0) })"
        }
        var when: [String] = []
        if !dayOfMonth.any, dayOfMonth.raw != "?" {
            var parts: [String] = []
            if !dayOfMonth.values.isEmpty { parts.append("on day \(list(dayOfMonth.values.sorted()) { ordinal($0) }) of the month") }
            if dayOfMonth.lastDay { parts.append(dayOfMonth.nearestWeekday == -1 ? "on the last weekday of the month" : (dayOfMonth.lastDayOffset > 0 ? "\(dayOfMonth.lastDayOffset) days before the end of the month" : "on the last day of the month")) }
            if let w = dayOfMonth.nearestWeekday, w > 0 { parts.append("on the weekday nearest the \(ordinal(w))") }
            when.append(parts.joined(separator: " and "))
        }
        if !dayOfWeek.any, dayOfWeek.raw != "?" {
            var parts: [String] = []
            let days = dayOfWeek.values.sorted()
            if days == [1, 2, 3, 4, 5] { parts.append("Monday through Friday") }
            else if days == [0, 6] { parts.append("on weekends") }
            else if !days.isEmpty { parts.append("on " + list(days) { Self.fullDay($0) }) }
            if let lw = dayOfWeek.lastWeekday { parts.append("on the last \(Self.fullDay(lw)) of the month") }
            if let nth = dayOfWeek.nth { parts.append("on the \(ordinal(nth.n)) \(Self.fullDay(nth.weekday)) of the month") }
            when.append((syntax == .standard && !dayOfMonth.any ? "or " : "") + parts.joined(separator: " and "))
        }
        if !month.any {
            let months = month.values.sorted()
            when.append("in " + list(months) { DateFormatter().monthSymbols[$0 - 1] })
        }
        if let y = year, !y.any { when.append("in " + list(y.values.sorted().prefix(5).map { $0 }) { String($0) } + (y.values.count > 5 ? "…" : "")) }
        var s = time.capitalizedFirst()
        if !when.isEmpty { s += ", " + when.joined(separator: ", ") }
        return s + "."
    }

    func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    static func fullDay(_ d: Int) -> String { ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d % 7] }
}

infix operator %%: MultiplicationPrecedence
func %% (a: Int, b: Int) -> Int { ((a % b) + b) % b }
