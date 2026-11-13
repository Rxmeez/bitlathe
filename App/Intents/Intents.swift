import AppIntents
import Foundation
import BitlatheCore
import BitlatheTools

// MARK: - Generic intents

struct RunToolIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Tool"
    static let description = IntentDescription("Run any Bitlathe tool on text and get the text result.", categoryName: "Tools")
    static let openAppWhenRun = false

    @Parameter(title: "Tool") var tool: ToolEntity
    @Parameter(title: "Input") var input: String
    @Parameter(title: "File", description: "Use a file instead of the text input (images, binary files).") var file: IntentFile?
    @Parameter(title: "Options", description: "JSON object or key=value lines, e.g. mode=decode") var options: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$tool) on \(\.$input)") {
            \.$file
            \.$options
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let t = try await IntentRuntime.tool(id: tool.id)
        let opts = try IntentRuntime.parseOptions(options, for: t)
        let out = try await IntentRuntime.run(tool: t, input: IntentRuntime.input(text: input, file: file), options: opts)
        return .result(value: try IntentRuntime.text(of: out, toolName: t.name))
    }
}

struct RunToolFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Tool (File)"
    static let description = IntentDescription("Run a Bitlathe tool and get the result as a file, for images and binary output.", categoryName: "Tools")
    static let openAppWhenRun = false

    @Parameter(title: "Tool") var tool: ToolEntity
    @Parameter(title: "File") var file: IntentFile?
    @Parameter(title: "Text Input") var input: String?
    @Parameter(title: "Options", description: "JSON object or key=value lines, e.g. format=png") var options: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$tool) on \(\.$file)") {
            \.$input
            \.$options
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let t = try await IntentRuntime.tool(id: tool.id)
        let opts = try IntentRuntime.parseOptions(options, for: t)
        guard file != nil || !(input ?? "").isEmpty else { throw BitlatheIntentError("Provide a file or text input.") }
        let out = try await IntentRuntime.run(tool: t, input: IntentRuntime.input(text: input ?? "", file: file), options: opts)
        return .result(value: try IntentRuntime.file(from: out, fallbackName: t.id.replacingOccurrences(of: ".", with: "-")))
    }
}

struct RunPipelineIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Pipeline"
    static let description = IntentDescription("Run one of your saved Bitlathe pipelines on some text.", categoryName: "Tools")
    static let openAppWhenRun = false

    @Parameter(title: "Pipeline") var pipeline: PipelineEntity
    @Parameter(title: "Input") var input: String

    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$pipeline) on \(\.$input)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let p = try await DataStore.shared.pipelines().first(where: { $0.id == pipeline.id }) else {
            throw BitlatheIntentError("Pipeline \"\(pipeline.name)\" no longer exists.")
        }
        let tools = await MainActor.run { () -> [String: AnyTool] in
            Dictionary(IntentRuntime.allTools().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        let run = await PipelineEngine.run(p, input: ToolInput(text: input), tools: { tools[$0] })
        if let e = run.error { throw BitlatheIntentError("Pipeline \"\(p.name)\": \(e.description)") }
        guard let out = run.finalOutput else { throw BitlatheIntentError("Pipeline \"\(p.name)\" produced no output.") }
        return .result(value: try IntentRuntime.text(of: out, toolName: p.name))
    }
}

struct DetectIntent: AppIntent {
    static let title: LocalizedStringResource = "Detect and Process"
    static let description = IntentDescription("Detect what some text is (JSON, JWT, Base64, timestamp, ...) and run the best matching tool.", categoryName: "Tools")
    static let openAppWhenRun = false

    @Parameter(title: "Input") var input: String

