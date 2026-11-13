import Foundation

/// A graph a tool wants drawn: boxes and arrows, with details for an inspector. Tools build one from what they parsed
/// (a workflow's jobs, a set of Kubernetes manifests) and ship it as JSON in an output facet; the app draws it.
/// Codable, so the same graph is also something an agent or a script can read.
public struct Diagram: Codable, Sendable, Equatable {

    public enum Tone: String, Codable, Sendable {
        case trigger, job, network, workload, config, secret, storage, identity, policy, other
    }

    public struct Detail: Codable, Sendable, Equatable {
        public var label: String
        public var value: String
        public init(_ label: String, _ value: String) { self.label = label; self.value = value }
    }

    public struct Node: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var subtitle: String?
        /// A short kind label on the card ("Deployment", "matrix ×6").
        public var badge: String?
        /// SF Symbol name.
        public var symbol: String
        public var tone: Tone
        /// A few lines shown on the card itself (a job's steps, a workload's images).
        public var lines: [String]
        /// Everything else, for the inspector.
        public var details: [Detail]
        /// Referred to, but not defined in the input (a Secret created elsewhere): drawn dashed.
        public var external: Bool
        /// The column, when the producer knows it. Nodes without one are placed by their edges.
        public var layer: Int?

        public init(id: String, title: String, subtitle: String? = nil, badge: String? = nil, symbol: String, tone: Tone,
                    lines: [String] = [], details: [Detail] = [], external: Bool = false, layer: Int? = nil) {
            self.id = id; self.title = title; self.subtitle = subtitle; self.badge = badge; self.symbol = symbol
            self.tone = tone; self.lines = lines; self.details = details; self.external = external; self.layer = layer
        }
    }

    public struct Edge: Codable, Sendable, Equatable, Hashable {
        public var from: String
        public var to: String
        public var label: String?
        public var dashed: Bool
        public init(_ from: String, _ to: String, label: String? = nil, dashed: Bool = false) {
            self.from = from; self.to = to; self.label = label; self.dashed = dashed
        }
    }

    public var title: String
    public var nodes: [Node]
    public var edges: [Edge]

    public init(title: String, nodes: [Node], edges: [Edge]) {
        self.title = title
        self.nodes = nodes
        // An edge to a node that is not there cannot be drawn; the same edge twice is one edge.
        let ids = Set(nodes.map(\.id))
        var seen = Set<Edge>()
        self.edges = edges.filter { ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to && seen.insert($0).inserted }
    }

    // MARK: Facet

    /// The output facet title tools put the graph under.
    public static let facetTitle = "Graph"

    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    public static func decode(_ json: String) -> Diagram? {
        try? JSONDecoder().decode(Diagram.self, from: Data(json.utf8))
    }

    // MARK: Layout

    /// Columns of node ids, left to right, each ordered top to bottom so arrows cross as little as possible.
    /// Nodes with a `layer` keep it; the rest go one column after the furthest node that points at them.
    /// Empty columns are removed. Cycles are tolerated (the edge that closes one is ignored for placement).
    public func columns() -> [[String]] {
        guard !nodes.isEmpty else { return [] }
        let order = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        var incoming: [String: [String]] = [:], outgoing: [String: [String]] = [:]
        for e in edges { incoming[e.to, default: []].append(e.from); outgoing[e.from, default: []].append(e.to) }

        // Longest path from the sources, with depth-first search marking the edges that close a cycle.
        var layer: [String: Int] = [:]
        var visiting = Set<String>()
        func place(_ id: String) -> Int {
            if let l = layer[id] { return l }
            guard let node = nodes[safe: order[id] ?? -1] else { return 0 }
            if let fixed = node.layer { layer[id] = fixed; return fixed }
            visiting.insert(id)
            var l = 0
            for p in incoming[id] ?? [] where !visiting.contains(p) { l = max(l, place(p) + 1) }
            visiting.remove(id)
            layer[id] = l
            return l
        }
        for n in nodes { _ = place(n.id) }

        let used = Set(layer.values).sorted()
        let compact = Dictionary(uniqueKeysWithValues: used.enumerated().map { ($0.element, $0.offset) })
        var cols = Array(repeating: [String](), count: used.count)
        for n in nodes { cols[compact[layer[n.id] ?? 0] ?? 0].append(n.id) }

        // Barycentre ordering: sweep right using each node's sources, then left using its targets.
        func position(_ col: [String]) -> [String: Double] {
            Dictionary(uniqueKeysWithValues: col.enumerated().map { ($0.element, Double($0.offset)) })
        }
        func reorder(_ c: Int, by neighbours: [String: [String]], in ref: [String: Double]) {
            let keyed = cols[c].enumerated().map { i, id -> (String, Double) in
                let ps = (neighbours[id] ?? []).compactMap { ref[$0] }
                return (id, ps.isEmpty ? Double(i) : ps.reduce(0, +) / Double(ps.count))
            }
            cols[c] = keyed.enumerated().sorted { a, b in
                a.element.1 != b.element.1 ? a.element.1 < b.element.1 : (order[a.element.0] ?? 0) < (order[b.element.0] ?? 0)
            }.map(\.element.0)
        }
        if cols.count > 1 {
            for _ in 0..<4 {
                for c in 1..<cols.count { reorder(c, by: incoming, in: position(cols[c - 1])) }
                for c in stride(from: cols.count - 2, through: 0, by: -1) { reorder(c, by: outgoing, in: position(cols[c + 1])) }
            }
        }
        return cols
    }

    // MARK: Mermaid

    /// The same graph as a Mermaid flowchart, to paste into a README or a pull request.
    public func mermaid() -> String {
        var ids: [String: String] = [:]
        for (i, n) in nodes.enumerated() {
            let base = n.id.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
            ids[n.id] = "n\(i)_" + base.prefix(40)
        }
        func label(_ s: String) -> String {
            s.replacingOccurrences(of: "\"", with: "#quot;").replacingOccurrences(of: "\n", with: " ")
        }
        var out = ["flowchart LR"]
        for n in nodes {
            let id = ids[n.id] ?? "n"
            var text = n.badge.map { "<small>\(label($0))</small><br/>" } ?? ""
            text += "<b>\(label(n.title))</b>"
            if let s = n.subtitle, !s.isEmpty { text += "<br/>\(label(s))" }
            out.append(n.tone == .trigger ? "  \(id)([\"\(text)\"])" : "  \(id)[\"\(text)\"]")
            if n.external { out.append("  class \(id) external") }
        }
        for e in edges {
            guard let a = ids[e.from], let b = ids[e.to] else { continue }
            let arrow = e.dashed ? "-.->" : "-->"
            if let l = e.label, !l.isEmpty { out.append("  \(a) \(arrow)|\(label(l))| \(b)") } else { out.append("  \(a) \(arrow) \(b)") }
        }
        if nodes.contains(where: \.external) { out.append("  classDef external stroke-dasharray: 4 3,opacity:0.7") }
        return out.joined(separator: "\n")
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
