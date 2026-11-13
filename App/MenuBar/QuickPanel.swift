import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

/// State behind the Quick Panel: the Smart Box's reading of the clipboard (same detection, typed instructions, chains
/// and learned order as the home screen) plus the computed result of the chosen action.
@MainActor
@Observable
final class QuickPanelModel {
    struct Computed: Equatable {
        /// The action that produced the result; a chained action when a second step ran (Base64 → JSON).
        var action: SmartBox.Action
        var output: String
        /// Labelled facts for tools whose result is a table rather than text (number bases, timestamps, CIDR…).
        var rows: [MetaRow] = []
        var error: String?

        /// What Copy puts on the clipboard: the text output, or the facts as "Label: value" lines.
        var copyText: String {
            if !output.isEmpty { return output }
            return rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
        }
    }

    var clipboardText: String = ""
    private(set) var analysis: SmartBox.Analysis?
    var candidates: [SmartBox.Action] = []
    var selected = 0
    var computed: Computed?
    var isRunning = false
    /// The fact row most recently copied by clicking it, for a brief checkmark.
    var copiedRowID: String?
    private var runTask: Task<Void, Never>?
    private var learned: SmartBox.Learned = [:]

    var current: SmartBox.Action? { candidates.indices.contains(selected) ? candidates[selected] : nil }
    var alternatives: [(index: Int, action: SmartBox.Action)] {
        candidates.enumerated().filter { $0.offset != selected }.prefix(4).map { ($0.offset, $0.element) }
    }
    var isSensitive: Bool { analysis?.isSensitive ?? false }

    /// Reads the clipboard, works out what it is, and runs the top action.
    func refresh() {
        let text = Clipboard.string ?? ""
        clipboardText = text
        analysis = nil
        candidates = []
        computed = nil
        copiedRowID = nil
        selected = 0
        guard !text.isEmpty, text.utf8.count < DetectionEngine.maxInputBytes else { return }
        analyse(text)
        // The remembered choices are read from disk; if they differ from the last copy, order again with them.
        Task { [weak self] in
            let loaded = (try? await DataStore.shared.choices()) ?? [:]
            guard let self, loaded != self.learned else { return }
            self.learned = loaded
            if self.clipboardText == text, self.selected == 0 { self.analyse(text) }
        }
    }

    private func analyse(_ text: String) {
        analysis = Self.read(text, learned: learned)
        candidates = analysis?.actions ?? []
        selected = 0
        runCurrent()
    }

    /// Prose is not worth a panel: only recognised data, commands and instructions count.
    private static func read(_ text: String, learned: SmartBox.Learned) -> SmartBox.Analysis? {
        guard var a = SmartBox.analyse(text, tools: ToolRegistry.shared.tools, ignoring: Set(Settings.shared.detectionIgnoreList),
                                       learned: learned, limit: 5) else { return nil }
        a.actions.removeAll { $0.opensTool }
        guard !a.actions.isEmpty, a.kind != .words || a.formatKey == "lines" else { return nil }
        return a
    }

    func select(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        selected = index
        copiedRowID = nil
        runCurrent()
    }

    private func runCurrent() {
        runTask?.cancel()
        guard let action = current else { computed = nil; return }
        isRunning = true
        let text = clipboardText
        // Only the first suggestion chains by itself; picking an alternative means wanting exactly that.
        let counts = selected == 0 ? learned[analysis?.formatKey ?? ""] ?? [:] : nil
        runTask = Task { [weak self] in
            let computed = await Self.run(action, on: text, chainCounts: counts)
            guard !Task.isCancelled else { return }
            self?.computed = computed
            self?.isRunning = false
        }
    }

    /// Runs an action, then a second step when its output is itself data (Base64 that hides JSON), unless the
    /// person has more often taken the first step alone. `chainCounts` nil means never chain.
    private static func run(_ action: SmartBox.Action, on text: String, chainCounts: [String: Int]?) async -> Computed {
        do {
            var out = try await action.tool.run(text: action.inputOverride ?? text, options: action.options)
            var used = action
            if let counts = chainCounts, let chain = SmartBox.chain(after: action, output: out.text, tools: ToolRegistry.shared.tools),
               let step = chain.then, (counts[chain.key] ?? 0) >= (counts[action.key] ?? 0),
               let second = try? await step.tool.run(text: out.text, options: step.options) {
                out = second
                used = chain
            }
            return Computed(action: used, output: out.payload.text ?? "", rows: out.metadata, error: nil)
        } catch {
            return Computed(action: action, output: "", error: (error as? ToolError)?.message ?? error.localizedDescription)
        }
    }

    /// Copying a result is accepting it: counted for this kind of data, as on the home screen.
    func learn() {
        guard let a = analysis, let key = computed?.action.key, computed?.error == nil else { return }
        learned[a.formatKey, default: [:]][key, default: 0] += 1
        let format = a.formatKey
        Task { try? await DataStore.shared.recordChoice(format: format, action: key) }
    }

