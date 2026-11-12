import SwiftUI
import BitlatheCore
import BitlatheUI

/// The inspector's History tab: search, pinned inputs, and recent runs grouped by day.
struct InspectorHistoryView: View {
    @Bindable var session: ToolSession
    @State private var settings = Settings.shared
    @State private var entries: [HistoryEntry] = []
    @State private var query = ""
    @State private var confirmClear = false

    private var toolID: String { session.tool.id }
    private var enabled: Bool { settings.isHistoryEnabled(for: toolID) }
    private var pinned: [HistoryEntry] { entries.filter(\.pinned) }
    private var recent: [HistoryEntry] { entries.filter { !$0.pinned } }

    var body: some View {
        VStack(spacing: 0) {
            if !enabled { disabledBanner }
            if !entries.isEmpty || !query.isEmpty { searchField }
            content
            Divider()
            footer
        }
        .task(id: toolID) { await reload() }
        .task(id: session.runCount) {
            // History is written ~2s after a successful run; refresh now and once more after it lands.
            await reload()
            try? await Task.sleep(for: .milliseconds(2400))
            guard !Task.isCancelled else { return }
            await reload()
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await reload()
        }
        .confirmationDialog("Clear history for \(session.tool.name)?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                Task {
                    try? await DataStore.shared.clearHistory(toolID: toolID)
                    await reload()
                }
            }
        } message: {
            Text("Recent inputs for this tool are removed. Pinned inputs are kept.")
        }
    }

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search history", text: $query).textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs + Space.xxs)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.small))
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }

    @ViewBuilder private var content: some View {
        if entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !pinned.isEmpty {
                        sectionHeader("Pinned", symbol: "pin.fill")
                        ForEach(pinned) { row($0) }
                    }
                    ForEach(DayBucket.allCases, id: \.self) { bucket in
                        let items = recent.filter { DayBucket(for: $0.createdAt) == bucket }
                        if !items.isEmpty {
                            sectionHeader(bucket.title, symbol: nil)
                            ForEach(items) { row($0) }
                        }
                    }
                }
                .padding(.bottom, Space.sm)
            }
        }
    }

    private func row(_ e: HistoryEntry) -> some View {
        HistoryRow(entry: e, tool: session.tool,
                   onRestore: { restore(e) },
                   onPin: { title in pin(e, title: title) },
                   onUnpin: { pin(e, title: nil) },
                   onCopy: { Clipboard.copy(e.input) },
                   onDelete: { delete(e) })
    }

    private func sectionHeader(_ title: String, symbol: String?) -> some View {
        HStack(spacing: Space.xs) {
            if let symbol { Image(systemName: symbol).font(.caption2) }
            Text(title.uppercased()).font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.md)
        .padding(.top, Space.md)
        .padding(.bottom, Space.xs)
        .accessibilityAddTraits(.isHeader)
    }

    private var emptyState: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: query.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
            Text(query.isEmpty ? (enabled ? "No history yet" : "Nothing is being recorded") : "No matches")
                .font(Typography.headline)
            Text(emptyMessage)
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if !query.isEmpty { return "Nothing in \(session.tool.name) history matches \u{201C}\(query)\u{201D}." }
        if !enabled { return "Turn history on below to keep recent inputs for this tool." }
        return "Inputs you run in \(session.tool.name) show up here with the options you used. Pin the ones you want to keep, like a saved regex or schedule."
    }

    private var disabledBanner: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "eye.slash").foregroundStyle(Palette.warning)
            Text("History is off for this tool").font(.callout.weight(.medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Palette.warning.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Toggle(isOn: Binding(get: { enabled }, set: { setEnabled($0) })) {
                Text("Keep history for this tool").font(.callout)
            }
            .toggleStyle(.checkbox)
            .disabled(!settings.historyEnabled)
            Text(settings.historyEnabled
                 ? "Inputs are stored only on this Mac. Tools that handle secrets (JWT, AES, password hashing) are off by default so tokens, keys and passwords are never saved."
                 : "History is turned off for every tool in Settings.")
                .font(.caption).foregroundStyle(.secondary)
            Button(role: .destructive) { confirmClear = true } label: {
                Label("Clear history for this tool\u{2026}", systemImage: "trash")
            }
            .buttonStyle(.plain).foregroundStyle(Palette.danger).font(.callout)
            .disabled(recent.isEmpty)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func setEnabled(_ on: Bool) {
        if on { settings.historyDisabledTools.removeAll { $0 == toolID } }
        else if !settings.historyDisabledTools.contains(toolID) { settings.historyDisabledTools.append(toolID) }
    }

    private func restore(_ e: HistoryEntry) {
        session.options = session.tool.optionFields.defaults.merging(e.options) { _, new in new }
        session.inputText = e.input
    }

    private func pin(_ e: HistoryEntry, title: String?) {
        let shouldPin = title != nil
        Task {
            try? await DataStore.shared.setPinned(e.id, shouldPin, title: title)
            await reload()
        }
    }

    private func delete(_ e: HistoryEntry) {
        Task {
            try? await DataStore.shared.deleteHistory(id: e.id)
            await reload()
        }
    }

    private func reload() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = (try? await DataStore.shared.history(toolID: toolID, query: q, limit: 200)) ?? []
        guard !Task.isCancelled else { return }
        entries = list
    }
}

