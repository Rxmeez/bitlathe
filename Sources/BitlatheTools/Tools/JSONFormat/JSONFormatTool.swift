import Foundation
import BitlatheCore

public struct JSONFormatTool: DevTool {
    public static let id = "json.format"
    public static let name = "JSON Formatter"
    public static let summary = "Format, validate, minify and query JSON, JSONC and JSON5"
    public static let category = ToolCategory.format
    public static let symbol = "curlybraces"
    public static let keywords = ["json", "pretty", "beautify", "minify", "validate", "jsonpath", "jq", "schema", "json5", "jsonc", "tree"]
    public static let io = ToolIO.text(.json, .json)
    public static let samples = [
        ToolSample("Messy object", #"{"name":"Bitlathe","version":1.0,"tags":["mac","dev"],"nested":{"ok":true,"count":null}}"#),
        ToolSample("JSON5 with comments", "// config\n{\n  unquoted: 'single',\n  trailing: [1, 2, 3,],\n  hex: 0xFF,\n}", options: ["inputMode": .string("json5")]),
        ToolSample("Broken JSON", #"{"a": 1, "b": [1, 2,], "c": tru}"#),
    ]
    public static let optionFields: [OptionField] = [
        .segmented("mode", "Mode", [.init("format", "Format"), .init("minify", "Minify"), .init("validate", "Validate")], default: "format"),
        .picker("indent", "Indent", [.init("2", "2 spaces"), .init("4", "4 spaces"), .init("tab", "Tab")], default: "2", visibleWhen: ("mode", ["format"])),
        .toggle("sortKeys", "Sort keys"),
        .picker("inputMode", "Input", [.init("json", "JSON"), .init("jsonc", "JSONC"), .init("json5", "JSON5"), .init("repair", "Repair")], default: "json", help: "JSONC allows comments and trailing commas; JSON5 also allows unquoted keys, single quotes and hex numbers; Repair mends broken JSON (missing commas, unclosed brackets, cut-off text) and lists what it changed"),
        .toggle("escapeNonASCII", "Escape non-ASCII", advanced: true),
        .toggle("escapeSlashes", "Escape slashes", advanced: true),
        .text("query", "Query", placeholder: "$.items[*].id or .items[].id", help: "JSONPath or jq-style path", advanced: true),
        .multiline("schema", "JSON Schema", placeholder: "Paste a JSON Schema to validate against"),
    ]

    public struct Options: ToolOptions {
        public var mode = "format"
        public var indent = "2"
        public var sortKeys = false
        public var inputMode = "json"
        public var escapeNonASCII = false
        public var escapeSlashes = false
        public var query = ""
        public var schema = ""
        public init() {}
    }

    public init() {}

    public static func parserOptions(_ mode: String) -> JSONParser.Options {
        switch mode {
        case "json5": .json5
        case "jsonc": .jsonc
        default: .strict
        }
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        var value: JSONValue
        var metadata: [MetaRow] = []
        var warnings: [String] = []
        do {
            value = try JSONParser.parse(text, options: Self.parserOptions(options.inputMode))
        } catch let e as ToolError {
            if options.inputMode == "repair", let repaired = JSONRepair.repair(text), let mended = try? JSONParser.parse(repaired.json) {
                value = mended
                warnings.append("Repaired: " + repaired.fixes.joined(separator: ", ") + ". Check the result against the original.")
                metadata.append(MetaRow("Repairs", "\(repaired.fixes.count)", style: .warning))
            } else {
                var e2 = e
                if options.inputMode == "json", (try? JSONParser.parse(text, options: .json5)) != nil {
                    e2.hint = (e.hint ?? "") + (e.hint == nil ? "" : " · ") + "This parses as JSON5 — switch the input mode"
                } else if options.inputMode != "repair", JSONRepair.repair(text) != nil {
                    e2.hint = (e.hint ?? "") + (e.hint == nil ? "" : " · ") + "Set Input to Repair to mend it"
                }
                throw e2
            }
        }
        try Task.checkpoint()

        if !options.query.trimmed().isEmpty {
            let results = try JSONPath.evaluate(options.query, in: value)
            metadata.append(MetaRow("Matches", "\(results.count)"))
            value = results.count == 1 ? results[0] : .array(results)
        }

        var isValid = true
        if !options.schema.trimmed().isEmpty {
            let schema: JSONValue
            do { schema = try JSONParser.parse(options.schema, options: .json5) } catch let e as ToolError {
                throw ToolError("Schema: " + e.message, hint: "The JSON Schema itself does not parse")
            }
            let issues = JSONSchemaValidator.validate(value, against: schema)
            isValid = issues.isEmpty
            for i in issues.prefix(50) { warnings.append("\(i.path): \(i.message)") }
            metadata.append(MetaRow("Schema", issues.isEmpty ? "Valid" : "\(issues.count) issue\(issues.count == 1 ? "" : "s")", style: issues.isEmpty ? .success : .danger))
        }

        metadata.append(MetaRow("Type", value.typeName))
        metadata.append(MetaRow("Depth", "\(Self.depth(value))"))
        switch value {
        case .object(let o): metadata.append(MetaRow("Keys", "\(o.count)"))
        case .array(let a): metadata.append(MetaRow("Items", "\(a.count)"))
        default: break
        }

        var ser = JSONSerializerOptions()
        ser.sortKeys = options.sortKeys
        ser.escapeNonASCII = options.escapeNonASCII
        ser.escapeSlashes = options.escapeSlashes
        switch options.mode {
        case "minify":
            ser.indent = 0
        case "validate":
            return ToolOutput(text: text, language: .json, metadata: metadata, warnings: warnings, isValid: isValid)
        default:
            if options.indent == "tab" { ser.useTabs = true; ser.indent = 1 } else { ser.indent = Int(options.indent) ?? 2 }
        }
        let out = try JSONSerializer.stringCancellable(value, options: ser)
        return ToolOutput(text: out, language: .json, metadata: metadata, warnings: warnings, isValid: isValid)
    }

    static func depth(_ v: JSONValue) -> Int {
        switch v {
        case .array(let a): 1 + (a.map(depth).max() ?? 0)
        case .object(let o): 1 + (o.map { depth($0.value) }.max() ?? 0)
        default: 0
        }
    }

    public static func detect(_ sample: String) -> DetectionScore? {
        guard let f = sample.first, f == "{" || f == "[" else { return nil }
        if (try? JSONParser.parse(sample)) != nil { return DetectionScore(0.95, "Valid JSON") }
        if (try? JSONParser.parse(sample, options: .json5)) != nil { return DetectionScore(0.85, "Valid JSON5", options: ["inputMode": .string("json5")]) }
        if Detect.looksLikeJSON(sample) { return DetectionScore(0.55, "Looks like JSON with errors") }
        // The detection engine only shows tools the first 64 KB, so a large document arrives cut off mid-way and can
        // never parse or end in a closing bracket. Accept it when the visible part starts like JSON.
        if sample.utf8.count >= DetectionEngine.sampleLimit - 4 {
            let body = sample.dropFirst().drop { $0.isWhitespace }
            if let next = body.first, f == "{" ? (next == "\"" || next == "}") : "\"{[-0123456789tfn]".contains(next) {
                return DetectionScore(0.6, "Large JSON document")
            }
        }
        return nil
    }
}
