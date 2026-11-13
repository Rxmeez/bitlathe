import Foundation

/// A Model Context Protocol server that gives AI agents Bitlathe's tools: exact, deterministic transformations instead
/// of a model's guess at a Base64 decode or a hash. JSON-RPC 2.0, one message per line (the MCP stdio transport).
/// Everything runs locally; nothing is sent anywhere. Pure: `bl mcp` feeds it stdin lines and prints what it returns.
public struct MCPServer: Sendable {
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let tools: [AnyTool]
    let byID: [String: AnyTool]
    let pipelines: [Pipeline]
    let version: String

    /// - Parameters:
    ///   - tools: the registry snapshot (native tools, user scripts, saved pipelines). Tools with side effects are left out.
    ///   - pipelines: saved pipelines, for `run_pipeline` by name.
    public init(tools: [AnyTool], pipelines: [Pipeline] = [], version: String) {
        self.tools = tools.filter { !$0.sideEffects }
        self.byID = Dictionary(self.tools.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.pipelines = pipelines
        self.version = version
    }

    // MARK: Transport

    /// Handles one line of JSON-RPC. Returns the response line, or nil for notifications.
    public func handle(line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else {
            return Self.encode(Self.error(id: NSNull(), code: -32700, message: "Parse error: not valid JSON"))
        }
        if let batch = object as? [Any] {   // JSON-RPC batches (older protocol versions)
            var out: [Any] = []
            for case let message as [String: Any] in batch { if let r = await respond(message) { out.append(r) } }
            return out.isEmpty ? nil : Self.encode(out)
        }
        guard let message = object as? [String: Any] else {
            return Self.encode(Self.error(id: NSNull(), code: -32600, message: "Invalid request"))
        }
        return await respond(message).map(Self.encode)
    }

    func respond(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        guard let method = message["method"] as? String else {
            return id == nil ? nil : Self.error(id: id ?? NSNull(), code: -32600, message: "Invalid request: no method")
        }
        if id == nil { return nil }   // notifications (initialized, cancelled…) need no answer
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return Self.result(id: id ?? NSNull(), [
                "protocolVersion": Self.supportedVersions.contains(asked) ? asked : Self.supportedVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "bitlathe", "title": "Bitlathe", "version": version],
                "instructions": """
                    Bitlathe is a local developer toolbox (\(tools.count) tools). Use it instead of guessing: decode/encode \
                    (Base64, URL, JWT…), format and convert (JSON, YAML, XML, CSV, SQL…), hash, time and cron, colours, \
                    diff, regex, IDs. Call `detect` or `smart_run` when unsure which tool fits; `list_tools` shows every \
                    tool's id and options; `run_tool` runs one exactly.
                    """,
            ])
        case "ping":
            return Self.result(id: id ?? NSNull(), [:])
        case "tools/list":
            return Self.result(id: id ?? NSNull(), ["tools": Self.toolDefinitions])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return Self.error(id: id ?? NSNull(), code: -32602, message: "tools/call needs a name")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            return Self.result(id: id ?? NSNull(), await call(name, args))
        default:
            return Self.error(id: id ?? NSNull(), code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: Tools offered to agents

    static var toolDefinitions: [[String: Any]] { [
        definition("detect", "Detect what some text is",
                   "Recognise text (JSON, JWT, timestamp, URL, Base64, cron, colour, curl, UUID…) and rank the Bitlathe tools that fit, with the options to use.",
                   ["input": ["type": "string", "description": "The text to recognise."]], required: ["input"]),
        definition("smart_run", "Recognise and transform text",
                   "Detect what the input is and run the best matching tool, as the Bitlathe app's Smart Box would. Also understands commands such as \"3 uuid v7\", \"password 24\" and \"now\".",
                   ["input": ["type": "string", "description": "Data or a short command."]], required: ["input"]),
        definition("run_tool", "Run one Bitlathe tool",
                   "Run a tool by id with exact options (see list_tools for ids and options). Deterministic and local.",
                   ["tool": ["type": "string", "description": "Tool id, e.g. json.format, base64.text, jwt.debug, time.unix."],
                    "input": ["type": "string", "description": "Text input. Omit for generators."],
                    "input_base64": ["type": "string", "description": "Binary input as Base64 (images, files), instead of input."],
                    "options": ["type": "object", "description": "Tool options, e.g. {\"mode\": \"decode\"}. Unknown keys are rejected."]],
                   required: ["tool"]),
        definition("list_tools", "List Bitlathe tools",
                   "Every tool with its id, summary and options (types, defaults, allowed values). Filter with query or category.",
                   ["query": ["type": "string", "description": "Fuzzy search, e.g. \"base64\" or \"jwt\"."],
                    "category": ["type": "string", "description": "format, convert, encode, inspect, generate, media or scripting."]]),
        definition("run_pipeline", "Run a chain of tools",
                   "Run tools one after another, each on the previous output. Give an expression like \"base64.text mode=decode | json.format\", or the name of a pipeline saved in Bitlathe.",
                   ["expression": ["type": "string"], "pipeline": ["type": "string", "description": "Saved pipeline name or slug."],
                    "input": ["type": "string"]], required: ["input"]),
    ] }

    static func definition(_ name: String, _ title: String, _ description: String, _ properties: [String: Any],
                           required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "title": title, "description": description, "inputSchema": schema,
                "annotations": ["readOnlyHint": true, "openWorldHint": false, "idempotentHint": true]]
    }

    func call(_ name: String, _ args: [String: Any]) async -> [String: Any] {
        do {
            switch name {
            case "detect": return try detect(args)
            case "smart_run": return try await smartRun(args)
            case "run_tool": return try await runTool(args)
            case "list_tools": return listTools(args)
            case "run_pipeline": return try await runPipeline(args)
            default: return Self.failure("Unknown tool \"\(name)\". Available: detect, smart_run, run_tool, list_tools, run_pipeline.")
            }
        } catch let e as ToolError {
            return Self.failure(e.description + (e.hint.map { "\nHint: \($0)" } ?? ""))
        } catch {
            return Self.failure(error.localizedDescription)
        }
    }

    func detect(_ args: [String: Any]) throws -> [String: Any] {
        let input = try Self.string(args, "input")
        let report = DetectionEngine.detect(input, tools: tools.filter { $0.io.input == .text })
        let rows: [[String: Any]] = report.results.prefix(6).map {
            ["tool": $0.tool.id, "name": $0.tool.name, "confidence": NSDecimalNumber(string: String(format: "%.2f", $0.score.confidence)),
             "reason": $0.score.reason, "options": Self.json($0.score.options)]
        }
        return Self.success(Self.encode(["matches": rows]), structured: ["matches": rows])
    }

    func smartRun(_ args: [String: Any]) async throws -> [String: Any] {
        let input = try Self.string(args, "input")
        guard let analysis = SmartBox.analyse(input, tools: tools), let action = analysis.actions.first(where: { !$0.opensTool }) else {
            return Self.failure("Nothing recognised. Try list_tools and run_tool.")
        }
        var output = try await action.tool.run(text: action.inputOverride ?? input, options: action.options)
        var used = [action.tool.id]
        if let chain = SmartBox.chain(after: action, output: output.text, tools: tools), let step = chain.then {
            output = try await step.tool.run(text: output.text, options: step.options)
            used.append(step.tool.id)
        }
        var result = content(for: output)
        let note = "Recognised as \(analysis.formatName); ran \(used.joined(separator: " then "))"
            + (action.options.isEmpty ? "" : " with \(Self.encode(Self.json(action.options)))") + "."
        var blocks = result["content"] as? [[String: Any]] ?? []
        blocks.insert(["type": "text", "text": note], at: 0)
        result["content"] = blocks
        return result
    }

    func runTool(_ args: [String: Any]) async throws -> [String: Any] {
        let id = try Self.string(args, "tool")
        guard let tool = byID[id] else {
            let near = Self.nearMisses(id, in: tools)
            throw ToolError("Unknown tool \"\(id)\".", hint: near.isEmpty ? "Call list_tools." : "Did you mean \(near.joined(separator: ", "))?")
        }
        let options = try Self.options(args["options"], for: tool)
        let payload: ToolPayload
        if let b64 = args["input_base64"] as? String {
            guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { throw ToolError("input_base64 is not valid Base64") }
            payload = .data(data)
        } else {
            payload = .text(args["input"] as? String ?? "")
        }
        if payload.isEmpty, tool.io.input != .none, !(tool.optionFields.contains { $0.key == "mode" && options["mode"]?.stringValue == "generate" }) {
            throw ToolError("\(tool.name) needs input.", hint: "Pass input (text) or input_base64.")
        }
        return content(for: try await tool.run(ToolInput(payload), options: options))
    }

    func listTools(_ args: [String: Any]) -> [String: Any] {
        var list = tools
        if let q = args["query"] as? String, !q.trimmingCharacters(in: .whitespaces).isEmpty { list = ToolRegistry.search(q, in: list, limit: 20) }
        if let c = (args["category"] as? String)?.lowercased() { list = list.filter { $0.category.rawValue == c } }
        let rows: [[String: Any]] = list.map { tool in
            ["id": tool.id, "name": tool.name, "summary": tool.summary, "category": tool.category.rawValue,
             "input": tool.io.input.rawValue, "output": tool.io.output.rawValue, "options": Self.optionSchema(tool)]
        }
        return Self.success(Self.encode(["tools": rows]), structured: ["tools": rows])
    }

    func runPipeline(_ args: [String: Any]) async throws -> [String: Any] {
        let input = try Self.string(args, "input")
        let pipeline: Pipeline
        if let expr = args["expression"] as? String {
            pipeline = try Pipeline.parse(expression: expr)
        } else if let name = args["pipeline"] as? String {
            guard let p = pipelines.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.slug == name }) else {
                throw ToolError("No saved pipeline named \"\(name)\".", hint: pipelines.isEmpty ? nil : "Saved: \(pipelines.map(\.name).joined(separator: ", ")).")
            }
            pipeline = p
        } else {
            throw ToolError("Give an expression or a pipeline name.")
        }
        let lookup = byID
        let run = await PipelineEngine.run(pipeline, input: ToolInput(text: input), tools: { lookup[$0] })
        if let e = run.error {
            let failed = run.steps.first { $0.error != nil }?.step.toolID ?? "a step"
            throw ToolError("\(failed) failed: \(e.description)")
        }
        return content(for: run.finalOutput ?? .empty)
    }

    // MARK: Results

    /// Text output as text; facts (metadata) as a second block and as structured content; images as image blocks.
    func content(for output: ToolOutput) -> [String: Any] {
        var blocks: [[String: Any]] = []
        switch output.payload {
        case .text(let t) where !t.isEmpty: blocks.append(["type": "text", "text": t])
        case .image(let d, let f): blocks.append(["type": "image", "data": d.base64EncodedString(), "mimeType": f.mimeType])
        case .data(let d): blocks.append(["type": "text", "text": "Binary output (\(d.count) bytes), Base64:\n" + d.base64EncodedString()])
        case .file(let url): blocks.append(["type": "text", "text": "File: \(url.path)"])
        default: break
        }
        if !output.metadata.isEmpty {
            blocks.append(["type": "text", "text": output.metadata.map { "\($0.label): \($0.value)" }.joined(separator: "\n")])
        }
        if !output.warnings.isEmpty { blocks.append(["type": "text", "text": "Warnings:\n" + output.warnings.joined(separator: "\n")]) }
        if blocks.isEmpty { blocks.append(["type": "text", "text": "(no output)"]) }
        var result: [String: Any] = ["content": blocks, "isError": false]
        if !output.metadata.isEmpty || output.isValid != nil {
            var structured: [String: Any] = ["details": Dictionary(output.metadata.map { ($0.label, $0.value) }, uniquingKeysWith: { a, _ in a })]
            if let v = output.isValid { structured["valid"] = v }
            result["structuredContent"] = structured
        }
        return result
    }

    // MARK: Options

    /// JSON arguments → typed option values, checked against the tool's fields (unknown keys and bad choices are errors).
    static func options(_ raw: Any?, for tool: AnyTool) throws -> OptionValues {
        guard let raw else { return [:] }
        guard let dict = raw as? [String: Any] else { throw ToolError("options must be an object") }
        var out: OptionValues = [:]
        for (key, value) in dict {
            guard let field = tool.optionFields.first(where: { $0.key == key }) else {
                let keys = tool.optionFields.map(\.key)
                throw ToolError("\(tool.id) has no option \"\(key)\".", hint: keys.isEmpty ? "It takes no options." : "Options: \(keys.joined(separator: ", ")).")
            }
            let parsed: OptionValue
            switch value {
            case let b as Bool where CFGetTypeID(b as CFTypeRef) == CFBooleanGetTypeID(): parsed = .bool(b)
            case let n as NSNumber:
                switch field.defaultValue {
                case .bool: parsed = .bool(n.boolValue)
                case .int: parsed = .int(n.intValue)
                case .double: parsed = .double(n.doubleValue)
                case .string: parsed = .string(n.stringValue)
                }
            case let s as String: parsed = OptionValue.parse(s, like: field)
            default: throw ToolError("Option \"\(key)\" must be a string, number or boolean")
            }
            switch field.kind {
            case .picker(let choices), .segmented(let choices):
                guard choices.contains(where: { $0.value == parsed.stringValue }) else {
                    throw ToolError("\"\(parsed.stringValue)\" is not a value of \(key).", hint: "Allowed: \(choices.map(\.value).joined(separator: ", ")).")
                }
            default: break
            }
            out[key] = parsed
        }
        return out
    }

    /// JSON Schema-like description of a tool's options, for list_tools.
    static func optionSchema(_ tool: AnyTool) -> [String: Any] {
        var props: [String: Any] = [:]
        for f in tool.optionFields {
            var p: [String: Any] = ["title": f.label]
            switch f.kind {
            case .toggle: p["type"] = "boolean"; p["default"] = f.defaultValue.boolValue
            case .picker(let c), .segmented(let c): p["type"] = "string"; p["enum"] = c.map(\.value); p["default"] = f.defaultValue.stringValue
                p["description"] = c.map { "\($0.value) = \($0.label)" }.joined(separator: "; ")
            case .stepper(let min, let max, _): p["type"] = "integer"; p["minimum"] = min; p["maximum"] = max; p["default"] = f.defaultValue.intValue
            case .slider(let min, let max): p["type"] = "number"; p["minimum"] = min; p["maximum"] = max; p["default"] = f.defaultValue.doubleValue
            case .text, .secret, .multiline: p["type"] = "string"; p["default"] = f.defaultValue.stringValue
            }
            if let help = f.help { p["description"] = [p["description"] as? String, help].compactMap { $0 }.joined(separator: ". ") }
            props[f.key] = p
        }
        return ["type": "object", "properties": props]
    }

    /// Tool ids a typo was probably meant to be: close by edit distance, else a fuzzy name match.
    static func nearMisses(_ id: String, in tools: [AnyTool]) -> [String] {
        let close = tools.map { ($0.id, editDistance(id.lowercased(), $0.id)) }
            .filter { $0.1 <= max(2, id.count / 4) }.sorted { $0.1 < $1.1 }.prefix(3).map(\.0)
        return close.isEmpty ? ToolRegistry.search(id, in: tools, limit: 3).map(\.id) : Array(close)
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var prev = row[0]; row[0] = i
            for j in 1...b.count {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return row[b.count]
    }

    // MARK: JSON helpers

    static func string(_ args: [String: Any], _ key: String) throws -> String {
        guard let s = args[key] as? String else { throw ToolError("Missing \"\(key)\" (a string).") }
        return s
    }

    static func json(_ options: OptionValues) -> [String: Any] {
        options.mapValues { v -> Any in
            switch v { case .bool(let b): b; case .int(let i): i; case .double(let d): d; case .string(let s): s }
        }
    }

    static func success(_ text: String, structured: [String: Any]? = nil) -> [String: Any] {
        var r: [String: Any] = ["content": [["type": "text", "text": text]], "isError": false]
        if let structured { r["structuredContent"] = structured }
        return r
    }

    static func failure(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    static func result(id: Any, _ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }

    static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    static func encode(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