// MARK: - Day buckets

private enum DayBucket: CaseIterable {
    case today, yesterday, thisWeek, older

    init(for date: Date, now: Date = .now, calendar: Calendar = .current) {
        if calendar.isDate(date, inSameDayAs: now) { self = .today }
        else if calendar.isDateInYesterday(date) { self = .yesterday }
        else if let week = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)), date >= week { self = .thisWeek }
        else { self = .older }
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .older: "Older"
        }
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let entry: HistoryEntry
    let tool: AnyTool
    let onRestore: () -> Void
    let onPin: (String) -> Void
    let onUnpin: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var showPinPopover = false
    @State private var pinTitle = ""

    /// Options that differ from the tool's defaults, as short labels.
    private var chips: [String] {
        tool.optionFields.compactMap { f in
            if case .secret = f.kind { return nil }
            guard let v = entry.options[f.key], v != f.defaultValue else { return nil }
            switch (f.kind, v) {
            case (.toggle, .bool(let b)): return b ? f.label : "No \(f.label)"
            case (.picker(let cs), .string(let s)), (.segmented(let cs), .string(let s)):
                return cs.first { $0.value == s }?.label ?? s
            default:
                let d = v.description
                return d.isEmpty ? nil : "\(f.label): \(d.prefix(16))"
            }
        }
    }

    private var preview: String {
        entry.input.split(separator: "\n", omittingEmptySubsequences: true).prefix(2)
            .map { String($0.prefix(140)) }.joined(separator: "\n")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onRestore) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    if let t = entry.title, !t.isEmpty {
                        Text(t).font(.callout.weight(.semibold)).lineLimit(1)
                    }
                    Text(preview).font(Typography.monoSmall).lineLimit(2).truncationMode(.tail)
                        .foregroundStyle(entry.title.map { !$0.isEmpty } ?? false ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: Space.xs) {
                        Text(entry.createdAt, format: .relative(presentation: .named))
                            .font(.caption2).foregroundStyle(.secondary)
                        ForEach(chips.prefix(3), id: \.self) { c in
                            Text(c).font(.caption2).lineLimit(1)
                                .padding(.horizontal, Space.xs + Space.xxs).padding(.vertical, 1)
                                .background(Palette.raised, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        if chips.count > 3 { Text("+\(chips.count - 3)").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                .padding(.horizontal, Space.sm + Space.xxs)
                .padding(.vertical, Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering ? Palette.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: Radius.small))
                .contentShape(RoundedRectangle(cornerRadius: Radius.small))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Restores this input and its options")

            if hovering || showPinPopover { actions }
        }
        .padding(.horizontal, Space.sm)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(entry.pinned ? "Unpin" : "Pin\u{2026}", systemImage: entry.pinned ? "pin.slash" : "pin") { togglePin() }
            Button("Copy", systemImage: "doc.on.doc", action: onCopy)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var actions: some View {
        HStack(spacing: Space.xxs) {
            iconButton(entry.pinned ? "pin.slash" : "pin", entry.pinned ? "Unpin" : "Pin") { togglePin() }
                .popover(isPresented: $showPinPopover, arrowEdge: .bottom) { pinPopover }
            iconButton("doc.on.doc", "Copy", action: onCopy)
            iconButton("trash", "Delete", action: onDelete)
        }
        .padding(Space.xxs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.small))
        .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Palette.separator))
        .padding(Space.xs)
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption).frame(width: Space.xl - Space.xs, height: Space.xl - Space.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private func togglePin() {
        if entry.pinned { onUnpin() } else { pinTitle = entry.title ?? ""; showPinPopover = true }
    }

    private var pinPopover: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Pin this input").font(Typography.headline)
            TextField("Title (optional)", text: $pinTitle)
                .textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit(commitPin)
            HStack {
                Spacer()
                Button("Cancel") { showPinPopover = false }.keyboardShortcut(.cancelAction)
                Button("Pin", action: commitPin).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.md)
    }

    private func commitPin() {
        showPinPopover = false
        onPin(pinTitle.trimmingCharacters(in: .whitespaces))
    }
}
