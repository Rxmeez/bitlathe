import SwiftUI
import BitlatheCore
import BitlatheUI

/// The Clipboard sidebar destination: searchable list of captured developer-format items.
struct ClipboardView: View {
    @Environment(AppModel.self) private var model
    private let monitor = ClipboardMonitor.shared
    @State private var entries: [ClipboardEntry] = []
    @State private var query = ""
    @State private var loaded = false
    @State private var confirmClear = false
    @State private var hovered: Int64?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.editorBackground)
        .task(id: monitor.revision) { await reload() }
        .task(id: query) { await reload() }
        .confirmationDialog("Delete all clipboard history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { monitor.clearAll() }
        } message: {
            Text("This removes every captured item from this Mac. It can’t be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Clipboard").font(Typography.title)
                Text("Developer formats you copied, kept on this Mac only").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: Space.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Space.sm)
            .frame(width: 220, height: 26)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.small))
            Button(role: .destructive) { confirmClear = true } label: { Label("Clear All", systemImage: "trash") }
                .disabled(entries.isEmpty && query.isEmpty)
                .help("Delete all clipboard history")
        }
        .padding(.horizontal, Space.lg)
        .frame(height: Layout.headerHeight + Space.md)
    }

    @ViewBuilder
    private var content: some View {
        if !loaded {
            Color.clear
        } else if entries.isEmpty {
            if query.isEmpty {
                ContentUnavailableView("Nothing captured yet", systemImage: "list.clipboard",
                                       description: Text("Copy JSON, a JWT, a UUID, a timestamp or another developer format and it shows up here. Passwords and concealed items are never recorded."))
            } else {
                ContentUnavailableView.search(text: query)
            }
        } else {
            List {
                ForEach(entries) { entry in
                    ClipboardRow(entry: entry, hovering: hovered == entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture { open(entry) }
                        .onHover { hovered = $0 ? entry.id : (hovered == entry.id ? nil : hovered) }
                        .contextMenu {
                            Button("Open in \(toolName(entry))") { open(entry) }
                            Button("Copy") { Clipboard.copy(entry.content) }
                            Divider()
                            Button("Delete", role: .destructive) { monitor.delete(entry) }
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Open") { open(entry) }
                        .accessibilityAction(named: "Delete") { monitor.delete(entry) }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .bottom) {
                Text("\(entries.count) item\(entries.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .padding(.horizontal, Space.md).padding(.vertical, Space.xs)
                    .background(.regularMaterial, in: Capsule())
                    .padding(Space.md)
            }
        }
    }

    private func toolName(_ e: ClipboardEntry) -> String {
        e.detectedToolID.flatMap { model.registry.tool($0)?.name } ?? "Tool"
    }

    private func open(_ e: ClipboardEntry) {
        guard let id = e.detectedToolID, model.registry.tool(id) != nil else { return }
        model.open(toolID: id, input: e.content)
    }

    private func reload() async {
        if !query.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
        guard !Task.isCancelled else { return }
        entries = (try? await DataStore.shared.clipboard(query: query, limit: 300)) ?? []
        loaded = true
    }
}

private struct ClipboardRow: View {
    @Environment(AppModel.self) private var model
    let entry: ClipboardEntry
    let hovering: Bool
    private let monitor = ClipboardMonitor.shared

    var body: some View {
        let source = SourceApp.info(entry.sourceApp)
        let tool = entry.detectedToolID.flatMap { model.registry.tool($0) }
        HStack(alignment: .top, spacing: Space.md) {
            Group {
                if let icon = source?.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app.dashed").resizable().scaledToFit().padding(4).foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(preview)
                    .font(Typography.captionMono)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Space.sm) {
                    if let tool {
                        Label(tool.name, systemImage: tool.symbol)
                            .font(.caption)
                            .padding(.horizontal, Space.sm).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(meta(source?.name)).font(.caption).foregroundStyle(.secondary)
                }
            }

            Button { monitor.delete(entry) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
                .help("Delete this item")
                .accessibilityLabel("Delete")
        }
        .padding(.vertical, Space.xs)
    }

    private var preview: String {
        let flat = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        return String(flat.prefix(220))
    }

    private func meta(_ app: String?) -> String {
        let age = Date.now.timeIntervalSince(entry.createdAt)
        let when = age < 60 ? "Just now" : RelativeDateTimeFormatter.shared.localizedString(for: entry.createdAt, relativeTo: .now)
        return [app, when].compactMap { $0 }.joined(separator: " · ")
    }
}

private extension RelativeDateTimeFormatter {
    @MainActor static let shared: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
