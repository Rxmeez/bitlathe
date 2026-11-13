import Foundation
import BitlatheCore
import BitlatheTools

// bl — the Bitlathe command line. Reuses the exact same engines as the app.

let version = "0.1.0"

enum CLIError: Error { case usage(String), tool(String) }

func stderr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func readStdin() -> Data {
    FileHandle.standardInput.readDataToEndOfFile()
}

func printUsage() {
    print("""
    bl \(version) — Bitlathe command line

    USAGE
      bl <tool.id> [--option value]… [file]      run a tool (reads stdin when no file is given)
      bl detect [text]                            rank tools for the input (stdin when omitted)
      bl pipe "<tool> [k=v] | <tool> | …"         run an ad-hoc pipeline
      bl pipeline <name> [file]                   run a saved pipeline
      bl list [--json] [--category <name>]        list tools
      bl mcp                                      serve the tools to AI agents (Model Context Protocol, stdio)
      bl <tool.id> --help                         show a tool's options
      bl --version

    OPTIONS
      --out <file>      write output to a file instead of stdout (required for binary/image output on a TTY)
      --json            machine-readable output (list, detect, and tool metadata)
      --quiet           suppress warnings

    EXAMPLES
      bl json.format --indent 4 < package.json
      echo 1700000000 | bl time.unix
      bl base64.text --mode decode <<< "SGVsbG8="
      bl pipe "base64.text mode=decode | compress.text mode=decompress | json.format"
      pbpaste | bl detect

    EXIT CODES
      0 success · 1 tool error · 2 usage error
    """)
}

func toolHelp(_ tool: AnyTool) {
    print("\(tool.id) — \(tool.name)\n\(tool.summary)\n")
    print("Category: \(tool.category.title)   Input: \(tool.io.input.rawValue)   Output: \(tool.io.output.rawValue)")
    if !tool.optionFields.isEmpty {
        print("\nOPTIONS")
        for f in tool.optionFields {
            var desc = "  --\(f.key)"
            switch f.kind {
            case .toggle: desc += " <true|false>"
            case .picker(let c), .segmented(let c): desc += " <" + c.map(\.value).joined(separator: "|") + ">"
            case .stepper(let min, let max, _): desc += " <\(min)…\(max)>"
            case .slider(let min, let max): desc += " <\(min)…\(max)>"
            case .text, .secret, .multiline: desc += " <text>"
            }
            desc = desc.padding(toLength: max(desc.count + 2, 40), withPad: " ", startingAt: 0)
            desc += f.label + "  (default: \(f.defaultValue.stringValue.isEmpty ? "none" : f.defaultValue.stringValue))"
            if let h = f.help { desc += "\n" + String(repeating: " ", count: 40) + h }
            print(desc)
        }
    }
    if !tool.samples.isEmpty {
        print("\nEXAMPLE INPUT\n  " + tool.samples[0].input.replacingOccurrences(of: "\n", with: "\n  "))
    }
}

func parseArgs(_ args: [String], fields: [OptionField]) throws -> (options: OptionValues, positional: [String], flags: Set<String>, out: String?) {
    var options: OptionValues = [:]
    var positional: [String] = []
    var flags: Set<String> = []
    var out: String?
    var i = 0
    while i < args.count {
        let a = args[i]
        if a.hasPrefix("--") {
            let body = String(a.dropFirst(2))
            let (key, inlineValue): (String, String?) = body.contains("=") ? (String(body.split(separator: "=", maxSplits: 1)[0]), String(body.split(separator: "=", maxSplits: 1)[1])) : (body, nil)
            if ["help", "json", "quiet", "version"].contains(key) { flags.insert(key); i += 1; continue }
            if key == "out" {
                out = inlineValue ?? (i + 1 < args.count ? args[i + 1] : nil)
                i += inlineValue == nil ? 2 : 1
                continue
            }
            if let field = fields.first(where: { $0.key == key }) {
                let value: String
                if let inlineValue { value = inlineValue; i += 1 }
                else if case .toggle = field.kind, i + 1 >= args.count || args[i + 1].hasPrefix("--") { value = "true"; i += 1 }
                else if i + 1 < args.count { value = args[i + 1]; i += 2 }
                else { throw CLIError.usage("Missing value for --\(key)") }
                options[key] = OptionValue.parse(value, like: field)
            } else {
                throw CLIError.usage("Unknown option --\(key). Run with --help to see options.")
            }
        } else {
            positional.append(a)
            i += 1
        }
    }
    return (options, positional, flags, out)
}

