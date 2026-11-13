import Foundation

/// Typed instructions: a short phrase saying what to do, then the data to do it to.
/// `sha256 hello`, `to yaml {"a":1}`, `base64 encode hi`, `minify <json>`, or the phrase on its own first line.
/// Rules, not a model: the same text always gives the same action, and nothing leaves the Mac.
extension SmartBox {

    public struct Intent: Sendable {
        /// Bucket for learning ("hash", "case", "convert:yaml").
        public let name: String
        /// The data the instruction applies to (the text after the phrase).
        public let data: String
        public let actions: [Action]

        /// One phrase the parser understands.
        struct Phrase: Sendable {
            let words: String
            let name: String
            /// English words that also start ordinary sentences ("sort", "title"): these need `sort: …` or the
            /// data on the next line, so pasted prose is never mistaken for an instruction.
            let needsSeparator: Bool
            let resolve: @Sendable (_ data: String, _ tools: [String: AnyTool]) -> (tool: AnyTool, options: OptionValues, title: String)?
        }

        public static func parse(_ text: String, tools: [String: AnyTool]) -> Intent? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // The instruction is on the first line; only that much is lowercased and scanned.
            let firstLine = trimmed.prefix { $0 != "\n" }
            guard firstLine.count >= 3 else { return nil }
            let head = String(firstLine.prefix(48)).lowercased()

