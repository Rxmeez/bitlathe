import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

// MARK: - Path helpers

enum JSONTreePath {
    static func child(_ parent: String, key: String) -> String {
        if let f = key.unicodeScalars.first,
           f == "_" || f == "$" || CharacterSet.letters.contains(f),
           key.unicodeScalars.allSatisfy({ $0 == "_" || $0 == "$" || CharacterSet.alphanumerics.contains($0) }) {
            return parent + "." + key
        }
        let escaped = key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return parent + "['" + escaped + "']"
    }

    static func child(_ parent: String, index: Int) -> String { parent + "[\(index)]" }

    static func children(of value: JSONValue, path: String) -> [(label: String, path: String, value: JSONValue)] {
        switch value {
        case .object(let o): return o.map { (label: $0.key, path: child(path, key: $0.key), value: $0.value) }
        case .array(let a): return a.enumerated().map { (label: "\($0.offset)", path: child(path, index: $0.offset), value: $0.element) }
        default: return []
        }
    }

    static func preview(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .string(let s):
            return "\"" + String(s.prefix(160)).replacingOccurrences(of: "\n", with: "\\n") + (s.count > 160 ? "…" : "") + "\""
        case .array(let a): return a.isEmpty ? "[ ]" : "[…]"
        case .object(let o): return o.isEmpty ? "{ }" : "{…}"
        }
    }

    /// Paths of nodes that match (or contain a match). Runs off the main thread.
    static func search(_ root: JSONValue, query: String, limit: Int = 5000) -> (keep: Set<String>, matches: Int) {
        let q = query.lowercased()
        var keep = Set<String>()
        var matches = 0
        func visit(_ value: JSONValue, label: String?, path: String) -> Bool {
            var hit = false
            if matches < limit {
                if let label, label.lowercased().contains(q) { hit = true }
                if value.count == 0, preview(value).lowercased().contains(q) { hit = true }
            }
            if hit { matches += 1 }
            var childHit = false
            for c in children(of: value, path: path) where visit(c.value, label: c.label, path: c.path) { childHit = true }
            if hit || childHit { keep.insert(path) }
            return hit || childHit
        }
        _ = visit(root, label: nil, path: "$")
        return (keep, matches)
    }
}

// MARK: - Model

@MainActor
final class JSONTreeNode: Identifiable {
    let id: String
    let label: String?
    let isIndex: Bool
    let value: JSONValue
    let depth: Int
    var expanded = false
    private var cached: [JSONTreeNode]?

    init(path: String, label: String?, isIndex: Bool, value: JSONValue, depth: Int) {
        id = path
        self.label = label
        self.isIndex = isIndex
        self.value = value
        self.depth = depth
    }

    var path: String { id }
    var isContainer: Bool { value.count > 0 }
    var children: [JSONTreeNode] {
        if let cached { return cached }
        let isArray = value.arrayValue != nil
        let c = JSONTreePath.children(of: value, path: path).map {
            JSONTreeNode(path: $0.path, label: $0.label, isIndex: isArray, value: $0.value, depth: depth + 1)
        }
        cached = c
        return c
    }
}

@MainActor
@Observable
final class JSONTreeModel {
    private(set) var root: JSONTreeNode?
    private(set) var rows: [JSONTreeNode] = []
    private(set) var selected: String?
    private(set) var selectedNode: JSONTreeNode?
    private(set) var matchCount = 0
    var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    private var keep: Set<String>?
    private var searchTask: Task<Void, Never>?
    static let expandAllLimit = 20_000

    var isFiltering: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func load(_ value: JSONValue) {
        let node = JSONTreeNode(path: "$", label: nil, isIndex: false, value: value, depth: 0)
        node.expanded = true
        root = node
        selected = nil
        selectedNode = nil
        keep = nil
        if isFiltering { scheduleSearch() } else { rebuild() }
    }

    func clear() {
        root = nil
        rows = []
        selected = nil
        selectedNode = nil
    }

    func select(_ n: JSONTreeNode) {
        selected = n.id
        selectedNode = n
    }

    func toggle(_ n: JSONTreeNode) {
        guard n.isContainer else { return }
        n.expanded.toggle()
        rebuild()
    }

    func collapseAll() {
        guard let root else { return }
        func collapse(_ n: JSONTreeNode) {
            guard n.expanded else { return }
            n.expanded = false
            for c in n.children { collapse(c) }
        }
        for c in root.children { collapse(c) }
        root.expanded = true
        rebuild()
    }

    func expandAll() {
        guard let root else { return }
        expand(subtreeOf: root)
    }

