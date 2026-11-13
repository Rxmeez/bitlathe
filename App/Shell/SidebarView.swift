import SwiftUI
import BitlatheCore
import BitlatheUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    /// The row the user picked. A tool can appear in several sections (Favourites, Frequently used, its category);
    /// rows carry section-qualified tags so only the clicked row is highlighted, not every copy of the tool.
    @State private var rowKey: String?

    private var selection: Binding<String?> {
        Binding(
            get: {
                guard let id = model.selectedToolID else { return nil }
                if let k = rowKey, ToolRow.toolID(from: k) == id { return k }
                return id
            },
            set: { key in
                rowKey = key
                model.selectedToolID = key.map(ToolRow.toolID(from:))
            })
    }

    var body: some View {
        @Bindable var model = model
        List(selection: selection) {
            if model.searchText.isEmpty {
                Section { Label("Home", systemImage: "house").tag(AppModel.homeID) } // smartbox: the Smart Box
                if model.settings.clipboardHistoryEnabled { // clipboard: only when opted in
                    Section { Label("Clipboard", systemImage: "list.clipboard").tag(ClipboardMonitor.sidebarID) }
                }
                if !model.favourites.isEmpty {
                    Section("Favourites") { toolRows(ids: model.favourites, section: "fav") }
                }
                if model.settings.showFrequentlyUsed, !model.frequent.isEmpty {
                    Section("Frequently used") { toolRows(ids: model.frequent, section: "freq") }
                }
                ForEach(ToolCategory.allCases.filter { $0 != .scripting }) { category in
                    let tools = model.tools(in: category)
                    if !tools.isEmpty {
                        Section(category.title) { ForEach(tools) { ToolRow(tool: $0) } }
                    }
                }
                // pipelines: saved pipelines + "New Pipeline"
                Section("Pipelines") {
                    ForEach(model.pipelines.pipelines) { p in
                        if let tool = model.registry.tool(p.toolID) { ToolRow(tool: tool) }
                    }
                    Button { model.pipelines.create() } label: {
                        Label { Text("New Pipeline") } icon: { Image(systemName: "plus").frame(width: Space.xl - Space.xs, alignment: .center) }
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("New Pipeline (⌥⌘N)")
                }
                let extras = model.visibleTools.filter { $0.kind == .script } // pipelines: pipelines have their own section
                if !extras.isEmpty {
                    Section("Scripts & Pipelines") { ForEach(extras) { ToolRow(tool: $0) } }
                }
            } else {
                Section("Results") {
                    if model.filteredTools.isEmpty { Text("No tools match “\(model.searchText)”").foregroundStyle(.secondary) }
                    ForEach(model.filteredTools) { ToolRow(tool: $0) }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search tools")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(model.searchText.isEmpty ? "\(model.visibleTools.count) tools" : "\(model.filteredTools.count) of \(model.visibleTools.count) tools")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings (⌘,)").accessibilityLabel("Settings")
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func toolRows(ids: [String], section: String) -> some View {
        ForEach(ids.compactMap { model.registry.tool($0) }) { ToolRow(tool: $0, section: section) }
    }
}

struct ToolRow: View {
    let tool: AnyTool
    /// Non-nil for rows in the shortcut sections; their tag is "<section>:<tool id>".
    var section: String?

    static func toolID(from key: String) -> String {
        for prefix in ["fav:", "freq:"] where key.hasPrefix(prefix) { return String(key.dropFirst(prefix.count)) }
        return key
    }
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow // url-scheme:

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 0) {
                Text(tool.name)
                if !model.searchText.isEmpty { Text(tool.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        } icon: {
            // Scaled to fit so wide symbols (e.g. "abc", "123") keep the label column aligned.
            Image(systemName: tool.symbol)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .frame(width: 17, height: 15)
                .frame(width: 20, alignment: .center)
        }
        .tag(section.map { "\($0):\(tool.id)" } ?? tool.id)
        .contextMenu {
            Button("Open in new window") { openNewWindow(tool) }
            Button(model.favourites.contains(tool.id) ? "Remove from Favourites" : "Add to Favourites") {
                let on = !model.favourites.contains(tool.id)
                Task { try? await DataStore.shared.setFavourite(tool.id, on); await model.refreshUsage() }
            }
            Divider()
            Button("Hide tool") { model.settings.hiddenTools.append(tool.id) }
            Button("Copy tool ID") { Clipboard.copy(tool.id) }
        }
    }

    private func openNewWindow(_ tool: AnyTool) {
        // url-scheme: a new, independent window (own AppModel/sessions) showing this tool.
        openWindow(id: "tool-window", value: "\(tool.id)#\(UUID().uuidString)")
    }
}
