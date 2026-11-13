import Foundation

/// The engine behind the Smart Box home screen. Given whatever was pasted or typed, it works out what the text is,
/// which actions make sense, and orders them by detection confidence plus what this person chose before for the
/// same kind of data. Pure and synchronous: the app runs the chosen action with the tool's own engine.
public enum SmartBox {

    /// One suggested action: run `tool` with `options` (optionally followed by a second step).
    public struct Action: Sendable, Identifiable, Equatable {
        public var id: String { key }
        /// Stable identity used for learning: "tool.id", "tool.id|mode=minify", or "tool.id>next.id" for chains.
        public let key: String
        public let tool: AnyTool
        public let options: OptionValues
        /// A second step for chained actions (Base64 decode, then format the JSON inside).
        public let then: Step?
        /// Text to run instead of the box contents (typed commands such as "now").
        public let inputOverride: String?
        /// True when the action only opens the tool's full screen (a word matched a tool that needs more input).
        public let opensTool: Bool
        /// Short label for the action chip ("JSON Formatter").
        public let title: String
        /// Secondary label (the chosen mode, "Minify"), if any.
        public let detail: String?
        /// Why it is suggested, from detection ("Valid JSON") or the command parser.
        public let reason: String
        public let confidence: Double
        /// How many times this person accepted this action for this kind of data.
        public var learned: Int

        // 4 points per accept: one stray copy does not reorder things, two or three consistent choices do.
        public var score: Double { confidence * 100 + Double(min(learned, 40)) * 4 }
        public var isChain: Bool { then != nil }
    }

    public struct Step: Sendable, Equatable {
        public let tool: AnyTool
        public let options: OptionValues
        public init(tool: AnyTool, options: OptionValues = [:]) { self.tool = tool; self.options = options }
    }

    public enum Kind: Sendable, Equatable {
        /// Recognised data (JSON, a JWT, a timestamp…).
        case data
        /// A typed command ("3 uuid v7", "password", "now").
        case command
        /// Words that are not data: matching tools to open, plus general text tools.
        case words
    }

    public struct Analysis: Sendable {
        public var kind: Kind
        /// Bucket for learning: the top detected tool's id ("jwt.debug"), "command:uuid", or "words".
        public var formatKey: String
        /// What it looks like, for people ("JSON Web Token").
        public var formatName: String
        public let confidence: Double
        public var actions: [Action]
        /// Credentials or keys: shown with a warning, and never handed to a model.
        public var isSensitive: Bool
    }

    /// formatKey → action key → times accepted.
    public typealias Learned = [String: [String: Int]]

    /// Tools that make sense for any plain text when nothing more specific matches.
    public static let textFallbackIDs = ["string.inspect", "text.case", "text.lines", "hash.generate", "url.encode", "base64.text"]

    // MARK: - Analysis

