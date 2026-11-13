import SwiftUI
import BitlatheCore
import BitlatheUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedToolID) {
            if model.searchText.isEmpty {
                if !model.favourites.isEmpty {
                    Section("Favourites") { toolRows(ids: model.favourites) }
                }
                if model.settings.showFrequentlyUsed, !model.frequent.isEmpty {
                    Section("Frequently used") { toolRows(ids: model.frequent) }
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
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings (⌘,)")
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func toolRows(ids: [String]) -> some View {
        ForEach(ids.compactMap { model.registry.tool($0) }) { ToolRow(tool: $0) }
    }
}

struct ToolRow: View {
    let tool: AnyTool
    @Environment(AppModel.self) private var model

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 0) {
                Text(tool.name)
                if !model.searchText.isEmpty { Text(tool.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        } icon: {
            Image(systemName: tool.symbol)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 20, alignment: .center)
        }
        .tag(tool.id)
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
        // Opens an additional main window; the new window selects the tool.
        if let url = URL(string: "bitlathe://tool/\(tool.id)") { NSWorkspace.shared.open(url) }
    }
}
