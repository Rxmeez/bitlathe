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

    /// Tools most people reach for. Among equally good matches they rank first ("base" → Base64 before Base32).
    public nonisolated static let everyday: [String] = [
        "json.format", "base64.text", "jwt.debug", "url.encode", "time.unix", "id.generate", "hash.generate",
        "regex.test", "text.diff", "color.convert", "html.format", "yaml.format", "cron.parse", "markdown.preview",
        "sql.format", "qr.code",
    ]

    /// Fuzzy search across names, summaries, ids and keywords.
    /// - Parameter boost: extra score per tool id (e.g. from the user's own usage), added to the match score.
    public func search(_ query: String, limit: Int = 50, boost: [String: Int] = [:]) -> [AnyTool] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tools }
        return Self.search(q, in: tools, limit: limit, boost: boost)
    }

    /// The ranking behind `search`, usable off the main actor (the Smart Box engine runs it on a tool snapshot).
    public nonisolated static func search(_ query: String, in tools: [AnyTool], limit: Int = 50, boost: [String: Int] = [:]) -> [AnyTool] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(tools.prefix(limit)) }
        return tools
            .compactMap { tool -> (AnyTool, Int)? in
                guard var score = Fuzzy.score(query: q, in: tool.name, secondary: tool.searchText) else { return nil }
                // A tool whose id starts with the query ("json" → json.format) is the canonical tool for that word,
                // so it outranks tools that merely mention it (JSON ⇄ CSV, YAML ⇄ JSON…).
                if tool.id.lowercased().hasPrefix(q.lowercased() + ".") { score += 100 }
                if everyday.contains(tool.id) { score += 12 }
                score += boost[tool.id] ?? 0
                return (tool, score)
            }
            // Deterministic order: score, then name, so equal matches never shuffle between keystrokes.
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending }
            .prefix(limit)
            .map(\.0)
    }
}
