import SwiftUI
import BitlatheCore
import BitlatheUI

private enum PickerMetrics {
    static let width: CGFloat = 560
    static let listMaxHeight: CGFloat = 360
    static let rowHeight: CGFloat = 40
    static let iconSize: CGFloat = 26
    static let shadow: Double = 0.28
    static let maxResults = 40
}

/// Floating, keyboard-driven tool picker. Recent tools lead when the query is empty.
struct ScratchpadPicker: View {
    let model: ScratchpadModel
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var rows: [AnyTool] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let eligible = Set(model.eligibleTools.map(\.id))
        if q.isEmpty {
            let recent = model.recentTools
            let recentIDs = Set(recent.map(\.id))
            return recent + model.eligibleTools.filter { !recentIDs.contains($0.id) }
        }
        return Array(model.registry.search(q, limit: 200).filter { eligible.contains($0.id) }.prefix(PickerMetrics.maxResults))
    }
    private var recentCount: Int { query.trimmingCharacters(in: .whitespaces).isEmpty ? model.recentTools.count : 0 }

    var body: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                Image(systemName: "wand.and.stars").font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Apply a tool to the \(model.targetDescription)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { choose(rows) }
                    .onKeyPress(.downArrow) { move(1, count: rows.count); return .handled }
                    .onKeyPress(.upArrow) { move(-1, count: rows.count); return .handled }
                    .onKeyPress(.escape) { model.closePicker(); return .handled }
                    .accessibilityLabel("Search tools")
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md + Space.xs)
            Divider()
            if rows.isEmpty {
                Text("No text tool matches “\(query)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.xxl)
            } else {
                list(rows)
            }
            Divider()
            HStack(spacing: Space.md) {
                Text("↩ apply to \(model.targetDescription)")
                Spacer()
                Text("↑↓ navigate  ⎋ close")
            }
            .font(Typography.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
        }
        .frame(width: PickerMetrics.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Palette.separator))
        .shadow(color: .black.opacity(PickerMetrics.shadow), radius: Space.xl, y: Space.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool picker")
        .onChange(of: query) { selection = 0 }
        .task {
            #if DEBUG
            if let q = UserDefaults.standard.string(forKey: "BLScratchpadPicker"), !q.isEmpty, q != "YES" { query = q }
            #endif
            focused = true
        }
        .onExitCommand { model.closePicker() }
    }

    private func list(_ rows: [AnyTool]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, tool in
                        if index == 0 && recentCount > 0 { sectionHeader("Recent") }
                        if index == recentCount && recentCount > 0 { sectionHeader("All Text Tools") }
                        row(tool, selected: index == selection)
                            .id(tool.id)
                            .onTapGesture { model.apply(tool) }
                    }
                }
                .padding(Space.xs)
            }
            .frame(height: min(PickerMetrics.listMaxHeight, CGFloat(rows.count + (recentCount > 0 ? 2 : 0)) * PickerMetrics.rowHeight + Space.sm))
            .onChange(of: selection) { _, new in
                if rows.indices.contains(new) { proxy.scrollTo(rows[new].id) }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.md)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xxs)
    }

    private func row(_ tool: AnyTool, selected: Bool) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: tool.symbol)
                .font(.system(size: 13))
                .frame(width: PickerMetrics.iconSize, height: PickerMetrics.iconSize)
                .background(selected ? Color.white.opacity(0.2) : Palette.raised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .accessibilityHidden(true)
            Text(tool.name).fontWeight(.medium).lineLimit(1)
            Text(tool.summary).foregroundStyle(selected ? Color.white.opacity(0.8) : .secondary).lineLimit(1)
            Spacer(minLength: 0)
            if tool.id == model.lastToolID { Text("last").font(.caption2).foregroundStyle(selected ? Color.white.opacity(0.8) : .secondary) }
        }
        .font(.callout)
        .foregroundStyle(selected ? Color.white : .primary)
        .padding(.horizontal, Space.md)
        .frame(height: PickerMetrics.rowHeight)
        .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func choose(_ rows: [AnyTool]) {
        guard rows.indices.contains(selection) else { return }
        model.apply(rows[selection])
    }
}
