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
                if phrase.needsSeparator && !separated { continue }
                let data = rest.trimmingCharacters(in: .whitespacesAndNewlines)
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

            // Hashes
            let hashes: [(String, [String], String)] = [
                ("md5", ["md5"], "MD5"), ("sha1", ["sha1", "sha-1"], "SHA-1"), ("sha256", ["sha256", "sha-256"], "SHA-256"),
                ("sha384", ["sha384", "sha-384"], "SHA-384"), ("sha512", ["sha512", "sha-512"], "SHA-512"),
                ("blake3", ["blake3"], "BLAKE3"), ("crc32", ["crc32"], "CRC-32"), ("keccak256", ["keccak256", "keccak-256"], "Keccak-256"),
            ]
            for (value, words, title) in hashes {
                fixed(words, name: "hash", tool: "hash.generate", ["algorithm": .string(value)], title: title)
            }
            fixed(["hash"], name: "hash", tool: "hash.generate", [:], title: "All hashes", separator: true)

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