    func expand(subtreeOf n: JSONTreeNode) {
        var budget = Self.expandAllLimit
        func walk(_ x: JSONTreeNode) {
            guard x.isContainer, budget > 0 else { return }
            x.expanded = true
            for c in x.children {
                budget -= 1
                walk(c)
            }
        }
        walk(n)
        rebuild()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let value = root?.value else {
            keep = nil
            matchCount = 0
            rebuild()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { JSONTreePath.search(value, query: q) }.value
            guard !Task.isCancelled, let self else { return }
            self.keep = result.keep
            self.matchCount = result.matches
            self.rebuild()
        }
    }

    func matches(_ n: JSONTreeNode) -> Bool {
        guard keep != nil, isFiltering else { return false }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if let l = n.label, l.lowercased().contains(q) { return true }
        return !n.isContainer && JSONTreePath.preview(n.value).lowercased().contains(q)
    }

    func rebuild() {
        guard let root else {
            rows = []
            return
        }
        let filter: Set<String>? = isFiltering ? (keep ?? []) : nil
        if let filter, filter.isEmpty { rows = []; return }
        var out: [JSONTreeNode] = []
        func walk(_ n: JSONTreeNode) {
            out.append(n)
            guard n.isContainer, filter != nil || n.expanded else { return }
            for c in n.children where filter?.contains(c.id) ?? true { walk(c) }
        }
        walk(root)
        rows = out
    }
}

// MARK: - Views

private enum OutputMode: Hashable { case text, tree }

struct JSONFormatterView: View {
    @Bindable var session: ToolSession
    @State private var mode: OutputMode = .text

    var body: some View {
        let config = EditorConfig.current
        VStack(spacing: 0) {
            OptionBar(session: session)
            SplitPane(orientation: $session.orientation) {
                InputPane(session: session, config: config)
            } second: {
                JSONOutputPane(session: session, config: config, mode: $mode)
            }
        }
    }
}

private struct JSONOutputPane: View {
    @Bindable var session: ToolSession
    let config: EditorConfig
    @Binding var mode: OutputMode
    @State private var model = JSONTreeModel()
    @State private var parseError: String?

    private struct ParseKey: Hashable {
        let text: String
        let mode: String
        let active: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneTitle(title: "Output") {
                HStack(spacing: Space.sm) {
                    if mode == .tree, model.root != nil {
                        Button { model.expandAll() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                            .help("Expand all").accessibilityLabel("Expand all")
                        Button { model.collapseAll() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                            .help("Collapse all").accessibilityLabel("Collapse all")
                    }
                    Picker("View", selection: $mode) {
                        Text("Text").tag(OutputMode.text)
                        Text("Tree").tag(OutputMode.tree)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .disabled(session.output == nil)
                    CopyButton(text: { session.outputText }).labelStyle(.iconOnly)
                        .disabled(session.output == nil)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            if let error = session.error { ErrorBanner(error) }
            if let out = session.output {
                WarningBanner(out.warnings)
                switch mode {
                case .text:
                    CodeEditor(text: .constant(session.outputText), language: session.outputLanguage, isEditable: false,
                               annotations: out.annotations.filter { $0.target == .output }, config: config)
                case .tree:
                    JSONTreePane(model: model, parseError: parseError)
                }
                if !out.metadata.isEmpty {
                    Divider()
                    if MetadataStrip.fits(out.metadata) {
                        MetadataStrip(rows: out.metadata)
                    } else {
                        KeyValueList(out.metadata).frame(maxHeight: 220)
                    }
                }
            } else if session.error == nil {
                VStack(spacing: Space.sm) {
                    Spacer()
                    Image(systemName: session.isRunning ? "hourglass" : "arrow.right.circle")
                        .font(.system(size: 28, weight: .light)).foregroundStyle(.quaternary)
                    Text("Results appear here as you type").font(.callout).foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity).background(Palette.editorBackground)
            } else {
                Spacer().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.editorBackground)
            }
        }
        .task(id: ParseKey(text: session.outputText, mode: inputMode, active: mode == .tree && session.output != nil)) {
            await reparse()
        }
    }

    private var inputMode: String {
        if case .string(let s)? = session.options["inputMode"] { return s }
        return "json"
    }

    private func reparse() async {
        guard mode == .tree, session.output != nil else { return }
        let text = session.outputText
        let opts = JSONFormatTool.parserOptions(inputMode)
        let result: Result<JSONValue, ToolError> = await Task.detached(priority: .userInitiated) {
            do { return .success(try JSONParser.parse(text, options: opts)) } catch let e as ToolError { return .failure(e) } catch { return .failure(ToolError(error.localizedDescription)) }
        }.value
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let v):
            parseError = nil
            model.load(v)
        case .failure(let e):
            parseError = e.message
            model.clear()
        }
    }
}

private struct JSONTreePane: View {
    @Bindable var model: JSONTreeModel
    let parseError: String?
    private let rowHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter keys and values", text: $model.query)
                    .textFieldStyle(.plain)
                if model.isFiltering {
                    Text("\(model.matchCount) match\(model.matchCount == 1 ? "" : "es")")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary).accessibilityLabel("Clear filter")
                }
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.xs + 1)
            .background(Palette.chrome)
            .overlay(alignment: .bottom) { Divider() }

            if let parseError {
                Text(parseError).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.editorBackground)
            } else if model.root == nil {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.editorBackground)
            } else if model.rows.isEmpty {
                Text("No matches").font(.callout).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.editorBackground)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { node in
                            JSONTreeRow(node: node, model: model, highlighted: model.matches(node))
                                .frame(height: rowHeight)
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
                .background(Palette.editorBackground)
            }
            if let sel = model.selectedNode {
                Divider()
                HStack(spacing: Space.sm) {
                    Text(sel.path).font(Typography.captionMono).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button("Copy Path") { Clipboard.copy(sel.path, toast: "Path copied") }
                    Button("Copy Value") { Clipboard.copy(JSONSerializer.string(sel.value), toast: "Value copied") }
                }
                .controlSize(.small)
                .padding(.horizontal, Space.md).padding(.vertical, Space.xs + 1)
                .background(Palette.chrome)
            }
        }
    }
}

