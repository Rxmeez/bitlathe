import Foundation
import AppKit
import BitlatheCore
import BitlatheUI

/// Runs a tool, pipeline or smart detection without showing UI. Shared by the URL scheme and the Services menu.
@MainActor
enum HeadlessRunner {
    struct Result {
        var text: String
        var toolName: String
    }

    static var registry: ToolRegistry { AppModel.shared.registry }

    static func runTool(id: String, input: String, options: OptionValues = [:]) async throws -> Result {
        guard let tool = registry.tool(id) else { throw DeepLink.ParseError("Unknown tool \"\(id)\".") }
        return Result(text: try await text(of: tool, input: input, options: options), toolName: tool.name)
    }

    static func runPipeline(_ query: String, input: String) async throws -> Result {
        let pipeline = try await findPipeline(query)
        let snapshot = Dictionary(uniqueKeysWithValues: registry.tools.map { ($0.id, $0) })
        let run = await PipelineEngine.run(pipeline, input: ToolInput(.text(input))) { snapshot[$0] }
        if let e = run.error { throw e }
        guard let out = run.finalOutput?.payload.text else { throw DeepLink.ParseError("Pipeline \"\(pipeline.name)\" produced no text output.") }
        return Result(text: out, toolName: pipeline.name)
    }

    /// Detection: apply the top-ranked tool with its suggested options.
    static func runSmart(input: String) async throws -> Result {
        guard let best = bestDetection(for: input) else { throw DeepLink.ParseError("Nothing recognisable in the selected text.") }
        return Result(text: try await text(of: best.tool, input: input, options: best.score.options), toolName: best.tool.name)
    }

    static func bestDetection(for input: String) -> DetectionResult? {
        guard input.utf8.count < DetectionEngine.maxInputBytes else { return nil }
        let report = DetectionEngine.detect(input, tools: registry.tools, ignoring: Set(Settings.shared.detectionIgnoreList))
        return report.best
    }

    static func findPipeline(_ query: String) async throws -> Pipeline {
        let all = try await DataStore.shared.pipelines()
        let q = query.lowercased()
        if let p = all.first(where: { $0.name.lowercased() == q || $0.slug == q || $0.toolID == q }) { return p }
        throw DeepLink.ParseError("No pipeline named \"\(query)\".")
    }

    private static func text(of tool: AnyTool, input: String, options: OptionValues) async throws -> String {
        let out = try await tool.run(ToolInput(.text(input)), options: options)
        guard let t = out.payload.text else { throw DeepLink.ParseError("\(tool.name) did not produce text output.") }
        return t
    }

    /// Blocks the caller (main thread) while spinning the run loop until the async work finishes.
    /// Services callbacks are synchronous, so this is the bridge. Returns nil on timeout.
    static func runBlocking<T: Sendable>(timeout: TimeInterval = 10, _ work: @escaping @MainActor @Sendable () async throws -> T) -> Swift.Result<T, Error> {
        var result: Swift.Result<T, Error>?
        let task = Task { @MainActor in
            do { result = .success(try await work()) } catch { result = .failure(error) }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while result == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        if result == nil { task.cancel() }
        return result ?? .failure(DeepLink.ParseError("Timed out."))
    }
}