    /// The top result, for the Option-click path (no panel).
    func topOutput() async -> String? {
        let text = Clipboard.string ?? ""
        guard !text.isEmpty, text.utf8.count < DetectionEngine.maxInputBytes else { return nil }
        learned = (try? await DataStore.shared.choices()) ?? learned
        guard let a = Self.read(text, learned: learned), let best = a.actions.first else { return nil }
        let result = await Self.run(best, on: text, chainCounts: learned[a.formatKey] ?? [:])
        guard result.error == nil else { return nil }
        let s = result.copyText
        return s.isEmpty ? nil : s
    }
}

struct QuickPanelView: View {
    @Bindable var model: QuickPanelModel
    var copy: () -> Void
    var openInApp: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if let current = model.current {
                header(current)
                preview
                if !model.alternatives.isEmpty { alsoTry }
                footer
            } else {
                empty
            }
        }
        .padding(Space.lg)
        .frame(width: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
        // Hidden buttons own the keyboard shortcuts (the panel is key but never activates the app).
        .background(shortcuts)
    }

    private func header(_ picked: SmartBox.Action) -> some View {
        // Once it has run, show what ran: the first suggestion may have chained a second step.
        let r = model.computed?.action.tool.id == picked.tool.id ? model.computed?.action ?? picked : picked
        return HStack(spacing: Space.sm) {
            Image(systemName: r.tool.symbol).font(.title3).foregroundStyle(Palette.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text([r.title, r.detail].compactMap { $0 }.joined(separator: " · ")).font(.headline).lineLimit(1)
                Text(r.learned > 0 ? "Your usual for this kind of data" : r.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.isSensitive {
                Label("Secret", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.warning)
                    .padding(.horizontal, Space.sm).padding(.vertical, 1)
                    .background(Palette.warning.opacity(0.12), in: Capsule())
                    .help("Looks like a credential or key. It stays on this Mac.")
            }
            if model.isRunning { ProgressView().controlSize(.small) }
        }
    }

    private var preview: some View {
        Group {
            if let c = model.computed, let err = c.error {
                Label(err, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Palette.warning)
            } else if let c = model.computed, !c.output.isEmpty {
                Text(c.output)
                    .font(Typography.captionMono)
                    .lineLimit(8)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let c = model.computed, !c.rows.isEmpty {
                facts(c.rows)
            } else if model.computed != nil {
                Text("No text output. Open in Bitlathe to see the result.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text(" ").font(Typography.captionMono)
            }
        }
        .padding(Space.sm + Space.xs)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    /// Facts as label/value rows; clicking a row copies just that value.
    private func facts(_ rows: [MetaRow]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.xs) {
            ForEach(rows.prefix(8)) { row in
                GridRow {
                    Text(row.label).font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Button {
                        Clipboard.copy(row.value, toast: nil)
                        model.copiedRowID = row.id
                    } label: {
                        HStack(spacing: Space.sm) {
                            Text(row.value).font(Typography.captionMono).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: Space.sm)
                            Image(systemName: model.copiedRowID == row.id ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(model.copiedRowID == row.id ? Palette.success : Palette.subtle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy \(row.label)")
                    .accessibilityLabel("\(row.label), \(row.value). Copy")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// As many alternatives as fit with their names in full; a cut-off "St…" tells nobody anything.
    private var alsoTry: some View {
        ViewThatFits(in: .horizontal) {
            ForEach([4, 3, 2, 1], id: \.self) { count in alsoTryRow(count) }
        }
    }

    private func alsoTryRow(_ count: Int) -> some View {
        HStack(spacing: Space.sm) {
            Text("Also try").font(.caption).foregroundStyle(.secondary).fixedSize()
            ForEach(Array(model.alternatives.prefix(count).enumerated()), id: \.element.action.key) { slot, alt in
                Button { model.select(alt.index) } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: alt.action.tool.symbol).font(.caption2)
                        Text(alt.action.title).lineLimit(1)
                        Text("⌘\(slot + 1)").foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .fixedSize()
                    .padding(.horizontal, Space.sm).padding(.vertical, Space.xs)
                    .background(Palette.raised, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("\(alt.action.reason) (⌘\(slot + 1))")
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Button("Open in Bitlathe", action: openInApp).controlSize(.regular)
            Spacer()
            Button(action: copy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled((model.computed?.copyText ?? "").isEmpty)
            .help("Copy result (Return)")
        }
    }

    private var empty: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "doc.on.clipboard").font(.largeTitle).foregroundStyle(.secondary)
            Text(model.clipboardText.isEmpty ? "The clipboard is empty" : "Nothing recognised on the clipboard").font(.headline)
            Text("Copy some JSON, a JWT, a timestamp, a colour, or an instruction such as “sha256 hello”, then open this panel again.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Bitlathe", action: openInApp).padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.md)
    }

    private var shortcuts: some View {
        ZStack {
            Button("", action: copy).keyboardShortcut(.defaultAction).disabled((model.computed?.copyText ?? "").isEmpty)
            Button("", action: close).keyboardShortcut(.cancelAction)
            ForEach(0..<4, id: \.self) { i in
                Button("") { if i < model.alternatives.count { model.select(model.alternatives[i].index) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Non-activating floating panel that can still take key presses.
final class QuickNSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onResign: (() -> Void)?
    override func resignKey() { super.resignKey(); onResign?() }
}