private struct JSONTreeRow: View {
    let node: JSONTreeNode
    let model: JSONTreeModel
    let highlighted: Bool
    private let indent: CGFloat = 14

    var body: some View {
        let selected = model.selected == node.id
        HStack(spacing: Space.xs) {
            Group {
                if node.isContainer {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 20)
                        .contentShape(Rectangle())
                        .onTapGesture { model.toggle(node) }
                } else {
                    Color.clear.frame(width: 14)
                }
            }
            Text(node.label ?? "root")
                .font(Typography.mono)
                .foregroundStyle(node.label == nil || node.isIndex ? Color.secondary : Palette.accent)
                .lineLimit(1)
            TypeBadge(value: node.value)
            if node.isContainer {
                Text(countLabel).font(.caption).foregroundStyle(.tertiary)
            } else {
                Text(JSONTreePath.preview(node.value))
                    .font(Typography.mono)
                    .foregroundStyle(valueColor)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Space.sm + CGFloat(node.depth) * indent)
        .padding(.trailing, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(selected ? Palette.accent.opacity(0.22) : (highlighted ? Color.yellow.opacity(0.22) : .clear))
                .padding(.horizontal, Space.xs)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.toggle(node) }
        .onTapGesture { model.select(node) }
        .contextMenu {
            Button("Copy Path", systemImage: "link") { Clipboard.copy(node.path, toast: "Path copied") }
            Button("Copy Value", systemImage: "doc.on.doc") { Clipboard.copy(JSONSerializer.string(node.value), toast: "Value copied") }
            if let l = node.label { Button("Copy Key", systemImage: "textformat") { Clipboard.copy(l, toast: "Key copied") } }
            if node.isContainer {
                Divider()
                Button(node.expanded ? "Collapse" : "Expand") { model.toggle(node) }
                Button("Expand All Below") { model.expand(subtreeOf: node) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var countLabel: String {
        let n = node.value.count
        if node.value.arrayValue != nil { return "\(n) \(n == 1 ? "item" : "items")" }
        return "\(n) \(n == 1 ? "key" : "keys")"
    }

    private var isOpen: Bool { node.expanded || model.isFiltering }

    private var valueColor: Color {
        switch node.value {
        case .string: .green
        case .number: .orange
        case .bool: .purple
        default: .secondary
        }
    }
}

private struct TypeBadge: View {
    let value: JSONValue
    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .padding(.horizontal, Space.xs + 1).padding(.vertical, 1)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.small / 2, style: .continuous))
    }

    private var label: String {
        switch value {
        case .null: "null"
        case .bool: "bool"
        case .number: "num"
        case .string: "str"
        case .array: "arr"
        case .object: "obj"
        }
    }

    private var tint: Color {
        switch value {
        case .null: .gray
        case .bool: .purple
        case .number: .orange
        case .string: .green
        case .array: .blue
        case .object: .teal
        }
    }
}

@MainActor
enum JSONTreeViewRegistration {
    static func register() {
        ToolViewRegistry.register(JSONFormatTool.id) { session in AnyView(JSONFormatterView(session: session)) }
    }
}