func loadInput(_ positional: [String], tool: AnyTool) throws -> ToolInput {
    if let path = positional.first {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        var secondary: ToolPayload?
        if tool.io.dualInput, positional.count > 1, let s = try? String(contentsOf: URL(fileURLWithPath: positional[1]), encoding: .utf8) { secondary = .text(s) }
        if let f = ImageFormat.sniff(data), f != .svg || tool.io.input == .image { return ToolInput(.image(data, f), secondary: secondary, fileName: url.lastPathComponent) }
        if tool.io.input == .file { return ToolInput(.file(url), secondary: secondary, fileName: url.lastPathComponent) }
        if let s = String(data: data, encoding: .utf8) { return ToolInput(.text(s), secondary: secondary, fileName: url.lastPathComponent) }
        return ToolInput(.data(data), secondary: secondary, fileName: url.lastPathComponent)
    }
    if tool.io.input == .none { return ToolInput(.none) }
    let data = readStdin()
    if let f = ImageFormat.sniff(data), f != .svg || tool.io.input == .image { return ToolInput(.image(data, f)) }
    if let s = String(data: data, encoding: .utf8) {
        return ToolInput(.text(s.hasSuffix("\n") && !s.hasSuffix("\n\n") ? String(s.dropLast()) : s))
    }
    return ToolInput(.data(data))
}