            for phrase in phrases where head.hasPrefix(phrase.words) {
                let afterPhrase = trimmed.index(trimmed.startIndex, offsetBy: phrase.words.count)
                var rest = trimmed[afterPhrase...]
                guard let next = rest.first else { continue }         // phrase alone: a tool search, not an instruction
                var separated = false
                if next == ":" { rest = rest.dropFirst(); separated = true }
                else if next == "\n" { separated = true }
                else if !next.isWhitespace { continue }               // "sha256sum", "sorted": a longer word
                let afterSpaces = rest.drop(while: { $0 == " " || $0 == "\t" })
                if !separated, afterSpaces.first == ":" { rest = afterSpaces.dropFirst(); separated = true }
                if !separated, afterSpaces.first == "\n" { separated = true }
                // "md5 of hello", "sha256 for this: …": the linking word is not part of the data. Only for phrases that
                // are unmistakable anyway; "title of the next release" is a sentence.
                var data = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                if !phrase.needsSeparator || separated {
                    for link in ["of ", "for ", "this ", "the following ", "it "] where data.lowercased().hasPrefix(link) {
                        data = String(data.dropFirst(link.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if data.hasPrefix(":") { data = String(data.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                }
                // No sentence goes on with a bracket or a quote: `format {"a":1}` is an instruction without a colon.
                if let first = data.first, "{[<\"'".contains(first) { separated = true }
                if phrase.needsSeparator && !separated { continue }
                guard !data.isEmpty, let r = phrase.resolve(data, tools) else { continue }
                let preview = data.count > 28 ? data.prefix(28).replacingOccurrences(of: "\n", with: " ") + "…" : data.replacingOccurrences(of: "\n", with: " ")
                let action = Action(key: SmartBox.key(r.tool.id, r.options), tool: r.tool, options: r.options, then: nil,
                                    inputOverride: data, opensTool: false, title: r.title, detail: nil,
                                    reason: "You asked for it: runs on “\(preview)”", confidence: 0.97, learned: 0)
                return Intent(name: phrase.name, data: data, actions: [action])
            }
            return nil
        }

        // MARK: Phrase table

        /// Longest phrases first, so "base64 decode" wins over "base64".
        static let phrases: [Phrase] = build().sorted { $0.words.count > $1.words.count }

        private static func build() -> [Phrase] {
            var out: [Phrase] = []
            func fixed(_ words: [String], name: String, tool id: String, _ options: OptionValues, title: String, separator: Bool = false) {
                for w in words {
                    out.append(Phrase(words: w, name: name, needsSeparator: separator) { _, tools in
                        tools[id].map { ($0, options, title) }
                    })
                }
            }

            // Counting
            fixed(["count words in", "count words", "word count of", "word count", "count characters in", "count characters", "character count",
                   "count chars", "length of", "count lines in", "count lines"],
                  name: "count", tool: "string.inspect", [:], title: "Count")

            // Hashes
            let hashes: [(String, [String], String)] = [
                ("md5", ["md5"], "MD5"), ("sha1", ["sha1", "sha-1"], "SHA-1"), ("sha256", ["sha256", "sha-256"], "SHA-256"),
                ("sha384", ["sha384", "sha-384"], "SHA-384"), ("sha512", ["sha512", "sha-512"], "SHA-512"),
                ("blake3", ["blake3"], "BLAKE3"), ("crc32", ["crc32"], "CRC-32"), ("keccak256", ["keccak256", "keccak-256"], "Keccak-256"),
            ]
            for (value, words, title) in hashes {
                fixed(words, name: "hash", tool: "hash.generate", ["algorithm": .string(value)], title: title)
            }
            fixed(["hash", "checksum"], name: "hash", tool: "hash.generate", [:], title: "All hashes")

            // Encoders: "<name> encode|decode", "encode|decode <name>", and the run-together forms.
            let codecs: [(String, [String], String)] = [
                ("base64.text", ["base64", "b64"], "Base64"), ("url.encode", ["url", "uri", "percent"], "URL"),
                ("hex.text", ["hex"], "Hex"), ("base32.text", ["base32"], "Base32"), ("base58.text", ["base58"], "Base58"),
                ("html.entities", ["html entities", "html"], "HTML entities"),
            ]
            for (id, names, label) in codecs {
                for n in names {
                    fixed(["\(n) encode", "encode \(n)", "\(n)encode", "to \(n)"], name: "encode", tool: id, ["mode": .string("encode")], title: "\(label) encode")
                    fixed(["\(n) decode", "decode \(n)", "\(n)decode", "from \(n)", "un\(n)"], name: "encode", tool: id, ["mode": .string("decode")], title: "\(label) decode")
                }
            }
            fixed(["base64", "b64"], name: "encode", tool: "base64.text", ["mode": .string("encode")], title: "Base64 encode")
            fixed(["encode"], name: "encode", tool: "base64.text", ["mode": .string("encode")], title: "Base64 encode", separator: true)
            // "decode <something>": what it is says how. Nothing recognisable, no instruction.
            out.append(Phrase(words: "decode", name: "encode", needsSeparator: false) { data, tools in
                let decoders = tools.values.filter { $0.io.input == .text && !$0.sideEffects && choices(of: $0, "mode").contains("decode") }
                guard let best = DetectionEngine.detect(data, tools: decoders).best else { return nil }
                var options = best.score.options
                options["mode"] = .string("decode")
                return (best.tool, options, "\(best.tool.name) · Decode")
            })
            fixed(["escape"], name: "encode", tool: "text.backslash", ["mode": .string("escape")], title: "Escape", separator: true)
            fixed(["unescape"], name: "encode", tool: "text.backslash", ["mode": .string("unescape")], title: "Unescape")

            // Case
            let cases: [(String, [String], [String], String)] = [
                ("upper", ["uppercase", "upper case", "to upper"], ["upper"], "UPPERCASE"),
                ("lower", ["lowercase", "lower case", "to lower"], ["lower"], "lowercase"),
                ("camel", ["camelcase", "camel case", "to camel"], ["camel"], "camelCase"),
                ("pascal", ["pascalcase", "pascal case", "to pascal"], ["pascal"], "PascalCase"),
                ("snake", ["snake_case", "snakecase", "snake case", "to snake"], ["snake"], "snake_case"),
                ("kebab", ["kebab-case", "kebabcase", "kebab case", "to kebab"], ["kebab"], "kebab-case"),
                ("constant", ["constant_case", "constant case", "screaming snake", "to constant"], [], "CONSTANT_CASE"),
                ("title", ["titlecase", "title case", "to title"], ["title"], "Title Case"),
                ("slug", ["slugify", "to slug"], ["slug"], "url-slug"),
            ]
            for (value, sure, ambiguous, title) in cases {
                fixed(sure, name: "case", tool: "text.case", ["target": .string(value)], title: title)
                fixed(ambiguous, name: "case", tool: "text.case", ["target": .string(value)], title: title, separator: true)
            }

            // Lines
            let lines: [(String, [String], [String], String)] = [
                ("sort", ["sort lines"], ["sort"], "Sort lines"), ("dedupe", ["dedupe", "dedup", "uniq", "unique lines", "remove duplicates"], ["unique"], "Remove duplicate lines"),
                ("reverse", ["reverse lines"], ["reverse"], "Reverse lines"), ("shuffle", ["shuffle lines"], ["shuffle"], "Shuffle lines"),
                ("trim", ["trim lines"], ["trim"], "Trim lines"), ("number", ["number lines"], [], "Number lines"),
            ]
            for (value, sure, ambiguous, title) in lines {
                fixed(sure, name: "lines", tool: "text.lines", ["operation": .string(value)], title: title)
                fixed(ambiguous, name: "lines", tool: "text.lines", ["operation": .string(value)], title: title, separator: true)
            }

            // Formatter modes: the tool comes from what the data is.
            let modes: [(String, [String], [String], String)] = [
                ("minify", ["minify", "minimise", "minimize", "compact"], [], "Minify"),
                ("format", ["prettify", "pretty print", "pretty-print", "beautify"], ["format", "pretty"], "Format"),
                ("validate", ["lint"], ["validate", "check"], "Validate"),
            ]
            for (mode, sure, ambiguous, title) in modes {
                for (words, separator) in [(sure, false), (ambiguous, true)] {
                    for w in words {
                        out.append(Phrase(words: w, name: "mode:\(mode)", needsSeparator: separator) { data, tools in
                            formatter(for: data, mode: mode, tools: tools).map { ($0, ["mode": .string(mode)], "\(title) \(shortName($0))") }
                        })
                    }
                }
            }

            // Conversions: "to yaml", "as csv", "convert to json", "yaml" is found from the tools' own direction lists.
            let targets: [(String, [String], String)] = [
                ("json", ["json"], "JSON"), ("yaml", ["yaml", "yml"], "YAML"), ("csv", ["csv"], "CSV"), ("toml", ["toml"], "TOML"),
                ("xml", ["xml"], "XML"), ("plist", ["plist", "property list"], "Property List"), ("php", ["php", "php array"], "PHP array"),
                ("query", ["query string", "querystring"], "query string"), ("html", ["html"], "HTML"), ("md", ["markdown", "md"], "Markdown"),
            ]
            for (target, names, label) in targets {
                for n in names {
                    // "to html" already means "HTML entities encode" only when said as "html encode"; a bare "to html" converts.
                    for w in ["convert to \(n)", "convert this to \(n)", "to \(n)", "as \(n)", "into \(n)"] {
                        out.removeAll { $0.words == w }
                        out.append(Phrase(words: w, name: "convert:\(target)", needsSeparator: false) { data, tools in
                            converter(for: data, to: target, tools: tools).map { ($0.0, ["direction": .string($0.1)], "To \(label)") }
                        })
                    }
                }
            }
            return out
        }

        /// The formatter that recognises `data` and has this mode ("minify" exists for JSON, not for YAML).
        static func formatter(for data: String, mode: String, tools: [String: AnyTool]) -> AnyTool? {
            let candidates = tools.values.filter { tool in
                tool.category == .format && tool.io.input == .text && choices(of: tool, "mode").contains(mode)
            }
            return DetectionEngine.detect(data, tools: candidates).best?.tool
        }

        /// The converter with a "…2<target>" direction that best recognises `data`, and that direction.
        static func converter(for data: String, to target: String, tools: [String: AnyTool]) -> (AnyTool, String)? {
            let suffix = "2" + target
            let candidates = tools.values.compactMap { tool -> (AnyTool, String)? in
                guard tool.io.input == .text, let direction = choices(of: tool, "direction").first(where: { $0.hasSuffix(suffix) }) else { return nil }
                return (tool, direction)
            }.sorted { $0.0.id < $1.0.id }
            guard candidates.count > 1 else { return candidates.first }
            // a=1&b=2 is a query string; as YAML it would be one long word.
            if data.range(of: #"^\??[^\s=&]+=[^\s&]*(&[^\s=&]+=[^\s&]*)*$"#, options: .regularExpression) != nil,
               let query = candidates.first(where: { $0.1 == "query" + suffix }) { return query }
            // Several sources convert to this target (YAML, CSV, TOML, XML → JSON): the data says which.
            let sources = ["yaml": "yaml.format", "toml": "toml.format", "xml": "xml.format", "csv": "csv.viewer", "json": "json.format",
                           "md": "markdown.preview", "html": "html.format"]
            let probes = candidates.compactMap { c -> AnyTool? in
                let source = String(c.1.dropLast(suffix.count))
                return sources[source].flatMap { tools[$0] }
            }
            if let best = DetectionEngine.detect(data, tools: probes).best,
               let source = sources.first(where: { $0.value == best.tool.id })?.key,
               let match = candidates.first(where: { $0.1 == source + suffix }) {
                return match
            }
            return candidates.first { $0.1 == "yaml" + suffix } ?? candidates.first
        }

        static func choices(of tool: AnyTool, _ key: String) -> [String] {
            guard let field = tool.optionFields.first(where: { $0.key == key }) else { return [] }
            switch field.kind {
            case .segmented(let c), .picker(let c): return c.map(\.value)
            default: return []
            }
        }

        /// "JSON Formatter" → "JSON".
        static func shortName(_ tool: AnyTool) -> String {
            tool.name.replacingOccurrences(of: " Formatter", with: "")
        }
    }

    /// "jwt eyJ…", "qr https://example.com", "cron */5 * * * *": a tool's name, then the data for it. Counted only when
    /// what follows is data (recognised as such, or one token that is not a plain word), so "time flies" stays prose.
    static func namedTool(_ trimmed: String, tools: [AnyTool], rest plainRest: (String) -> Analysis?) -> (action: Action, data: String, otherwise: [Action])? {
        guard let space = trimmed.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == ":" }) else { return nil }
        let word = trimmed[..<space].lowercased()
        var data = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespacesAndNewlines)
        if data.hasPrefix(":") { data = String(data.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard word.count >= 2, word.count <= 14, word.allSatisfy({ $0.isLetter || $0.isNumber }), !data.isEmpty, !fillerWords.contains(word) else { return nil }
        let usable = tools.filter { $0.io.input == .text && !$0.sideEffects && $0.kind == .native }
        guard let tool = ToolRegistry.search(word, in: usable, limit: 1).first,
              tool.id.lowercased().hasPrefix(word + ".")
                || tool.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(Substring(word)) else { return nil }
        let reading = plainRest(data)
        let oneToken = !data.contains(where: \.isWhitespace) && data.contains(where: { !$0.isLetter })
        guard reading?.kind == .data || oneToken else { return nil }
        let same = reading?.actions.first { $0.tool.id == tool.id && $0.then == nil }
        let options = same?.options ?? [:]
        let preview = data.count > 28 ? data.prefix(28).replacingOccurrences(of: "\n", with: " ") + "…" : data.replacingOccurrences(of: "\n", with: " ")
        let action = Action(key: key(tool.id, options), tool: tool, options: options, then: nil, inputOverride: data, opensTool: false,
                            title: tool.name, detail: modeLabel(tool, options), reason: "You named the tool: runs on “\(preview)”", confidence: 0.96, learned: 0)
        return (action, data, reading?.kind == .data ? reading?.actions ?? [] : [])
    }

    /// Filler in a request ("convert this to yaml please"): dropped before searching tools by name.
    static let fillerWords: Set<String> = ["convert", "this", "that", "it", "to", "into", "as", "a", "an", "the", "please", "me", "my", "make",
                                           "turn", "from", "of", "in", "for", "with", "and", "how", "do", "i", "can", "you", "give", "get", "show",
                                           "want", "need", "some", "text", "string", "data", "file"]

    /// Tools matching a phrase. The whole phrase first; if that finds nothing, its meaningful words, with tools that
    /// match more of them first ("convert this to yaml" → YAML ⇄ JSON, YAML Formatter).
    static func searchTools(_ phrase: String, in tools: [AnyTool], limit: Int) -> [AnyTool] {
        let whole = ToolRegistry.search(phrase, in: tools, limit: limit)
        if !whole.isEmpty { return whole }
        let all = phrase.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        // "convert … to yaml", "json to csv": a converter is wanted more than a formatter.
        let wantsConversion = !Set(all).isDisjoint(with: ["convert", "to", "into", "as", "from", "turn"])
        let words = Set(phrase.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 2 && !fillerWords.contains($0) })
        guard !words.isEmpty else { return [] }
        // Whole words of the tool's name only (no fuzzy matching), so ordinary prose does not turn into a tool search.
        var hits: [String: (tool: AnyTool, count: Int, order: Int)] = [:]
        for (order, tool) in tools.enumerated() {
            let nameWords = Set(tool.name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            let count = words.intersection(nameWords).count
            if count > 0 { hits[tool.id] = (tool, count * 2 + (wantsConversion && tool.category == .convert ? 1 : 0), order) }
        }
        return hits.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.order < $1.order }.prefix(limit).map(\.tool)
    }
}

// MARK: - Requests the rules do not understand: an on-device model picks the tool

extension SmartBox {

    /// Hands a request in plain words ("what is this timestamp in Tokyo") to a language model running on this Mac.
    /// The model never produces the result. It may only name one of the tools on a shortlist, set that tool's
    /// options, and point at the part of the person's own text that is the data; all three are checked here, and the
    /// tool then runs as it always does. A wrong pick is a wrong suggestion, never a wrong answer.
    public enum Advisor {

        public struct Query: Sendable, Equatable {
            /// The whole text in the box.
            public let text: String
            /// System instructions for the model.
            public let instructions: String
            public let prompt: String
            /// Tool ids the model may choose from.
            public let shortlist: [String]
        }

        public static let reason = "Suggested by the on-device model"
        static let shortlistSize = 14
        static let sampleLength = 400

        /// A query when the text is a request in words that nothing else understood. Nil for recognised data,
        /// commands, instructions the rules handle, long prose, and anything that looks like a secret.
        public static func query(for text: String, analysis: Analysis, tools: [AnyTool]) -> Query? {
            guard analysis.kind == .words, !analysis.isSensitive else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = String(trimmed.prefix { $0 != "\n" }).trimmingCharacters(in: .whitespaces)
            // The request is the first line: a few words, not a paragraph.
            let words = firstLine.split(separator: " ")
            guard words.count >= 2, words.count <= 16, firstLine.count <= 140, firstLine.contains(where: \.isLetter) else { return nil }
            guard !looksSecret(trimmed) else { return nil }

            let usable = tools.filter { $0.kind != .pipeline && !$0.sideEffects && ($0.io.input == .text || $0.io.input == .none) }
            let shortlist = Self.shortlist(for: firstLine, in: usable)
            guard !shortlist.isEmpty else { return nil }

            let catalogue = shortlist.map { tool -> String in
                let options = tool.optionFields.filter { !$0.advanced }.compactMap { f -> String? in
                    switch f.kind {
                    case .segmented(let c), .picker(let c): return "\(f.key)=\(c.prefix(12).map(\.value).joined(separator: "|"))"
                    case .text: return f.key == "timeZone" ? "\(f.key)=<IANA zone>" : nil
                    default: return nil
                    }
                }
                return "\(tool.id): \(tool.summary)" + (options.isEmpty ? "" : " [\(options.joined(separator: " "))]")
            }.joined(separator: "\n")
            let instructions = """
                You route a request to one tool of a developer toolbox. You do not answer the request yourself.
                Reply with exactly two lines and nothing else:
                TOOL: <tool id> <option>=<value> ...
                INPUT: <the part of the request that is the data to transform, copied exactly, or empty>
                Use only tool ids and option values from the list. Options are optional. If no tool fits, reply: TOOL: none

                Tools:
                \(catalogue)
                """
            let sample = trimmed.count > sampleLength ? String(trimmed.prefix(sampleLength)) + "…" : trimmed
            return Query(text: trimmed, instructions: instructions, prompt: "Request:\n\(sample)", shortlist: shortlist.map(\.id))
        }

        /// Tools worth showing the model: those whose name, summary or keywords share words with the request.
        /// The model's context is small, so it never sees the whole catalogue.
        static func shortlist(for request: String, in tools: [AnyTool]) -> [AnyTool] {
            let words = request.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 2 && !fillerWords.contains($0) }
            var scores: [String: (tool: AnyTool, score: Int, order: Int)] = [:]
            for (wi, word) in words.enumerated() {
                for (rank, tool) in ToolRegistry.search(word, in: tools, limit: 8).enumerated() {
                    scores[tool.id, default: (tool, 0, wi * 100 + rank)].score += 8 - rank
                }
            }
            return scores.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }.prefix(shortlistSize).map(\.tool)
        }

        /// The model's reply, checked, as an action; nil when it is not a usable pick. Unknown tools are refused,
        /// unknown options and values are dropped, and the input must be a verbatim part of the person's text.
        public static func action(fromReply reply: String, query: Query, tools: [AnyTool]) -> Action? {
            var toolLine: Substring?
            var input = ""
            for line in reply.split(separator: "\n", omittingEmptySubsequences: true) {
                let l = line.trimmingCharacters(in: .whitespaces)
                if toolLine == nil, l.uppercased().hasPrefix("TOOL:") { toolLine = l.dropFirst(5) }
                else if l.uppercased().hasPrefix("INPUT:") { input = l.dropFirst(6).trimmingCharacters(in: .whitespaces) }
            }
            guard let tokens = toolLine?.split(separator: " ", omittingEmptySubsequences: true), let first = tokens.first else { return nil }
            let id = first.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'<>.,"))
            guard query.shortlist.contains(id), let tool = tools.first(where: { $0.id == id }) else { return nil }

            var options: OptionValues = [:]
            for token in tokens.dropFirst() {
                let kv = token.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2, let field = tool.optionFields.first(where: { $0.key == kv[0] }) else { continue }
                let raw = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "`\"'<>,"))
                switch field.kind {
                case .segmented(let c), .picker(let c):
                    guard c.contains(where: { $0.value == raw }) else { continue }
                case .text, .multiline:
                    guard raw.count <= 64, !raw.contains("|") else { continue }
                case .secret: continue
                default: break
                }
                options[field.key] = OptionValue.parse(raw, like: field)
            }

            // The data is the person's own text or nothing: a model may not supply it.
            input = input.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
            let rest = query.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let data: String? = !input.isEmpty && query.text.contains(input) && input != query.text ? input : (rest.isEmpty ? nil : rest)
            let detail = modeLabel(tool, options)
            if tool.io.input == .none {
                return Action(key: key(tool.id, options), tool: tool, options: options, then: nil, inputOverride: "", opensTool: false,
                              title: tool.name, detail: detail, reason: reason, confidence: 0.9, learned: 0)
            }
            guard let data else {
                return Action(key: "open:" + tool.id, tool: tool, options: options, then: nil, inputOverride: nil, opensTool: true,
                              title: tool.name, detail: "Open", reason: reason, confidence: 0.9, learned: 0)
            }
            return Action(key: key(tool.id, options), tool: tool, options: options, then: nil, inputOverride: data, opensTool: false,
                          title: tool.name, detail: detail, reason: reason, confidence: 0.9, learned: 0)
        }
    }
}
