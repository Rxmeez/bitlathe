import Foundation

/// Mends JSON that is nearly right: the mistakes people and programs actually make (a missing comma, a bracket that
/// was never closed, single quotes, Python's `True`/`None`, a log line cut off half-way). Rules only, so the same
/// input always gives the same output, and every change is reported. It never invents data: at most it adds a `null`
/// where a value is missing.
public enum JSONRepair {

    public struct Result: Sendable, Equatable {
        /// Strict JSON (compact). Format it with the JSON formatter.
        public let json: String
        /// What was changed, for people: "added 2 missing commas", "closed 1 bracket".
        public let fixes: [String]
        public var summary: String {
            guard let first = fixes.first else { return "Nothing to repair" }
            return (first.prefix(1).uppercased() + first.dropFirst()) + (fixes.count > 1 ? ", " + fixes.dropFirst().joined(separator: ", ") : "")
        }
    }

    /// Returns nil when the text is not JSON-shaped (does not start with `{` or `[`), needed no repair, or could not
    /// be brought to valid JSON.
    public static func repair(_ text: String) -> Result? {
        let scalars = Array(text.unicodeScalars)
        var machine = Machine(scalars)
        guard machine.run() else { return nil }
        // One value per line (JSON Lines, a log): each is read in turn and they are joined into an array, rather
        // than keeping the first and dropping the rest.
        var values = [machine.out.joined()]
        var counts = machine.counts
        var rest = machine
        while rest.done, rest.nextStartsValue, values.count < 100_000 {
            var next = Machine(scalars, from: rest.i)
            guard next.run() else { break }
            values.append(next.out.joined())
            for (fix, n) in next.counts where fix != .extra { counts[fix, default: 0] += n }
            rest = next
        }
        if values.count > 1 {
            counts[.extra] = rest.counts[.extra]
            counts[.joined] = values.count
            machine.out = ["[" + values.joined(separator: ",") + "]"]
            machine.counts = counts
        }
        guard !machine.counts.isEmpty else { return nil }
        let json = machine.out.joined()
        guard let data = json.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }
        return Result(json: json, fixes: machine.describe())
    }

    // MARK: - Implementation

    private enum Fix: String, CaseIterable {
        case joined, comma, trailingComma, closed, quotes, key, literal, string, colon, missingValue, comment, extra, bare
    }

    private enum Expect { case key, colon, value, valueOrEnd, commaOrEnd, keyOrEnd }

    private struct Machine {
        let s: [Unicode.Scalar]
        var i = 0
        var out: [String] = []
        var stack: [Character] = []
        var expect: Expect = .value
        var done = false
        var counts: [Fix: Int] = [:]

        init(_ s: [Unicode.Scalar], from start: Int = 0) { self.s = s; self.i = start }

        /// After a finished value: does another one start here?
        var nextStartsValue: Bool {
            var j = i
            while j < s.count, s[j].properties.isWhitespace || s[j] == "," { j += 1 }
            return j < s.count && (s[j] == "{" || s[j] == "[")
        }

        mutating func note(_ f: Fix) { counts[f, default: 0] += 1 }

        func describe() -> [String] {
            func n(_ c: Int, _ one: String, _ many: String) -> String { c == 1 ? one : many.replacingOccurrences(of: "#", with: "\(c)") }
            return Fix.allCases.compactMap { f -> String? in
                guard let c = counts[f] else { return nil }
                switch f {
                case .joined: return "joined \(c) values into one array"
                case .comma: return n(c, "added 1 missing comma", "added # missing commas")
                case .trailingComma: return n(c, "removed 1 stray comma", "removed # stray commas")
                case .closed: return n(c, "closed 1 bracket", "closed # brackets")
                case .quotes: return n(c, "changed 1 string to double quotes", "changed # strings to double quotes")
                case .key: return n(c, "quoted 1 key", "quoted # keys")
                case .literal: return n(c, "fixed 1 literal (true, false or null)", "fixed # literals (true, false or null)")
                case .string: return n(c, "mended 1 string", "mended # strings")
                case .colon: return n(c, "added 1 missing colon", "added # missing colons")
                case .missingValue: return n(c, "put null where 1 value was missing", "put null where # values were missing")
                case .comment: return n(c, "removed 1 comment", "removed # comments")
                case .extra: return "ignored text after the end"
                case .bare: return n(c, "quoted 1 bare word", "quoted # bare words")
                }
            }
        }

        mutating func run() -> Bool {
            skipSpace()
            guard i < s.count, s[i] == "{" || s[i] == "[" else { return false }
            while i < s.count, !done {
                skipSpace()
                guard i < s.count else { break }
                let c = s[i]
                switch c {
                case "{", "[": open(Character(c)); i += 1
                case "}", "]": close(Character(c)); i += 1
                case ",": comma(); i += 1
                case ":": colon(); i += 1
                case "\"", "'", "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}", "`": string(c)
                default: word()
                }
            }
            if !done { finish() } else {
                skipSpace()
                if i < s.count, !nextStartsValue { note(.extra) }
            }
            return done
        }

        mutating func skipSpace() {
            while i < s.count {
                let c = s[i]
                if c.properties.isWhitespace || c == "\u{FEFF}" { i += 1; continue }
                if c == "/", i + 1 < s.count, s[i + 1] == "/" {
                    while i < s.count, s[i] != "\n" { i += 1 }
                    note(.comment); continue
                }
                if c == "/", i + 1 < s.count, s[i + 1] == "*" {
                    i += 2
                    while i + 1 < s.count, !(s[i] == "*" && s[i + 1] == "/") { i += 1 }
                    i = min(i + 2, s.count)
                    note(.comment); continue
                }
                break
            }
        }

        // MARK: Structure

        /// Called before any key or value is written: supplies the comma or colon that should have come first.
        mutating func beforeItem(isString: Bool) {
            switch expect {
            case .commaOrEnd:
                out.append(","); note(.comma)
                expect = stack.last == "{" ? .key : .value
            case .colon:
                out.append(":"); note(.colon)
                expect = .value
            default: break
            }
        }

        mutating func afterValue() {
            if stack.isEmpty { done = true } else { expect = .commaOrEnd }
        }

        mutating func open(_ c: Character) {
            beforeItem(isString: false)
            if expect == .key || expect == .keyOrEnd {
                // A container where a key belongs cannot be mended sensibly; treat the object as an array would be wrong.
                out.append("\"\""); out.append(":"); note(.missingValue)
            }
            out.append(String(c))
            stack.append(c)
            expect = c == "{" ? .keyOrEnd : .valueOrEnd
        }

        mutating func close(_ c: Character) {
            guard !stack.isEmpty else { return }
            let wanted: Character = c == "}" ? "{" : "["
            guard stack.contains(wanted) else { note(.trailingComma); return }   // a closer with nothing to close: drop it
            settleBeforeClose()
            while let top = stack.last, top != wanted {
                out.append(top == "{" ? "}" : "]"); stack.removeLast(); note(.closed)
            }
            out.append(String(c)); stack.removeLast()
            afterValue()
        }

        /// Tidies what precedes a closing bracket: a dangling comma goes, a key without a value gets null.
        mutating func settleBeforeClose() {
            switch expect {
            case .key where out.last == ",", .value where out.last == ",":
                out.removeLast(); note(.trailingComma)
            case .colon:
                out.append(":"); out.append("null"); note(.missingValue)
            case .value:
                out.append("null"); note(.missingValue)
            default: break
            }
        }

        mutating func comma() {
            switch expect {
            case .commaOrEnd:
                out.append(",")
                expect = stack.last == "{" ? .key : .value
            case .colon:
                out.append(":"); out.append("null"); out.append(","); note(.missingValue)
                expect = .key
            case .value where stack.last == "{" && out.last == ":":
                out.append("null"); out.append(","); note(.missingValue)
                expect = .key
            default:
                note(.trailingComma)     // a leading or doubled comma
            }
        }

        mutating func colon() {
            if expect == .colon { out.append(":"); expect = .value } else { note(.colon) }
        }

        mutating func finish() {
            guard !stack.isEmpty else { return }
            settleBeforeClose()
            while let top = stack.popLast() { out.append(top == "{" ? "}" : "]"); note(.closed) }
            done = true
        }

        // MARK: Strings

        mutating func string(_ quote: Unicode.Scalar) {
            let closers: Set<Unicode.Scalar>
            switch quote {
            case "\"": closers = ["\""]
            case "'": closers = ["'"]
            case "`": closers = ["`"]
            case "\u{201C}", "\u{201D}": closers = ["\u{201C}", "\u{201D}", "\""]
            default: closers = ["\u{2018}", "\u{2019}", "'"]
            }
            if quote != "\"" { note(.quotes) }
            i += 1
            var body = String.UnicodeScalarView()
            var closed = false
            var mended = false
            while i < s.count {
                let c = s[i]
                if c == "\\", i + 1 < s.count {
                    let next = s[i + 1]
                    if next == "'" { body.append("'") }                       // \' is not a JSON escape
                    else if "\"\\/bfnrtu".unicodeScalars.contains(next) { body.append(c); body.append(next) }
                    else if next == "\n" { mended = true }                    // line continuation
                    else { body.append("\\"); body.append("\\"); body.append(next); mended = true }
                    i += 2; continue
                }
                if closers.contains(c) { closed = true; i += 1; break }
                switch c {
                case "\"": body.append("\\"); body.append("\"")
                case "\n": body.append(contentsOf: "\\n".unicodeScalars); mended = true
                case "\r": body.append(contentsOf: "\\r".unicodeScalars); mended = true
                case "\t": body.append(contentsOf: "\\t".unicodeScalars); mended = true
                default:
                    if c.value < 0x20 { body.append(contentsOf: String(format: "\\u%04x", c.value).unicodeScalars); mended = true } else { body.append(c) }
                }
                i += 1
            }
            if !closed || mended { note(.string) }
            emitString(String(body))
        }

        mutating func emitString(_ body: String) {
            beforeItem(isString: true)
            out.append("\"" + body + "\"")
            switch expect {
            case .key, .keyOrEnd: expect = .colon
            default: afterValue()
            }
        }

        // MARK: Bare words and numbers

        mutating func word() {
            let start = i
            while i < s.count {
                let c = s[i]
                if c.properties.isWhitespace || ",:{}[]\"'".unicodeScalars.contains(c) { break }
                i += 1
            }
            if i == start { i += 1; return }
            var w = String(String.UnicodeScalarView(s[start..<i]))
            // "…" or "..." at a cut-off point is the writer's "and so on", not data.
            if w.allSatisfy({ $0 == "." || $0 == "…" }) { note(.extra); return }
            beforeItem(isString: false)
            if expect == .key || expect == .keyOrEnd {
                out.append("\"" + escape(w) + "\""); note(.key)
                expect = .colon
                return
            }
            let literals = ["true": "true", "false": "false", "null": "null", "none": "null", "nil": "null", "undefined": "null", "nan": "null"]
            let lower = w.lowercased()
            if w == "true" || w == "false" || w == "null" {
                out.append(w)
            } else if let l = literals[lower] {
                out.append(l); note(.literal)
            } else if lower.count >= 2, let full = ["true", "false", "null"].first(where: { $0.hasPrefix(lower) }) {
                out.append(full); note(.literal)                                   // cut off: "tru", "fals"
            } else if let n = number(w) {
                if n != w { note(.literal) }
                out.append(n)
            } else {
                // A word run on to the next separator; values such as `2024-01-05` or `ok` can only be strings.
                while w.hasSuffix(";") { w.removeLast() }
                out.append("\"" + escape(w) + "\""); note(.bare)
            }
            afterValue()
        }

        func number(_ w: String) -> String? {
            if w.range(of: #"^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$"#, options: .regularExpression) != nil { return w }
            if w.lowercased().hasPrefix("0x"), let v = UInt64(w.dropFirst(2), radix: 16) { return String(v) }
            var t = w
            if t.hasPrefix("+") { t.removeFirst() }
            if t.hasPrefix(".") { t = "0" + t }
            if t.hasPrefix("-.") { t = "-0" + t.dropFirst() }
            if t.hasSuffix(".") { t.removeLast() }
            // Leading zeros ("007") are not JSON numbers.
            if t.range(of: #"^-?0\d+$"#, options: .regularExpression) != nil, let v = Int(t) { t = String(v) }
            return t != w && t.range(of: #"^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$"#, options: .regularExpression) != nil ? t : nil
        }

        func escape(_ w: String) -> String {
            w.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
    }
}
