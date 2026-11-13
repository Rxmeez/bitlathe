import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

/// State behind the Quick Panel: detection over the clipboard plus the computed result of the chosen tool.
@MainActor
@Observable
final class QuickPanelModel {
    struct Computed: Equatable {
        var result: DetectionResult
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
    var candidates: [DetectionResult] = []
    var selected = 0
    var computed: Computed?
    var isRunning = false
    /// The fact row most recently copied by clicking it, for a brief checkmark.
    var copiedRowID: String?
    private var runTask: Task<Void, Never>?

    var current: DetectionResult? { candidates.indices.contains(selected) ? candidates[selected] : nil }
    var alternatives: [(index: Int, result: DetectionResult)] {
        candidates.enumerated().filter { $0.offset != selected }.prefix(4).map { ($0.offset, $0.element) }
    }

    /// Reads the clipboard, detects, and runs the top result.
    func refresh() {
        let text = Clipboard.string ?? ""
        clipboardText = text
        candidates = []
        computed = nil
        copiedRowID = nil
        selected = 0
        guard !text.isEmpty, text.utf8.count < DetectionEngine.maxInputBytes else { return }
        let report = DetectionEngine.detect(text, tools: ToolRegistry.shared.tools,
                                            ignoring: Set(Settings.shared.detectionIgnoreList))
        candidates = Array(report.results.prefix(5))
        runCurrent()
    }

    func select(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        selected = index
        copiedRowID = nil
        runCurrent()
    }

    private func runCurrent() {
        runTask?.cancel()
        guard let result = current else { computed = nil; return }
        isRunning = true
        let text = clipboardText
        runTask = Task { [weak self] in
            let computed: Computed
            do {
                let out = try await result.tool.run(text: text, options: result.score.options)
                computed = Computed(result: result, output: out.payload.text ?? "", rows: out.metadata, error: nil)
            } catch {
                computed = Computed(result: result, output: "", error: (error as? ToolError)?.message ?? error.localizedDescription)
            }
            guard !Task.isCancelled else { return }
            self?.computed = computed
            self?.isRunning = false
        }
    }

    /// Computes the top result synchronously enough for the Option-click path.
    func topOutput() async -> String? {
        let text = Clipboard.string ?? ""
        guard !text.isEmpty, text.utf8.count < DetectionEngine.maxInputBytes else { return nil }
        let report = DetectionEngine.detect(text, tools: ToolRegistry.shared.tools, ignoring: Set(Settings.shared.detectionIgnoreList))
        guard let best = report.best, let out = try? await best.tool.run(text: text, options: best.score.options) else { return nil }
        let s = Computed(result: best, output: out.payload.text ?? "", rows: out.metadata).copyText
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

    private func header(_ r: DetectionResult) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: r.tool.symbol).font(.title3).foregroundStyle(Palette.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(r.tool.name).font(.headline)
                Text(r.score.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
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

    private var alsoTry: some View {
        HStack(spacing: Space.sm) {
            Text("Also try").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(model.alternatives.enumerated()), id: \.element.result.id) { slot, alt in
                Button { model.select(alt.index) } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: alt.result.tool.symbol).font(.caption2)
                        Text(alt.result.tool.name).lineLimit(1)
                        Text("⌘\(slot + 1)").foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .padding(.horizontal, Space.sm).padding(.vertical, Space.xs)
                    .background(Palette.raised, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Show \(alt.result.tool.name) (⌘\(slot + 1))")
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
            Text("Copy some JSON, a JWT, a timestamp, a colour, or any developer text, then open this panel again.")
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
