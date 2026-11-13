import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

// MARK: - Items

/// One selectable row in the palette. `perform` does exactly what the row says.
struct PaletteItem: Identifiable {
    let id: String
    let title: String
    var subtitle: String?
    let symbol: String
    var shortcut: String?
    /// Query used to bold matched characters in `title`.
    var highlight = ""
    let perform: @MainActor () -> Void
}

struct PaletteSection: Identifiable {
    let title: String
    let items: [PaletteItem]
    var id: String { title }
}

private enum PaletteMetrics {
    static let width: CGFloat = 640
    static let listMaxHeight: CGFloat = 400
    static let rowHeight: CGFloat = 40
    static let iconSize: CGFloat = 28
    static let iconFont: CGFloat = 14
    static let topFraction: CGFloat = 0.16
    static let dim: Double = 0.22
    static let shadow: Double = 0.28
    static let maxRecentInputs = 4
    static let maxTools = 30
    static let previewLength = 80
}

// MARK: - Overlay

/// Attach point: `.overlay { CommandPaletteOverlay() }` on the window content.
struct CommandPaletteOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if model.showPalette {
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        Color.black.opacity(PaletteMetrics.dim)
                            .contentShape(Rectangle())
                            .onTapGesture { model.closePalette() }
                            .accessibilityHidden(true)
                        CommandPalette()
                            .padding(.top, geo.size.height * PaletteMetrics.topFraction)
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(Motion.animation(Motion.fast), value: model.showPalette)
    }
}

struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selection = 0
    @State private var recentInputs: [HistoryEntry] = []
    @FocusState private var fieldFocused: Bool

    private var sections: [PaletteSection] { buildSections() }
    private var flat: [PaletteItem] { sections.flatMap(\.items) }

    var body: some View {
        let sections = self.sections
        let flat = sections.flatMap(\.items)
        VStack(spacing: 0) {
            searchField
            Divider()
            results(sections: sections, flat: flat)
        }
        .frame(width: PaletteMetrics.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Palette.separator))
        .shadow(color: .black.opacity(PaletteMetrics.shadow), radius: Space.xl, y: Space.md)
        .background(quickPickButtons(flat))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
        .task {
            recentInputs = (try? await DataStore.shared.recentInputs(limit: 20)) ?? []
            #if DEBUG
            if let q = UserDefaults.standard.string(forKey: "BLPaletteQuery") { query = q }
            #endif
            fieldFocused = true
        }
        .onChange(of: query) { selection = 0 }
        .onExitCommand { model.closePalette() }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search tools, actions and recent inputs", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($fieldFocused)
                .accessibilityLabel("Search tools and actions")
                .onSubmit { runSelected() }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { model.closePalette(); return .handled }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md + Space.xs)
    }

    // MARK: Results

    @ViewBuilder
    private func results(sections: [PaletteSection], flat: [PaletteItem]) -> some View {
        if flat.isEmpty {
            Text("No results for “\(query)”")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xxl)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // A plain VStack: the list is small, and LazyVStack reused stale rows (wrong ⌘n badge and
                    // selection) when the query changed but a row's identity stayed the same.
                    let indexOf = Dictionary(flat.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Space.md)
                                .padding(.top, Space.md)
                                .padding(.bottom, Space.xs)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.items) { item in
                                let index = indexOf[item.id] ?? 0
                                PaletteRow(item: item, selected: index == selection, quickPick: index < 9 ? index + 1 : nil)
                                    .id(item.id)
                                    .onTapGesture { run(item) }
                                    .onHover { if $0 { selection = index } }
                            }
                        }
                    }
                    .padding(.horizontal, Space.sm)
                    .padding(.bottom, Space.sm)
                }
                .frame(maxHeight: PaletteMetrics.listMaxHeight)
                .onChange(of: selection) { _, new in
                    if flat.indices.contains(new) { proxy.scrollTo(flat[new].id) }
                }
            }
        }
    }

    /// Invisible ⌘1…⌘9 buttons so quick-pick works while the text field has focus.
    private func quickPickButtons(_ flat: [PaletteItem]) -> some View {
        ZStack {
            ForEach(0..<min(9, flat.count), id: \.self) { i in
                Button("Run result \(i + 1)") { run(flat[i]) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Behaviour

    private func move(_ delta: Int) {
        let count = flat.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func runSelected() {
        let items = flat
        if items.indices.contains(selection) { run(items[selection]) }
    }

    private func run(_ item: PaletteItem) {
        model.closePalette(refocus: false)
        // Let the palette finish dismissing before the action (file panels, tool switch) takes over.
        Task { @MainActor in
            item.perform()
            model.focusEditor()
        }
    }

    // MARK: Data

    private func buildSections() -> [PaletteSection] {
        let q = query.trimmed()
        var out: [PaletteSection] = []

        let toolItems: [PaletteItem]
        let toolTitle: String
        if q.isEmpty {
            var ids: [String] = []
            for id in model.recent + model.frequent where !ids.contains(id) { ids.append(id) }
            var tools = ids.compactMap { model.registry.tool($0) }
            if tools.isEmpty { tools = Array(model.visibleTools.prefix(6)) }
            toolTitle = "Recent tools"
            toolItems = tools.prefix(6).map { toolItem($0, q: "") }
        } else {
            toolTitle = "Tools"
            // Tools you use often get a small nudge among equally good matches.
            let usage = Dictionary(model.frequent.enumerated().map { ($1, max(10 - $0 * 2, 2)) }, uniquingKeysWith: max)
            toolItems = model.registry.search(q, limit: PaletteMetrics.maxTools, boost: usage).map { toolItem($0, q: q) }
        }
        if !toolItems.isEmpty { out.append(PaletteSection(title: toolTitle, items: toolItems)) }

        var actions: [(Int, PaletteItem)] = []
        for (item, keywords) in actionItems() {
            if q.isEmpty { actions.append((0, item)); continue }
            guard let s = Fuzzy.score(query: q, in: item.title, secondary: keywords) else { continue }
            var m = item
            m.highlight = q
            actions.append((s, m))
        }
        if !q.isEmpty { actions.sort { $0.0 > $1.0 } }
        if !actions.isEmpty { out.append(PaletteSection(title: "Actions", items: actions.map(\.1))) }

        var inputs: [PaletteItem] = []
        for entry in recentInputs {
            guard let tool = model.registry.tool(entry.toolID) else { continue }
            let oneLine = String(entry.input.replacingOccurrences(of: "\n", with: " ").prefix(PaletteMetrics.previewLength))
            if oneLine.trimmed().isEmpty { continue }
            if !q.isEmpty {
                let hay = oneLine + " " + tool.name
                guard Fuzzy.score(query: q, in: hay) != nil || hay.localizedCaseInsensitiveContains(q) else { continue }
            }
            let toolID = entry.toolID, input = entry.input, options = entry.options
            inputs.append(PaletteItem(id: "input:\(entry.id)", title: oneLine, subtitle: "Open in \(tool.name)", symbol: tool.symbol, highlight: q) { [model] in
                model.open(toolID: toolID, input: input, options: options)
            })
            if inputs.count >= PaletteMetrics.maxRecentInputs { break }
        }
        if !inputs.isEmpty { out.append(PaletteSection(title: "Recent inputs", items: inputs)) }
        return out
    }

    private func toolItem(_ tool: AnyTool, q: String) -> PaletteItem {
        let id = tool.id
        return PaletteItem(id: "tool:\(id)", title: tool.name, subtitle: tool.summary, symbol: tool.symbol, highlight: q) { [model] in
            model.open(toolID: id)
        }
    }

    /// Actions that can actually run right now; each paired with extra search keywords.
    private func actionItems() -> [(PaletteItem, String)] {
        let session = model.currentSession
        let hasOutput = session?.output != nil
        var list: [(PaletteItem, String)] = []
        if hasOutput {
            list.append((PaletteItem(id: "act:copy", title: "Copy output", symbol: "doc.on.doc", shortcut: "⇧⌘C") { session?.copyOutput() }, "clipboard"))
            list.append((PaletteItem(id: "act:replace", title: "Replace clipboard with output", symbol: "doc.on.clipboard", shortcut: "⇧⌘V") { session?.replaceClipboardWithOutput() }, "paste copy"))
            list.append((PaletteItem(id: "act:swap", title: "Swap input and output", symbol: "arrow.left.arrow.right", shortcut: "⇧⌘S") { session?.swapInputOutput() }, "exchange"))
        }
        if session != nil {
            list.append((PaletteItem(id: "act:clear", title: "Clear input", symbol: "xmark.circle", shortcut: "⌘⌫") { session?.clear() }, "reset empty"))
            list.append((PaletteItem(id: "act:open", title: "Open file…", symbol: "folder", shortcut: "⌘O") { session?.openFile() }, "load import"))
        }
        if hasOutput {
            list.append((PaletteItem(id: "act:save", title: "Save output…", symbol: "square.and.arrow.down", shortcut: "⌘S") { session?.saveOutput() }, "export file"))
        }
        list.append((PaletteItem(id: "act:smartpaste", title: "Smart paste", subtitle: "Paste into the best matching tool", symbol: "wand.and.stars", shortcut: "⌥⌘V") { [model] in model.smartPaste() }, "detect clipboard"))
        list.append((PaletteItem(id: "act:inspector", title: model.showInspector ? "Hide inspector" : "Show inspector", symbol: "sidebar.trailing", shortcut: "⌥⌘I") { [model] in model.showInspector.toggle() }, "toggle options history"))
        let open = openSettings
        list.append((PaletteItem(id: "act:settings", title: "Settings…", symbol: "gearshape", shortcut: "⌘,") { open() }, "preferences"))
        return list
    }
}

// MARK: - Row

private struct PaletteRow: View {
    let item: PaletteItem
    let selected: Bool
    let quickPick: Int?

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: item.symbol)
                .font(.system(size: PaletteMetrics.iconFont, weight: .medium))
                .foregroundStyle(selected ? Color.white : Palette.accent)
                .frame(width: PaletteMetrics.iconSize, height: PaletteMetrics.iconSize)
                .background(selected ? Color.white.opacity(0.2) : Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .accessibilityHidden(true)
            Text(highlighted)
                .font(item.id.hasPrefix("input:") ? Typography.monoSmall : .body)
                .lineLimit(1)
            if let sub = item.subtitle {
                Text(sub)
                    .font(.callout)
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: Space.sm)
            if let label = item.shortcut ?? quickPick.map({ "⌘\($0)" }) {
                Text(label)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, Space.sm)
        .frame(height: PaletteMetrics.rowHeight)
        .background(selected ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.title, item.subtitle, item.shortcut.map { "Shortcut \($0)" }].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Press Return to run")
    }

    private var highlighted: AttributedString {
        let chars = Array(item.title)
        let hits = Set(item.highlight.isEmpty ? [] : Fuzzy.matchIndices(query: item.highlight, in: item.title).filter { $0 < chars.count })
        var out = AttributedString()
        for (i, ch) in chars.enumerated() {
            var piece = AttributedString(String(ch))
            if hits.contains(i) { piece.inlinePresentationIntent = .stronglyEmphasized }
            out.append(piece)
        }
        return out
    }
}

// MARK: - Focus return

extension AppModel {
    /// Moves keyboard focus back to the current tool's input editor (first editable code editor in the key window).
    func focusEditor() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow, let root = window.contentView else { return }
            @MainActor func find(_ v: NSView) -> EditorTextView? {
                if let t = v as? EditorTextView, t.isEditable { return t }
                for s in v.subviews { if let f = find(s) { return f } }
                return nil
            }
            if let editor = find(root) { window.makeFirstResponder(editor) }
        }
    }
}