    public static func analyse(_ text: String, tools: [AnyTool], ignoring: Set<String> = [], learned: Learned = [:],
                               limit: Int = 6) -> Analysis? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let byID = Dictionary(tools.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        if let command = Command.parse(trimmed, tools: byID) {
            var a = Analysis(kind: .command, formatKey: "command:\(command.name)", formatName: "Command", confidence: 0.95,
                             actions: command.actions, isSensitive: false)
            a.actions = rank(a.actions, learned: learned[a.formatKey] ?? [:], tools: byID, limit: limit)
            return a
        }

        // A typed instruction ("sha256 hello", "to yaml {…}"): do that to the rest of the text. What the data
        // itself would get (the JSON formatter for JSON) stays one key away.
        if let intent = Intent.parse(trimmed, tools: byID) {
            let key = "intent:\(intent.name)"
            let dataTrimmed = intent.data.trimmingCharacters(in: .whitespacesAndNewlines)
            let otherwise = plain(intent.data, trimmed: dataTrimmed, tools: tools, byID: byID, ignoring: ignoring, learned: [:], limit: limit)?.actions ?? []
            let offered = intent.actions + otherwise.filter { !$0.opensTool && $0.inputOverride == nil }.map { a in
                Action(key: a.key, tool: a.tool, options: a.options, then: nil, inputOverride: intent.data, opensTool: false,
                       title: a.title, detail: a.detail, reason: a.reason, confidence: min(a.confidence, 0.5), learned: 0)
            }
            // Only remembered choices that are on offer: a remembered "md5" must not reappear for "sha256 …".
            let counts = (learned[key] ?? [:]).filter { k, _ in offered.contains { $0.key == k } }
            return Analysis(kind: .command, formatKey: key, formatName: "Instruction", confidence: 0.97,
                            actions: rank(offered, learned: counts, tools: byID, limit: limit), isSensitive: looksSecret(intent.data))
        }
        let whole = plain(text, trimmed: trimmed, tools: tools, byID: byID, ignoring: ignoring, learned: learned, limit: limit)
        // A tool's name, then data for it ("jwt eyJ…", "qr https://…"), when the text as a whole is not data.
        if whole?.kind != .data,
           let named = namedTool(trimmed, tools: tools, rest: { plain($0, trimmed: $0, tools: tools, byID: byID, ignoring: ignoring, learned: [:], limit: limit) }) {
            let key = "intent:tool"
            let offered = [named.action] + named.otherwise.filter { !$0.opensTool && $0.inputOverride == nil && $0.key != named.action.key }.map { a in
                Action(key: a.key, tool: a.tool, options: a.options, then: nil, inputOverride: named.data, opensTool: false,
                       title: a.title, detail: a.detail, reason: a.reason, confidence: min(a.confidence, 0.5), learned: 0)
            }
            let counts = (learned[key] ?? [:]).filter { k, _ in offered.contains { $0.key == k } }
            return Analysis(kind: .command, formatKey: key, formatName: "Instruction", confidence: 0.96,
                            actions: rank(offered, learned: counts, tools: byID, limit: limit), isSensitive: looksSecret(named.data))
        }
        return whole
    }

