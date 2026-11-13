import AppIntents
import Foundation
import BitlatheCore
import BitlatheTools

// App Intents: shared runtime, entities and option parsing. Intents run headless (no window),
// using the same tools, detection and pipeline engines as the app, CLI and URL scheme.

struct BitlatheIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

enum IntentRuntime {
    /// All tools (native, scripts, pipelines). Populates the shared registry exactly like the app does,
    /// so intents work when the app was launched by Shortcuts with no UI.
    @MainActor
    static func allTools() -> [AnyTool] {
        let registry = ToolRegistry.shared
        if registry.tools.isEmpty { ToolCatalog.registerAll(in: registry) }
        return registry.tools
    }

    static func tool(id: String) async throws -> AnyTool {
        let found = await MainActor.run { () -> AnyTool? in
            _ = allTools()
            return ToolRegistry.shared.tool(id)
        }
        guard let found else { throw BitlatheIntentError("Unknown tool \"\(id)\". Open Bitlathe to check that it is still installed.") }
        return found
    }

    static func run(toolID: String, input: ToolInput, options: OptionValues = [:]) async throws -> ToolOutput {
        let tool = try await tool(id: toolID)
        return try await run(tool: tool, input: input, options: options)
    }

    static func run(tool: AnyTool, input: ToolInput, options: OptionValues) async throws -> ToolOutput {
        // Fill in defaults so partial option sets behave like the app.
        var merged = tool.optionFields.defaults
        for (k, v) in options { merged[k] = v }
        do {
            return try await tool.run(input, options: merged)
        } catch let e as ToolError {
            var msg = "\(tool.name): \(e.description)"
            if let hint = e.hint { msg += ". \(hint)" }
            throw BitlatheIntentError(msg)
        } catch {
            throw BitlatheIntentError("\(tool.name): \(error.localizedDescription)")
        }
    }

    /// Text of an output, or an error when it is binary (use the file variants).
    static func text(of output: ToolOutput, toolName: String) throws -> String {
        if let t = output.payload.text { return t }
        throw BitlatheIntentError("\(toolName) produced \(output.payload.kindName) output. Use \"Run Tool (File)\" to receive it as a file.")
    }

    static func input(text: String, file: IntentFile?) -> ToolInput {
        if let file {
            let d = file.data
            let name = file.filename
            if let f = ImageFormat.sniff(d), f != .svg { return ToolInput(.image(d, f), fileName: name) }
            if let s = String(data: d, encoding: .utf8) { return ToolInput(.text(s), fileName: name) }
            return ToolInput(.data(d), fileName: name)
        }
        return ToolInput(text: text)
    }

    static func file(from output: ToolOutput, fallbackName: String) throws -> IntentFile {
        switch output.payload {
        case .image(let d, let f):
            return IntentFile(data: d, filename: output.suggestedFileName ?? "\(fallbackName).\(f.fileExtension)", type: nil)
        case .data(let d):
            return IntentFile(data: d, filename: output.suggestedFileName ?? "\(fallbackName).bin", type: nil)
        case .file(let url):
            return IntentFile(fileURL: url)
        case .text(let s):
            return IntentFile(data: Data(s.utf8), filename: output.suggestedFileName ?? "\(fallbackName).txt", type: .plainText)
        case .none:
            throw BitlatheIntentError("\(fallbackName) produced no output.")
        }
    }

    /// Parse options given as a JSON object or `key=value` lines (also `key: value`, `#` comments).
    static func parseOptions(_ raw: String?, for tool: AnyTool) throws -> OptionValues {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return [:] }
        var out: OptionValues = [:]
        func field(_ key: String) -> OptionField? { tool.optionFields.first { $0.key == key } }
        if raw.hasPrefix("{") {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else {
                throw BitlatheIntentError("Options are not valid JSON. Use {\"key\": value} or key=value lines.")
            }
            for (k, v) in obj {
                guard let f = field(k) else { throw unknownKey(k, tool) }
                switch v {
                case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): out[k] = .bool(n.boolValue)
                case let n as NSNumber: out[k] = OptionValue.parse(n.stringValue, like: f)
                case let s as String: out[k] = OptionValue.parse(s, like: f)
                default: throw BitlatheIntentError("Option \"\(k)\" must be a string, number or boolean.")
                }
            }
            return out
        }
        for line in raw.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") { continue }
            guard let sep = l.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
                throw BitlatheIntentError("Cannot read option line \"\(l)\". Use key=value.")
            }
            let k = String(l[..<sep]).trimmingCharacters(in: .whitespaces)
            let v = String(l[l.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
            guard let f = field(k) else { throw unknownKey(k, tool) }
            out[k] = OptionValue.parse(v, like: f)
        }
        return out
    }

    private static func unknownKey(_ k: String, _ tool: AnyTool) -> BitlatheIntentError {
        let keys = tool.optionFields.map(\.key).joined(separator: ", ")
        return BitlatheIntentError("\(tool.name) has no option \"\(k)\"." + (keys.isEmpty ? " It takes no options." : " Available: \(keys)."))
    }
}

// MARK: - Entities

struct ToolEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tool")
    static let defaultQuery = ToolEntityQuery()

    var id: String
    @Property(title: "Name") var name: String
    @Property(title: "Summary") var summary: String
    @Property(title: "Category") var category: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }

    init(_ tool: AnyTool) {
        id = tool.id
        name = tool.name
        summary = tool.summary
        category = tool.category.title
    }
}

struct ToolEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ToolEntity] {
        await MainActor.run {
            let all = IntentRuntime.allTools()
            return identifiers.compactMap { id in all.first { $0.id == id }.map(ToolEntity.init) }
        }
    }

    func entities(matching string: String) async throws -> [ToolEntity] {
        await MainActor.run {
            _ = IntentRuntime.allTools()
            return ToolRegistry.shared.search(string, limit: 25).map(ToolEntity.init)
        }
    }

    func suggestedEntities() async throws -> [ToolEntity] {
        await MainActor.run { IntentRuntime.allTools().map(ToolEntity.init) }
    }
}

struct PipelineEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pipeline")
    static let defaultQuery = PipelineEntityQuery()

    var id: UUID
    @Property(title: "Name") var name: String
    @Property(title: "Steps") var expression: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(expression)")
    }

    init(_ p: Pipeline) {
        id = p.id
        name = p.name
        expression = p.expression
    }
}

struct PipelineEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PipelineEntity] {
        try await DataStore.shared.pipelines().filter { identifiers.contains($0.id) }.map(PipelineEntity.init)
    }

    func entities(matching string: String) async throws -> [PipelineEntity] {
        let q = string.lowercased()
        return try await DataStore.shared.pipelines()
            .filter { $0.name.lowercased().contains(q) || $0.expression.lowercased().contains(q) }
            .map(PipelineEntity.init)
    }

    func suggestedEntities() async throws -> [PipelineEntity] {
        try await DataStore.shared.pipelines().map(PipelineEntity.init)
    }
}