    static var parameterSummary: some ParameterSummary { Summary("Detect and process \(\.$input)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let tools = await MainActor.run { IntentRuntime.allTools() }
        let report = DetectionEngine.detect(input, tools: tools)
        guard let best = report.best else { throw BitlatheIntentError("Could not detect what this input is.") }
        let out = try await IntentRuntime.run(tool: best.tool, input: ToolInput(text: input), options: [:])
        let text = try IntentRuntime.text(of: out, toolName: best.tool.name)
        return .result(value: text, dialog: "Detected \(best.tool.name)")
    }
}

// MARK: - Option enums

enum JSONFormatMode: String, AppEnum {
    case format, minify, validate
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "JSON Mode")
    static let caseDisplayRepresentations: [JSONFormatMode: DisplayRepresentation] = [
        .format: "Format", .minify: "Minify", .validate: "Validate",
    ]
}

enum JSONIndent: String, AppEnum {
    case two = "2", four = "4", tab
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Indent")
    static let caseDisplayRepresentations: [JSONIndent: DisplayRepresentation] = [
        .two: "2 spaces", .four: "4 spaces", .tab: "Tab",
    ]
}

enum Base64Variant: String, AppEnum {
    case standard, url
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Base64 Alphabet")
    static let caseDisplayRepresentations: [Base64Variant: DisplayRepresentation] = [
        .standard: "Standard", .url: "URL-safe",
    ]
}

enum UUIDKind: String, AppEnum {
    case uuid4, uuid7, ulid, nanoid
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "ID Kind")
    static let caseDisplayRepresentations: [UUIDKind: DisplayRepresentation] = [
        .uuid4: "UUID v4 (random)", .uuid7: "UUID v7 (time-ordered)", .ulid: "ULID", .nanoid: "Nano ID",
    ]
}

// MARK: - Convenience intents

struct FormatJSONIntent: AppIntent {
    static let title: LocalizedStringResource = "Format JSON"
    static let description = IntentDescription("Pretty-print, minify or validate JSON (JSONC and JSON5 accepted).", categoryName: "Tools")
    static let openAppWhenRun = false

    @Parameter(title: "JSON") var json: String
    @Parameter(title: "Mode", default: .format) var mode: JSONFormatMode
    @Parameter(title: "Indent", default: .two) var indent: JSONIndent
    @Parameter(title: "Sort Keys", default: false) var sortKeys: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Format \(\.$json)") {
            \.$mode
            \.$indent
            \.$sortKeys
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let out = try await IntentRuntime.run(toolID: "json.format", input: ToolInput(text: json), options: [
            "mode": .string(mode.rawValue), "indent": .string(indent.rawValue),
            "sortKeys": .bool(sortKeys), "inputMode": .string("json5"),
        ])
        if mode == .validate, out.isValid == false {
            throw BitlatheIntentError(out.text.isEmpty ? "Invalid JSON" : out.text)
        }
        return .result(value: try IntentRuntime.text(of: out, toolName: "JSON Formatter"))
    }
}

struct DecodeBase64Intent: AppIntent {
    static let title: LocalizedStringResource = "Decode Base64"
    static let description = IntentDescription("Decode a Base64 string (standard or URL-safe) to text.", categoryName: "Tools")
    static let openAppWhenRun = false

    @Parameter(title: "Base64") var text: String
    @Parameter(title: "Alphabet", default: .standard) var variant: Base64Variant

    static var parameterSummary: some ParameterSummary { Summary("Decode Base64 \(\.$text)") { \.$variant } }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let out = try await IntentRuntime.run(toolID: "base64.text", input: ToolInput(text: text),
                                              options: ["mode": .string("decode"), "variant": .string(variant.rawValue)])
        return .result(value: try IntentRuntime.text(of: out, toolName: "Base64"))
    }
}

struct DecodeJWTIntent: AppIntent {
    static let title: LocalizedStringResource = "Decode JWT"
    static let description = IntentDescription("Decode a JSON Web Token and show its header, claims and expiry. Optionally verify an HMAC signature.", categoryName: "Tools")
    static let openAppWhenRun = false

    @Parameter(title: "Token") var token: String
    @Parameter(title: "Secret", description: "HMAC secret to verify HS256/384/512 tokens.") var secret: String?