    /// Recognised data, or words (tool names, prose).
    static func plain(_ text: String, trimmed: String, tools: [AnyTool], byID: [String: AnyTool], ignoring: Set<String>,
                      learned: Learned, limit: Int) -> Analysis? {

        let usable = tools.filter { $0.io.input == .text && !$0.sideEffects && $0.kind != .pipeline }
        var report = DetectionEngine.detect(text, tools: usable, ignoring: ignoring)
        // Broken JSON is not valid JSON, so the formatter barely claims it (or not at all), yet it is the tool that
        // shows where the mistake is, and can usually mend it. Without this the best match is whatever regex fits.
        let nearMiss = "JSON with a mistake"
        var repairAction: Action?
        if looksLikeBrokenJSON(trimmed), !ignoring.contains("json.format"), let json = byID["json.format"],
           (report.results.first { $0.tool.id == "json.format" }?.score.confidence ?? 0) < 0.8 {
            report.results.removeAll { $0.tool.id == "json.format" }
            report.results.insert(DetectionResult(tool: json, score: DetectionScore(0.8, nearMiss)), at: 0)
            report.results.sort { $0.score.confidence > $1.score.confidence }
            if trimmed.utf8.count <= 1_000_000, let repaired = JSONRepair.repair(trimmed) {
                let options: OptionValues = ["inputMode": .string("repair")]
                repairAction = Action(key: key(json.id, options), tool: json, options: options, then: nil, inputOverride: nil, opensTool: false,
                                      title: "Repair JSON", detail: nil, reason: repaired.summary, confidence: 0.82, learned: 0)
            }
        }
        if let best = report.best {
            // Weak guesses (a Base64 string "could be" an identifier for the case converter) only add noise.
            // User scripts match on a regex alone, so they count as alternatives only when they are as sure as the best.
            let floor = max(0.45, best.score.confidence - 0.3)
            let strong = report.results.filter {
                $0.tool.id == best.tool.id || ($0.score.confidence >= floor && ($0.tool.kind != .script || $0.score.confidence >= best.score.confidence))
            }
            var actions: [Action] = strong.prefix(limit + 2).map { r in
                action(r.tool, options: r.score.options, reason: r.score.reason, confidence: r.score.confidence)
            }
            if best.score.reason != nearMiss { actions.insert(contentsOf: modeVariants(of: best), at: min(1, actions.count)) }
            if let repairAction { actions.insert(repairAction, at: 0) }
            let key = best.tool.id
            let sensitive = !best.tool.historyEnabledByDefault || looksSecret(trimmed)
            return Analysis(kind: .data, formatKey: key, formatName: best.score.reason, confidence: best.score.confidence,
                            actions: rank(actions, learned: learned[key] ?? [:], tools: byID, limit: limit), isSensitive: sensitive)
        }

        // Not data: words. Offer tools whose names match, then general text tools.
        var actions: [Action] = []
        if isShortPhrase(trimmed) {
            for (i, tool) in searchTools(trimmed, in: tools.filter { $0.kind != .pipeline }, limit: 4).enumerated() {
                let runnable = tool.io.input == .none
                actions.append(Action(key: "open:" + tool.id, tool: tool, options: [:], then: nil, inputOverride: runnable ? "" : nil,
                                      opensTool: !runnable, title: tool.name, detail: runnable ? nil : "Open",
                                      reason: tool.summary, confidence: 0.6 - Double(i) * 0.02, learned: 0))
            }
        }
        // A list (several short lines): say what is wrong with it, and offer the fix, before the general text tools.
        let list = listFacts(trimmed)
        if let list, let lines = byID["text.lines"], !ignoring.contains("text.lines") {
            func line(_ operation: String, _ title: String, _ reason: String, _ confidence: Double) -> Action {
                let options: OptionValues = ["operation": .string(operation)]
                return Action(key: SmartBox.key(lines.id, options), tool: lines, options: options, then: nil, inputOverride: nil, opensTool: false,
                              title: title, detail: nil, reason: reason, confidence: confidence, learned: 0)
            }
            if list.repeated > 0 {
                actions.append(line("dedupe", "Remove duplicates", list.repeated == 1 ? "1 line is repeated" : "\(list.repeated) lines are repeated", 0.58))
            }
            if !list.sorted { actions.append(line("sort", "Sort lines", "\(list.count) lines, not in order", 0.56)) }
        }
        for (i, id) in textFallbackIDs.enumerated() {
            guard let tool = byID[id], !ignoring.contains(id) else { continue }
            actions.append(action(tool, options: [:], reason: "Works on any text", confidence: 0.4 - Double(i) * 0.01))
        }
        let key = list == nil ? "words" : "lines"
        return Analysis(kind: .words, formatKey: key, formatName: actions.first?.opensTool == true ? "Tool search" : list == nil ? "Text" : "List",
                        confidence: 0.4, actions: rank(actions, learned: learned[key] ?? [:], tools: byID, limit: limit),
                        isSensitive: looksSecret(trimmed))
    }

    /// After the first step ran: if its output is itself structured data (Base64 that hides JSON), returns a
    /// chained action that runs both. `nil` when the output is not worth a second step.
    public static func chain(after action: Action, output: String, tools: [AnyTool]) -> Action? {
        guard action.then == nil, !action.opensTool, !output.isEmpty, output.utf8.count < DetectionEngine.maxInputBytes else { return nil }
        let structured: Set<String> = ["json.format", "yaml.format", "xml.format", "toml.format"]
        let candidates = tools.filter { structured.contains($0.id) }
        guard let best = DetectionEngine.detect(output, tools: candidates).best, best.score.confidence >= 0.9,
              best.tool.id != action.tool.id else { return nil }
        // Already pretty (multi-line, indented)? Then a second step adds nothing.
        if output.contains("\n  ") { return nil }
        return Action(key: action.key + ">" + best.tool.id, tool: action.tool, options: action.options,
                      then: Step(tool: best.tool, options: best.score.options), inputOverride: nil, opensTool: false,
                      title: "\(action.title) → \(best.tool.name)", detail: nil,
                      reason: "Then \(best.tool.name) on the result", confidence: action.confidence + 0.001, learned: 0)
    }

