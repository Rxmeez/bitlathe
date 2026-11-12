import Foundation
import Observation

/// The single source of truth for every tool: native, script and pipeline.
@MainActor
@Observable
public final class ToolRegistry {
    public static let shared = ToolRegistry()

    public private(set) var tools: [AnyTool] = []
    private var byID: [String: AnyTool] = [:]

    public init() {}

    public func register(_ tool: AnyTool) {
        if let i = tools.firstIndex(where: { $0.id == tool.id }) {
            tools[i] = tool
        } else {
            tools.append(tool)
        }
        byID[tool.id] = tool
    }

    public func register(_ newTools: [AnyTool]) {
        for t in newTools { register(t) }
    }

    public func unregister(id: String) {
        tools.removeAll { $0.id == id }
        byID[id] = nil
    }

    public func unregister(kind: AnyTool.Kind) {
        for t in tools where t.kind == kind { byID[t.id] = nil }
        tools.removeAll { $0.kind == kind }
    }

    public func tool(_ id: String) -> AnyTool? { byID[id] }

    public subscript(id: String) -> AnyTool? { byID[id] }

    public var native: [AnyTool] { tools.filter { $0.kind == .native } }
    public var scripts: [AnyTool] { tools.filter { $0.kind == .script } }
    public var pipelines: [AnyTool] { tools.filter { $0.kind == .pipeline } }

    public func tools(in category: ToolCategory) -> [AnyTool] {
        tools.filter { $0.category == category && $0.kind == .native }
    }

    /// Fuzzy search across names, summaries, ids and keywords.
    public func search(_ query: String, limit: Int = 50) -> [AnyTool] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tools }
        return tools
            .compactMap { tool -> (AnyTool, Int)? in
                guard var score = Fuzzy.score(query: q, in: tool.name, secondary: tool.searchText) else { return nil }
                // A tool whose id starts with the query ("json" → json.format) is the canonical tool for that word,
                // so it outranks tools that merely mention it (JSON ⇄ CSV, YAML ⇄ JSON…).
                if tool.id.lowercased().hasPrefix(q.lowercased() + ".") { score += 100 }
                return (tool, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