    static var parameterSummary: some ParameterSummary { Summary("Decode JWT \(\.$token)") { \.$secret } }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var opts: OptionValues = ["mode": .string("decode")]
        if let secret, !secret.isEmpty { opts["secret"] = .string(secret) }
        let out = try await IntentRuntime.run(toolID: "jwt.debug", input: ToolInput(text: token), options: opts)
        return .result(value: try IntentRuntime.text(of: out, toolName: "JWT Debugger"))
    }
}

struct ConvertUnixTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Convert Unix Time"
    static let description = IntentDescription("Convert a Unix timestamp (s, ms, us, ns), ISO 8601 date or \"now\" to readable dates.", categoryName: "Tools")
    static let openAppWhenRun = false

    @Parameter(title: "Timestamp or Date", default: "now") var value: String
    @Parameter(title: "Time Zone", description: "IANA identifier such as Europe/London. Blank uses the system zone.") var timeZone: String?

    static var parameterSummary: some ParameterSummary { Summary("Convert \(\.$value)") { \.$timeZone } }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var opts: OptionValues = [:]
        if let timeZone, !timeZone.isEmpty { opts["timeZone"] = .string(timeZone) }
        let out = try await IntentRuntime.run(toolID: "time.unix", input: ToolInput(text: value), options: opts)
        return .result(value: try IntentRuntime.text(of: out, toolName: "Unix Time"))
    }
}

struct GenerateUUIDIntent: AppIntent {
    static let title: LocalizedStringResource = "Generate UUID"
    static let description = IntentDescription("Generate UUIDs, ULIDs or Nano IDs, one per line.", categoryName: "Tools")
    static let openAppWhenRun = false

    @Parameter(title: "Kind", default: .uuid4) var kind: UUIDKind
    @Parameter(title: "Count", default: 1, inclusiveRange: (1, 1000)) var count: Int
    @Parameter(title: "Uppercase", default: false) var uppercase: Bool

    static var parameterSummary: some ParameterSummary { Summary("Generate \(\.$count) \(\.$kind)") { \.$uppercase } }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let out = try await IntentRuntime.run(toolID: "id.generate", input: ToolInput(text: ""), options: [
            "mode": .string("generate"), "kind": .string(kind.rawValue), "count": .int(count), "uppercase": .bool(uppercase),
        ])
        return .result(value: try IntentRuntime.text(of: out, toolName: "ID Generator"))
    }
}

// MARK: - Shortcuts provider

struct BitlatheShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FormatJSONIntent(), phrases: ["Format JSON with \(.applicationName)", "Pretty print JSON in \(.applicationName)"],
                    shortTitle: "Format JSON", systemImageName: "curlybraces")
        AppShortcut(intent: DecodeBase64Intent(), phrases: ["Decode Base64 with \(.applicationName)"],
                    shortTitle: "Decode Base64", systemImageName: "b.square")
        AppShortcut(intent: DecodeJWTIntent(), phrases: ["Decode a JWT with \(.applicationName)"],
                    shortTitle: "Decode JWT", systemImageName: "key.horizontal")
        AppShortcut(intent: ConvertUnixTimeIntent(), phrases: ["Convert Unix time with \(.applicationName)", "Convert a timestamp with \(.applicationName)"],
                    shortTitle: "Convert Unix Time", systemImageName: "clock")
        AppShortcut(intent: GenerateUUIDIntent(), phrases: ["Generate a UUID with \(.applicationName)"],
                    shortTitle: "Generate UUID", systemImageName: "number.square")
        AppShortcut(intent: DetectIntent(), phrases: ["Detect and process text with \(.applicationName)"],
                    shortTitle: "Detect and Process", systemImageName: "wand.and.stars")
        AppShortcut(intent: RunToolIntent(), phrases: ["Run a tool with \(.applicationName)"],
                    shortTitle: "Run Tool", systemImageName: "hammer")
        AppShortcut(intent: RunPipelineIntent(), phrases: ["Run a pipeline with \(.applicationName)"],
                    shortTitle: "Run Pipeline", systemImageName: "point.3.connected.trianglepath.dotted")
    }
}
