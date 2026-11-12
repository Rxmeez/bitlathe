import Foundation

public struct PipelineStep: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var toolID: String
    public var options: OptionValues
    public var enabled: Bool

    public init(id: UUID = UUID(), toolID: String, options: OptionValues = [:], enabled: Bool = true) {
        self.id = id
        self.toolID = toolID
        self.options = options
        self.enabled = enabled
    }
}

public struct Pipeline: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var symbol: String
    public var steps: [PipelineStep]
    public var hotkey: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, summary: String = "", symbol: String = "point.3.connected.trianglepath.dotted",
                steps: [PipelineStep] = [], hotkey: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.steps = steps
        self.hotkey = hotkey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Tool id used in the registry, URL scheme and CLI.
    public var toolID: String { "pipeline." + slug }
    public var slug: String {
        let allowed = name.lowercased().map { c -> Character in
            c.isLetter || c.isNumber ? c : "-"
        }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }

    /// Parse `"base64.decode | compress.text mode=decompress | json.format"`.
    public static func parse(expression: String, name: String = "Ad hoc") throws -> Pipeline {
        var steps: [PipelineStep] = []
        for part in expression.split(separator: "|") {
            let tokens = part.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
            guard let first = tokens.first else { continue }
            var options: OptionValues = [:]
            for t in tokens.dropFirst() {
                let kv = t.split(separator: "=", maxSplits: 1)
                let key = String(kv[0]).replacingOccurrences(of: "--", with: "")
                let raw = kv.count > 1 ? String(kv[1]) : "true"
                if let i = Int(raw) { options[key] = .int(i) }
                else if raw == "true" || raw == "false" { options[key] = .bool(raw == "true") }
                else if let d = Double(raw) { options[key] = .double(d) }
                else { options[key] = .string(raw) }
            }
            steps.append(PipelineStep(toolID: String(first), options: options))
        }
        guard !steps.isEmpty else { throw ToolError("Pipeline expression is empty") }
        return Pipeline(name: name, steps: steps)
    }

    public var expression: String {
        steps.filter(\.enabled).map { step in
            ([step.toolID] + step.options.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.stringValue)" }).joined(separator: " ")
        }.joined(separator: " | ")
    }

    public func exportJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(self)
    }

    public static func importJSON(_ data: Data) throws -> Pipeline {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        var p = try dec.decode(Pipeline.self, from: data)
        p.id = UUID()
        return p
    }
}

public struct PipelineStepResult: Sendable, Identifiable {
    public var id: UUID { step.id }
    public let step: PipelineStep
    public let tool: AnyTool?
    public let output: ToolOutput?
    public let error: ToolError?
    public let duration: Duration
    public let skipped: Bool
}

public struct PipelineRun: Sendable {
    public var steps: [PipelineStepResult]
    public var finalOutput: ToolOutput?
    public var error: ToolError? { steps.compactMap(\.error).first }
    public var duration: Duration
}

public enum PipelineEngine {
    public static func run(_ pipeline: Pipeline, input: ToolInput, tools: @Sendable (String) -> AnyTool?) async -> PipelineRun {
        let clock = ContinuousClock()
        let start = clock.now
        var current = input
        var results: [PipelineStepResult] = []
        var last: ToolOutput?
        var failed = false
        for step in pipeline.steps {
            if Task.isCancelled { break }
            guard let tool = tools(step.toolID) else {
                results.append(PipelineStepResult(step: step, tool: nil, output: nil,
                                                  error: ToolError("Unknown tool \"\(step.toolID)\""), duration: .zero, skipped: false))
                failed = true
                break
            }
            if !step.enabled || failed {
                results.append(PipelineStepResult(step: step, tool: tool, output: nil, error: nil, duration: .zero, skipped: true))
                continue
            }
            let t0 = clock.now
            do {
                let out = try await tool.run(current, options: step.options)
                results.append(PipelineStepResult(step: step, tool: tool, output: out, error: nil, duration: clock.now - t0, skipped: false))
                current = ToolInput(out.payload, fileName: current.fileName)
                last = out
            } catch let e as ToolError {
                results.append(PipelineStepResult(step: step, tool: tool, output: nil, error: e, duration: clock.now - t0, skipped: false))
                failed = true
            } catch {
                results.append(PipelineStepResult(step: step, tool: tool, output: nil, error: ToolError(error.localizedDescription), duration: clock.now - t0, skipped: false))
                failed = true
            }
        }
        return PipelineRun(steps: results, finalOutput: failed ? nil : last, duration: clock.now - start)
    }

    /// Wrap a pipeline as a tool so it shows up in the palette, CLI, URL scheme and Shortcuts.
    public static func asTool(_ pipeline: Pipeline, tools: @escaping @Sendable (String) -> AnyTool?) -> AnyTool {
        AnyTool(id: pipeline.toolID, name: pipeline.name,
                summary: pipeline.summary.isEmpty ? pipeline.expression : pipeline.summary,
                category: .scripting, symbol: pipeline.symbol, keywords: ["pipeline"] + pipeline.steps.map(\.toolID),
                kind: .pipeline) { input, _ in
            let run = await PipelineEngine.run(pipeline, input: input, tools: tools)
            if let e = run.error { throw e }
            return run.finalOutput ?? .empty
        }
    }
}