    /// Learning key for an action stored as text (`tool.id|k=v&k=v`), back to an action.
    public static func action(fromKey key: String, tools: [String: AnyTool], reason: String = "You chose this before") -> Action? {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard let first = parts.first, !first.contains(">"), !first.hasPrefix("open:"), let tool = tools[first],
              tool.io.input == .text else { return nil }
        var options: OptionValues = [:]
        if parts.count == 2 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2, let field = tool.optionFields.first(where: { $0.key == kv[0] }) else { continue }
                options[kv[0]] = OptionValue.parse(kv[1], like: field)
            }
        }
        return action(tool, options: options, reason: reason, confidence: 0.35)
    }

    // MARK: - Helpers

    static func action(_ tool: AnyTool, options: OptionValues, reason: String, confidence: Double) -> Action {
        Action(key: key(tool.id, options), tool: tool, options: options, then: nil, inputOverride: nil, opensTool: false,
               title: tool.name, detail: modeLabel(tool, options), reason: reason, confidence: confidence, learned: 0)
    }

    static func key(_ toolID: String, _ options: OptionValues) -> String {
        guard !options.isEmpty else { return toolID }
        return toolID + "|" + options.keys.sorted().map { "\($0)=\(options[$0]!.stringValue)" }.joined(separator: "&") // swiftlint:disable:this force_unwrapping
    }

    /// The label of the chosen "mode" (or first segmented field) value, e.g. "Decode".
    static func modeLabel(_ tool: AnyTool, _ options: OptionValues) -> String? {
        for field in tool.optionFields {
            guard let value = options[field.key] else { continue }
            switch field.kind {
            case .segmented(let choices), .picker(let choices):
                if field.key == "mode" || field.key == "kind" || field.key == "direction" {
                    return choices.first { $0.value == value.stringValue }?.label
                }
            default: continue
            }
        }
        return nil
    }

    /// For the best match, the other values of its mode switch ("Minify", "Validate") when detection did not pick one.
    static func modeVariants(of best: DetectionResult) -> [Action] {
        // Only formatters: their modes are different views of the same data (Format, Minify, Validate). For encoders
        // and the like the other mode is the inverse (Encode for something already encoded), which is noise.
        guard best.tool.category == .format, best.score.options["mode"] == nil,
              let field = best.tool.optionFields.first(where: { $0.key == "mode" }) else { return [] }
        let choices: [OptionChoice]
        switch field.kind {
        case .segmented(let c), .picker(let c): choices = c
        default: return []
        }
        return choices.filter { $0.value != field.defaultValue.stringValue }.prefix(2).enumerated().map { i, choice in
            var opts = best.score.options
            opts["mode"] = .string(choice.value)
            return Action(key: key(best.tool.id, opts), tool: best.tool, options: opts, then: nil, inputOverride: nil, opensTool: false,
                          title: choice.label, detail: nil, reason: "\(choice.label) with \(best.tool.name)",
                          confidence: best.score.confidence - 0.05 - Double(i) * 0.01, learned: 0)
        }
    }

    /// Orders by score (detection plus learning), adds remembered actions detection did not offer, de-duplicates.
    static func rank(_ actions: [Action], learned: [String: Int], tools: [String: AnyTool], limit: Int) -> [Action] {
        var all = actions
        for (key, _) in learned where !all.contains(where: { $0.key == key }) {
            if let a = action(fromKey: key, tools: tools) { all.append(a) }
        }
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.key).inserted }
        // Two chips that read the same ("JSON Formatter" as detected, and as remembered with other options) are one
        // choice to the person: keep the better-ranked one.
        func label(_ a: Action) -> String { a.title + "\u{1}" + (a.detail ?? "") + "\u{1}" + (a.then?.tool.id ?? "") + (a.opensTool ? "\u{1}open" : "") }
        let withLearning = unique.enumerated().map { i, a -> (Int, Action) in
            var a = a
            a.learned = learned[a.key] ?? 0
            return (i, a)
        }
        var labels = Set<String>()
        return withLearning
            .sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }
            .map(\.1)
            .filter { labels.insert(label($0)).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// Starts like JSON and has JSON's punctuation, whether or not it parses.
    static func looksLikeBrokenJSON(_ s: String) -> Bool {
        guard let first = s.first, first == "{" || first == "[" else { return false }
        let sample = s.prefix(4096)
        return sample.contains("\"") && (sample.contains(":") || sample.contains(","))
    }

    /// For text that is a list (three or more short lines): how many lines repeat an earlier one, and whether it is in order.
    static func listFacts(_ s: String) -> (count: Int, repeated: Int, sorted: Bool)? {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 3, lines.count <= 50_000, lines.allSatisfy({ $0.count <= 200 }) else { return nil }
        // Prose wrapped over lines is not a list: most list items are a few words.
        let wordy = lines.filter { $0.split(separator: " ").count > 6 }.count
        guard wordy * 4 <= lines.count else { return nil }
        let repeated = lines.count - Set(lines).count
        let sorted = zip(lines, lines.dropFirst()).allSatisfy { $0.localizedStandardCompare($1) != .orderedDescending }
        return (lines.count, repeated, sorted)
    }

    static func isShortPhrase(_ s: String) -> Bool {
        !s.contains("\n") && s.count <= 80 && s.split(separator: " ").count <= 8 && s.contains(where: \.isLetter)
    }

    /// Credentials and keys that should be marked in the UI (and never leave the Mac).
    public static func looksSecret(_ s: String) -> Bool {
        let patterns = [
            "-----BEGIN [A-Z ]*PRIVATE KEY-----", "(?i)authorization:\\s*(bearer|basic)\\s+\\S+", "\\bsk_(live|test)_[A-Za-z0-9]{6,}",
            "\\bgh[pousr]_[A-Za-z0-9]{20,}", "\\bAKIA[0-9A-Z]{16}\\b", "\\bxox[baprs]-[A-Za-z0-9-]{10,}",
            "(?i)\\b(password|passwd|secret|api[_-]?key|token)\\s*[=:]\\s*\\S{6,}", "^eyJ[\\w-]+\\.eyJ[\\w-]+\\.[\\w-]*$",
        ]
        let sample = String(s.prefix(16_384))
        return patterns.contains { sample.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: - Typed commands

    /// Short commands for tools that make something rather than read something.
    public struct Command: Sendable {
        public let name: String
        public let actions: [Action]

        public static func parse(_ text: String, tools: [String: AnyTool]) -> Command? {
            let s = text.lowercased().trimmingCharacters(in: .whitespaces)
            guard s.count <= 40, !s.contains("\n") else { return nil }
            // `input` nil = run on the typed text itself (generators ignore it, and a session skips empty input).
            func make(_ id: String, _ options: OptionValues, title: String, detail: String? = nil, input: String? = nil, reason: String,
                      confidence: Double = 0.95) -> Action? {
                guard let tool = tools[id] else { return nil }
                return Action(key: key(id, options), tool: tool, options: options, then: nil, inputOverride: input, opensTool: false,
                              title: title, detail: detail, reason: reason, confidence: confidence, learned: 0)
            }
            func count(_ m: String?) -> Int { m.flatMap(Int.init).map { max(1, min($0, 1000)) } ?? 1 }

            // "uuid", "3 uuids", "uuid v7", "5 ulid", "nanoid"
            if let m = s.wholeMatch(of: /(\d{1,4})?\s*(uuid|guid|ulid|nano ?id|objectid)s?\s*(?:v?([1-7]))?/) {
                let n = count(m.1.map(String.init))
                let word = String(m.2).replacingOccurrences(of: " ", with: "")
                let kind: String
                switch word {
                case "ulid": kind = "ulid"
                case "nanoid": kind = "nanoid"
                case "objectid": kind = "objectid"
                default: kind = ["1", "7"].contains(m.3.map(String.init) ?? "") ? "uuid\(m.3!)" : "uuid4" // swiftlint:disable:this force_unwrapping
                }
                let other = kind == "uuid7" ? "uuid4" : "uuid7"
                let label = kind.hasPrefix("uuid") ? "UUID v\(kind.dropFirst(4))" : (kind == "ulid" ? "ULID" : kind == "nanoid" ? "Nano ID" : "ObjectId")
                let first = make("id.generate", ["mode": .string("generate"), "kind": .string(kind), "count": .int(n)],
                                 title: n == 1 ? label : "\(n) × \(label)", reason: "Generate \(n == 1 ? "an identifier" : "\(n) identifiers")")
                let alt = kind.hasPrefix("uuid") ? make("id.generate", ["mode": .string("generate"), "kind": .string(other), "count": .int(n)],
                                                        title: "UUID v\(other.dropFirst(4)) instead", reason: "Another version", confidence: 0.9) : nil
                return Command(name: "id", actions: [first, alt].compactMap { $0 })
            }
            // "password", "password 32", "3 passwords", "passphrase", "pin", "hex 32"
            if let m = s.wholeMatch(of: /(\d{1,3})?\s*(password|passphrase|pin|hex|token|secret)s?\s*(\d{1,4})?/) {
                let howMany = count(m.1.map(String.init))
                let word = String(m.2), n = m.3.flatMap { Int($0) }
                var opts: OptionValues
                switch word {
                case "passphrase": opts = ["kind": .string("passphrase")]; if let n { opts["words"] = .int(min(max(n, 2), 20)) }
                case "pin": opts = ["kind": .string("pin")]; opts["length"] = .int(n ?? 6)
                case "hex", "token", "secret": opts = ["kind": .string("hex")]; opts["bytes"] = .int(n ?? 32)
                default: opts = ["kind": .string("password")]; if let n { opts["length"] = .int(min(max(n, 4), 1024)) }
                }
                opts["count"] = .int(min(howMany, 100))
                let first = make("random.string", opts, title: howMany == 1 ? word.capitalized : "\(howMany) × \(word.capitalized)",
                                 reason: "Generate a random \(word)")
                let alt = word == "password" ? make("random.string", ["kind": .string("passphrase"), "count": .int(min(howMany, 100))], title: "Passphrase instead",
                                                    reason: "Easier to type", confidence: 0.9) : nil
                return Command(name: "random", actions: [first, alt].compactMap { $0 })
            }
            // "now", "today", "time", "timestamp"
            if ["now", "today", "time", "timestamp", "date", "epoch", "unix", "unix time", "unix now", "current time", "time now", "timestamp now"].contains(s) {
                return make("time.unix", [:], title: "Current time", input: "now", reason: "The time right now in every format")
                    .map { Command(name: "now", actions: [$0]) }
            }
            // A date in words: "tomorrow 9am", "next friday", "15 March 2024 at 10:30".
            if s.contains(where: \.isLetter), s.contains(" ") || ["tomorrow", "yesterday", "tonight", "noon", "midnight"].contains(s),
               let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = detector.firstMatch(in: text, range: range), match.range == range, match.date != nil {
                    return make("time.unix", [:], title: "Date & time", reason: "A date in words, in every format").map { Command(name: "date", actions: [$0]) }
                }
            }
            // "lorem", "lorem 3", "lorem 5 sentences"
            if let m = s.wholeMatch(of: /lorem(?:\s+ipsum)?\s*(\d{1,3})?\s*(paragraphs?|sentences?|words?)?/) {
                let unit = m.2.map { $0.hasPrefix("s") ? "sentences" : $0.hasPrefix("w") ? "words" : "paragraphs" } ?? "paragraphs"
                let n = m.1.flatMap { Int($0) } ?? 1
                return make("lorem.ipsum", ["unit": .string(unit), "count": .int(n)], title: "Lorem ipsum", detail: "\(n) \(unit)",
                            reason: "Placeholder text").map { Command(name: "lorem", actions: [$0]) }
            }
            return nil
        }
    }
}