func emit(_ output: ToolOutput, outPath: String?, quiet: Bool, json: Bool) throws {
    if json {
        var obj: [String: Any] = ["ok": true, "type": output.payload.kindName]
        if let t = output.payload.text { obj["output"] = t } else if let d = output.payload.data { obj["base64"] = d.base64EncodedString() }
        if !output.metadata.isEmpty { obj["metadata"] = output.metadata.map { [$0.label: $0.value] } }
        if !output.facets.isEmpty { obj["facets"] = output.facets.reduce(into: [String: String]()) { $0[$1.title] = $1.payload.text ?? "" } }
        if !output.warnings.isEmpty { obj["warnings"] = output.warnings }
        if let v = output.isValid { obj["valid"] = v }
        print(String(decoding: try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        return
    }
    if !quiet { for w in output.warnings { stderr("warning: \(w)") } }
    if let outPath {
        guard let data = output.payload.data else { throw CLIError.tool("No output to write") }
        try data.write(to: URL(fileURLWithPath: outPath))
        if !quiet { stderr("wrote \(ByteFormatter.string(data.count)) to \(outPath)") }
        return
    }
    switch output.payload {
    case .text(let t):
        print(t)
        if t.isEmpty, !output.metadata.isEmpty {
            for m in output.metadata { print("\(m.label): \(m.value)") }
        }
    case .none:
        for m in output.metadata { print("\(m.label): \(m.value)") }
    case .image(let d, _), .data(let d):
        if isatty(STDOUT_FILENO) != 0 {
            throw CLIError.usage("Output is binary (\(ByteFormatter.string(d.count))). Use --out <file> or pipe it somewhere.")
        }
        FileHandle.standardOutput.write(d)
    case .file(let url):
        print(url.path)
    }
}

@MainActor
func main() async -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    ToolCatalog.registerAll()
    let registry = ToolRegistry.shared
    // User scripts
    let scriptsFolder = Settings.shared.scriptsFolderPath.isEmpty ? ScriptLoader.defaultFolder : URL(fileURLWithPath: Settings.shared.scriptsFolderPath)
    for s in ScriptLoader.load(folder: scriptsFolder) { registry.register(s.asTool) }
    // Pipeline steps run off the main actor, so they resolve tools from an immutable snapshot
    // (MainActor.assumeIsolated traps there). Pipelines cannot nest, so natives + scripts suffice.
    let toolsByID = Dictionary(registry.tools.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let lookup: @Sendable (String) -> AnyTool? = { toolsByID[$0] }
    // Saved pipelines
    if let pipelines = try? await DataStore.shared.pipelines() {
        for p in pipelines { registry.register(PipelineEngine.asTool(p, tools: lookup)) }
    }

    guard let command = args.first else { printUsage(); return 2 }
    args.removeFirst()
    do {
        switch command {
        case "--help", "-h", "help": printUsage(); return 0
        case "--version", "-v", "version": print("bl \(version)"); return 0
        case "mcp":
            // Model Context Protocol over stdio: one JSON-RPC message per line in, one per line out. Logs go to stderr.
            let saved = (try? await DataStore.shared.pipelines()) ?? []
            let server = MCPServer(tools: registry.tools, pipelines: saved, version: version)
            stderr("bl mcp: serving \(registry.tools.count) tools on stdio")
            for try await line in FileHandle.standardInput.bytes.lines {
                if let reply = await server.handle(line: line) {
                    FileHandle.standardOutput.write(Data((reply + "\n").utf8))
                }
            }
            return 0
        case "list":
            let json = args.contains("--json")
            var tools = registry.tools
            if let i = args.firstIndex(of: "--category"), i + 1 < args.count {
                let c = args[i + 1].lowercased()
                tools = tools.filter { $0.category.rawValue == c || $0.category.title.lowercased().contains(c) }
            }
            if json {
                let arr = tools.map { ["id": $0.id, "name": $0.name, "summary": $0.summary, "category": $0.category.rawValue, "kind": $0.kind.rawValue,
                                       "options": $0.optionFields.map { ["key": $0.key, "label": $0.label, "default": $0.defaultValue.stringValue] }] as [String: Any] }
                print(String(decoding: try JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
            } else {
                var current: ToolCategory?
                for t in tools.sorted(by: { ($0.category.rawValue, $0.name) < ($1.category.rawValue, $1.name) }) {
                    if t.category != current { current = t.category; print("\n\(t.category.title)") }
                    print("  " + t.id.padding(toLength: 24, withPad: " ", startingAt: 0) + t.name.padding(toLength: 28, withPad: " ", startingAt: 0) + t.summary)
                }
            }
            return 0
        case "detect":
            let json = args.contains("--json")
            let text = args.filter { !$0.hasPrefix("--") }.first ?? String(decoding: readStdin(), as: UTF8.self)
            let report = DetectionEngine.detect(text, tools: registry.tools, ignoring: Set(Settings.shared.detectionIgnoreList))
            if json {
                let arr = report.results.map { ["id": $0.tool.id, "name": $0.tool.name, "confidence": $0.score.confidence, "reason": $0.score.reason] as [String: Any] }
                print(String(decoding: try JSONSerialization.data(withJSONObject: ["results": arr, "ms": Double(report.duration.components.attoseconds) / 1e15 + Double(report.duration.components.seconds) * 1000], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
            } else if report.results.isEmpty {
                print("No matching tool.")
            } else {
                for r in report.results.prefix(6) {
                    print(String(format: "%3.0f%%  %@  %@", r.score.confidence * 100, r.tool.id.padding(toLength: 22, withPad: " ", startingAt: 0), r.score.reason))
                }
            }
            return 0
        case "pipe", "pipeline":
            guard let spec = args.first else { throw CLIError.usage("Missing pipeline \(command == "pipe" ? "expression" : "name")") }
            let rest = Array(args.dropFirst())
            let pipeline: Pipeline
            if command == "pipe" {
                pipeline = try Pipeline.parse(expression: spec)
            } else {
                guard let p = try await DataStore.shared.pipelines().first(where: { $0.name.caseInsensitiveCompare(spec) == .orderedSame || $0.slug == spec }) else {
                    throw CLIError.usage("No saved pipeline named \"\(spec)\"")
                }
                pipeline = p
            }
            let (_, positional, flags, out) = try parseArgs(rest, fields: [])
            let firstTool = registry.tool(pipeline.steps.first?.toolID ?? "") ?? registry.tools[0]
            let input = try loadInput(positional, tool: firstTool)
            let run = await PipelineEngine.run(pipeline, input: input, tools: lookup)
            if let e = run.error {
                let failed = run.steps.first { $0.error != nil }
                throw CLIError.tool("\(failed?.step.toolID ?? "pipeline"): \(e.description)")
            }
            try emit(run.finalOutput ?? .empty, outPath: out, quiet: flags.contains("quiet"), json: flags.contains("json"))
            return 0
        default:
            guard let tool = registry.tool(command) else {
                let suggestions = registry.search(command, limit: 3).map(\.id)
                throw CLIError.usage("Unknown tool \"\(command)\"." + (suggestions.isEmpty ? "" : " Did you mean: \(suggestions.joined(separator: ", "))?") + " Run `bl list`.")
            }
            let (options, positional, flags, out) = try parseArgs(args, fields: tool.optionFields)
            if flags.contains("help") { toolHelp(tool); return 0 }
            let input = try loadInput(positional, tool: tool)
            let output = try await tool.run(input, options: options)
            try emit(output, outPath: out, quiet: flags.contains("quiet"), json: flags.contains("json"))
            return 0
        }
    } catch CLIError.usage(let m) {
        stderr("bl: \(m)")
        return 2
    } catch CLIError.tool(let m) {
        stderr("bl: \(m)")
        return 1
    } catch let e as ToolError {
        stderr("bl: \(e.description)" + (e.hint.map { "\n     hint: \($0)" } ?? ""))
        return 1
    } catch {
        stderr("bl: \(error.localizedDescription)")
        return 1
    }
}

exit(await main())
