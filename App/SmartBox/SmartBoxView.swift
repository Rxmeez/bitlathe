import SwiftUI
import BitlatheCore
import BitlatheUI

private enum SmartMetrics {
    static let minInput: CGFloat = 96
    static let maxInputFraction: CGFloat = 0.42
    static let inputPadding = EdgeInsets(top: Space.lg, leading: Space.xl, bottom: Space.lg, trailing: Space.xl)
    static let maxActionsWithShortcuts = 6
    static let emptyWidth: CGFloat = 620
}

/// Bitlathe's home: one box. Paste or type anything; it is recognised, the most likely action runs at once, and
/// alternatives sit one key away. Accepting a result teaches the ranking.
struct SmartBoxView: View {
    @Bindable var model: SmartBoxModel
    @Environment(AppModel.self) private var app
    @State private var editor = EditorController()

    var body: some View {
        let config = Self.editorConfig
        GeometryReader { geo in
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    CodeEditor(text: $model.text, language: model.inputLanguage, placeholder: "", config: config, controller: editor)
                        .accessibilityLabel("Smart Box input")
                    if model.isEmpty {
                        HomeEmptyState(model: model, minHeight: geo.size.height - Layout.statusHeight) { editor.focus() }
                    }
                }
                .frame(height: model.isEmpty ? nil : inputHeight(total: geo.size.height, width: geo.size.width, config: config))
                .frame(maxHeight: model.isEmpty ? .infinity : nil)

                if let analysis = model.analysis {
                    Divider()
                    SuggestionBar(model: model, analysis: analysis)
                    Divider()
                    SmartResult(model: model)
                        .frame(maxHeight: .infinity)
                }
                SmartStatusBar(model: model)
            }
        }
        .background(Palette.editorBackground)
        .background(shortcuts)
        .focusedSceneValue(\.toolSession, model.resultSession)
        .focusedSceneValue(\.smartBox, model)
        .onAppear {
            Task { await model.reloadMemory() }
            DispatchQueue.main.async { editor.focus() }
        }
    }

    /// No gutter or current-line band: the home box should read as a plain field, not a code editor.
    static var editorConfig: EditorConfig {
        var c = EditorConfig.current
        c.lineNumbers = false
        c.highlightCurrentLine = false
        c.wrap = true
        c.horizontalInset = Space.lg - 5   // the text container pads 5 pt itself: 16 pt in all, like the bars below
        return c
    }

    /// Grows with the content (one line stays compact) up to 42 % of the window, so the result keeps the room.
    private func inputHeight(total: CGFloat, width: CGFloat, config: EditorConfig) -> CGFloat {
        let lineHeight = config.fontSize * 1.5
        let charWidth = max(config.fontSize * 0.6, 1)
        let columns = max(Int((width - SmartMetrics.inputPadding.leading * 2) / charWidth), 20)
        var lines = 0
        for line in model.text.split(separator: "\n", omittingEmptySubsequences: false).prefix(400) {
            lines += max(1, Int((Double(line.count) / Double(columns)).rounded(.up)))
            if lines > 400 { break }
        }
        let needed = CGFloat(lines) * lineHeight + SmartMetrics.inputPadding.top * 2 + Space.lg
        return min(max(needed, SmartMetrics.minInput), total * SmartMetrics.maxInputFraction)
    }

    /// Keyboard: ⌘↩ copy, ⇧⌘↩ replace, ⌥↩ open the full tool, ⌘1–6 pick an action, Esc clears.
    private var shortcuts: some View {
        ZStack {
            Button("Copy result") { model.copy() }.keyboardShortcut(.return, modifiers: .command)
            Button("Replace with result") { model.replace() }.keyboardShortcut(.return, modifiers: [.command, .shift])
            Button("Open tool") { model.openTool() }.keyboardShortcut(.return, modifiers: .option)
            Button("Clear") { model.clear(); editor.focus() }.keyboardShortcut(.cancelAction).disabled(model.isEmpty || app.showPalette)
            ForEach(0..<SmartMetrics.maxActionsWithShortcuts, id: \.self) { i in
                Button("Action \(i + 1)") { model.choose(i) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }
}

// MARK: - Empty state

private struct HomeEmptyState: View {
    let model: SmartBoxModel
    /// The visible height, so a short page sits in the middle of the window instead of hugging the top.
    let minHeight: CGFloat
    let focus: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                VStack(spacing: Space.sm) {
                    (Text("Paste ") + Text("anything").foregroundStyle(LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.7)], startPoint: .leading, endPoint: .trailing)) + Text("."))
                        .font(.system(size: 30, weight: .semibold))
                    Text("Bitlathe works out what it is and what you usually do with it.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                BoxPrompt(action: focus)
                if let report = app.detectionReport, let best = report.best, let text = app.detectedText {
                    Button { model.paste(text) } label: {
                        HStack(spacing: Space.sm) {
                            Image(systemName: "doc.on.clipboard").foregroundStyle(Palette.accent)
                            Text("On your clipboard: **\(best.score.reason)**")
                            Spacer()
                            Text("Paste ⌘V").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, Space.md).padding(.vertical, Space.sm + 2)
                        .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Put the clipboard in the box")
                }
                if !model.recent.isEmpty {
                    section("Pick up where you left off") {
                        VStack(spacing: 0) {
                            ForEach(Array(model.recent.enumerated()), id: \.element.id) { i, entry in
                                if i > 0 { Divider() }
                                RecentRow(entry: entry) { model.paste(entry.input) }
                            }
                        }
                        .background(Palette.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.separator.opacity(0.6)))
                    }
                }
                if !model.usual.isEmpty {
                    (Text("Your usual: ") + Text(model.usual.joined(separator: "   ·   ")).foregroundStyle(.secondary))
                        .font(.caption).foregroundStyle(Palette.subtle)
                        .multilineTextAlignment(.center)
                }
                section("Try some data") {
                    FlowLayout(spacing: Space.sm, rowSpacing: Space.sm) {
                        ForEach(HomeSamples.all, id: \.label) { sample in
                            Chip(sample.label, symbol: sample.symbol) { model.paste(sample.text) }
                        }
                    }
                }
                section("Or say what you want") {
                    FlowLayout(spacing: Space.sm, rowSpacing: Space.sm) {
                        ForEach(HomeSamples.instructions, id: \.label) { sample in
                            InstructionChip(label: sample.label) { model.paste(sample.text) }
                        }
                    }
                }
            }
            .frame(maxWidth: SmartMetrics.emptyWidth)
            .padding(.horizontal, Space.xxl).padding(.vertical, Space.xl)
            // A little above centre reads as centred once the title bar is counted.
            .padding(.bottom, max(0, minHeight * 0.06))
            .frame(maxWidth: .infinity, minHeight: max(minHeight, 0))
        }
        .scrollBounceBehavior(.basedOnSize)
        // Clicks between the controls go through to the editor underneath, so you can just start typing.
        .background(Palette.editorBackground.allowsHitTesting(false))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: Space.sm) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(Palette.subtle)
            content()
        }
    }
}

/// The box, drawn: on an empty screen the editor underneath has no edges, so this shows where typing goes.
private struct BoxPrompt: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2, height: 20)
                Text("Paste or type here").foregroundStyle(Palette.subtle)
                Spacer()
                KeyHint("⌘V", "paste")
                KeyHint("⌘K", "all tools")
            }
            .font(.title3)
            .padding(.horizontal, Space.lg)
            .frame(height: 52)
            .background(Palette.raised.opacity(hovering ? 1 : 0.6), in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.accent.opacity(0.45), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Smart Box. Paste or type anything.")
    }
}

private struct KeyHint: View {
    let keys: String
    let label: String
    init(_ keys: String, _ label: String) { self.keys = keys; self.label = label }
    var body: some View {
        HStack(spacing: Space.xs) {
            Text(keys).font(.caption.monospaced().weight(.medium))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.separator))
            Text(label).font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

/// A typed instruction shown as it would be typed (monospaced, neutral), unlike the data samples.
private struct InstructionChip: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Text(label).font(Typography.captionMono)
                .padding(.horizontal, Space.md).padding(.vertical, Space.xs + 1)
                .background(hovering ? Palette.raised : Palette.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).strokeBorder(Palette.separator.opacity(0.6)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Type this in the box")
    }
}

private struct RecentRow: View {
    let entry: HistoryEntry
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Text(ToolRegistry.shared.tool(entry.toolID)?.name ?? entry.toolID)
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading).lineLimit(1)
                Text(entry.input.replacingOccurrences(of: "\n", with: " "))
                    .font(Typography.captionMono).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: Space.md)
                Text(entry.createdAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(Palette.subtle)
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm + 1)
            .background(hovering ? Palette.raised : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Put this back in the box")
    }
}

/// Starters for the empty screen: one of each kind of data the box recognises.
enum HomeSamples {
    struct Sample { let label: String; let symbol: String; let text: String }
    static let all: [Sample] = [
        Sample(label: "JSON", symbol: "curlybraces", text: #"{"name":"Bitlathe","version":"1.0","tags":["mac","dev"],"nested":{"ok":true,"count":null}}"#),
        Sample(label: "JWT", symbol: "key", text: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkFkYSBMb3ZlbGFjZSIsImlhdCI6MTUxNjIzOTAyMn0.EmiBPa0Exs9C9dSEpZD-MLrW0VjujRmRHL7LpzW1C4s"),
        Sample(label: "Timestamp", symbol: "clock", text: "1700000000"),
        Sample(label: "URL", symbol: "link", text: "https://shop.example.com/products/42?color=blue&utm_source=newsletter&utm_campaign=autumn"),
        Sample(label: "Base64", symbol: "textformat.abc", text: "eyJ1c2VyIjp7ImlkIjo0MiwibmFtZSI6IkFkYSJ9LCJhY3RpdmUiOnRydWV9"),
        Sample(label: "Cron", symbol: "calendar.badge.clock", text: "*/15 9-17 * * 1-5"),
        Sample(label: "Colour", symbol: "paintpalette", text: "#3D7BFF"),
        Sample(label: "curl", symbol: "terminal", text: #"curl -X POST https://api.example.com/v1/items -H 'Content-Type: application/json' -d '{"name":"widget","qty":2}'"#),
    ]
    /// Typed commands and instructions: say what you want, then the data.
    static let instructions: [Sample] = [
        Sample(label: "3 uuid v7", symbol: "", text: "3 uuid v7"),
        Sample(label: "sha256 hello", symbol: "", text: "sha256 hello"),
        Sample(label: "to yaml {…}", symbol: "", text: #"to yaml {"name":"Bitlathe","tags":["mac","dev"],"port":8080}"#),
        Sample(label: "base64 decode …", symbol: "", text: "base64 decode SGVsbG8sIEJpdGxhdGhlIQ=="),
        Sample(label: "snake_case …", symbol: "", text: "snake_case helloBraveNewWorld"),
        Sample(label: "password 24", symbol: "", text: "password 24"),
        Sample(label: "now", symbol: "", text: "now"),
    ]
}

// MARK: - Suggestions

private struct SuggestionBar: View {
    let model: SmartBoxModel
    let analysis: SmartBox.Analysis

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    ForEach(Array(analysis.actions.enumerated()), id: \.element.key) { i, action in
                        ActionChip(action: action, index: i, selected: i == model.selected) { model.choose(i) }
                    }
                }
                .padding(.horizontal, Space.lg)
            }
            HStack(spacing: Space.sm) {
                switch analysis.kind {
                case .data:
                    Text("Detected").foregroundStyle(Palette.subtle)
                    FormatPill(name: analysis.formatName, confidence: analysis.confidence)
                case .command:
                    FormatPill(name: analysis.formatName, confidence: nil)
                case .words:
                    Text(analysis.actions.first?.opensTool == true ? "Not data: matching tools" : analysis.formatKey == "lines" ? "A list" : "Plain text")
                        .foregroundStyle(Palette.subtle)
                }
                if let action = model.current {
                    Text("·").foregroundStyle(Palette.subtle)
                    Text(reason(for: action)).foregroundStyle(Palette.subtle).lineLimit(1)
                }
                if model.isAskingModel {
                    HStack(spacing: Space.xs) {
                        ProgressView().controlSize(.mini)
                        Text("Asking the on-device model…").foregroundStyle(Palette.subtle)
                    }
                }
                if analysis.isSensitive {
                    Label("Contains a secret", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.warning)
                        .padding(.horizontal, Space.sm).padding(.vertical, 1)
                        .background(Palette.warning.opacity(0.12), in: Capsule())
                        .help("Looks like a credential or key. It stays on this Mac; Bitlathe never sends anything anywhere.")
                }
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, Space.lg)
        }
        .padding(.vertical, Space.sm + 2)
        .background(Palette.chrome)
    }

    private func reason(for action: SmartBox.Action) -> String {
        if action.reason == SmartBox.Advisor.reason { return action.reason + ": it chose the tool, the tool made the result" }
        if action.learned > 0 { return "You chose this \(action.learned)× for this kind of data" }
        // Don't repeat the detection pill ("Valid JSON · Valid JSON").
        if action.reason == analysis.formatName { return model.selected == 0 ? "Best match" : action.tool.name }
        return action.reason
    }
}

private struct FormatPill: View {
    let name: String
    let confidence: Double?
    var body: some View {
        HStack(spacing: Space.xs) {
            Circle().fill(Palette.accent).frame(width: 6, height: 6)
            Text(name).fontWeight(.semibold)
            if let confidence { Text("\(Int((confidence * 100).rounded()))%").foregroundStyle(Palette.subtle).monospacedDigit() }
        }
        .padding(.horizontal, Space.sm).padding(.vertical, 1)
        .background(Palette.raised, in: Capsule())
    }
}

private struct ActionChip: View {
    let action: SmartBox.Action
    let index: Int
    let selected: Bool
    let tap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: tap) {
            HStack(spacing: Space.sm) {
                Image(systemName: action.tool.symbol).imageScale(.small)
                Text(action.title).fontWeight(.semibold).lineLimit(1)
                if let detail = action.detail {
                    Text(detail).foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary).lineLimit(1)
                }
                if action.learned >= 3, !selected {
                    Circle().fill(Palette.success).frame(width: 6, height: 6).help("You use this often")
                }
                if index < SmartMetrics.maxActionsWithShortcuts {
                    Text(selected ? "⌘↩" : "⌘\(index + 1)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? Color.white.opacity(0.5) : Palette.separator))
                        .foregroundStyle(selected ? Color.white.opacity(0.9) : Palette.subtle)
                }
            }
            .font(.callout)
            .padding(.horizontal, Space.md).padding(.vertical, Space.xs + 2)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(hovering ? Palette.raised : Palette.editorBackground),
                        in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(selected ? Color.clear : Palette.separator, lineWidth: 1))
            .shadow(color: selected ? Palette.accent.opacity(0.35) : .clear, radius: 8, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(action.reason)
        .accessibilityLabel([action.title, action.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Result

private struct SmartResult: View {
    @Bindable var model: SmartBoxModel

    var body: some View {
        let config = EditorConfig.current
        VStack(spacing: 0) {
            if let action = model.current {
                header(action)
                if action.opensTool {
                    OpenToolCard(action: action) { model.openTool() }
                } else if let first = model.session {
                    // A formatter's modes are already the chips above (Minify ⌘2, Validate ⌘3): one control, not two.
                    let hidden: Set<String> = modesAreChips(for: action) ? ["mode"] : []
                    if !first.tool.optionFields.filter({ !$0.advanced && !hidden.contains($0.key) }).isEmpty, action.then == nil {
                        OptionBar(session: first, hiding: hidden)
                    }
                    if let error = model.error {
                        ErrorBanner(error, onFix: { first.setOption($0.option, $0.value) })
                        Spacer()
                    } else if let session = model.resultSession, let out = session.output {
                        WarningBanner(out.warnings)
                        OutputContent(payload: session.currentOutputPayload ?? out.payload, output: out, session: session, config: config)
                    } else if first.isRunning || first.runCount == 0 {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("No result").foregroundStyle(Palette.subtle).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private func modesAreChips(for action: SmartBox.Action) -> Bool {
        guard let actions = model.analysis?.actions else { return false }
        return actions.contains { $0.key != action.key && $0.tool.id == action.tool.id && $0.then == nil && $0.options["mode"] != nil }
            || (action.options["mode"] != nil && actions.contains { $0.key != action.key && $0.tool.id == action.tool.id && $0.then == nil })
    }

    private func header(_ action: SmartBox.Action) -> some View {
        HStack(spacing: Space.md) {
            if let step = action.then {
                HStack(spacing: Space.xs) {
                    StepBadge(number: 1, name: action.tool.name)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(Palette.subtle)
                    StepBadge(number: 2, name: step.tool.name)
                }
            } else {
                Text([action.title, action.detail].compactMap { $0 }.joined(separator: " · ")).font(.headline)
            }
            if let out = model.resultSession?.output, let valid = out.isValid {
                StatusBadge(valid ? "Valid" : "Invalid", valid ? .success : .danger)
            }
            if let s = model.resultSession, s.runCount > 0, model.error == nil {
                Text(DurationFormatter.ms(s.lastDuration)).font(.caption).foregroundStyle(Palette.subtle).monospacedDigit()
            }
            Spacer()
            if model.replacedFrom != nil {
                Button("Undo") { model.undoReplace() }.help("Put back the text you replaced")
            }
            if !action.opensTool {
                Button("Open Tool") { model.openTool() }.help("Open the full \(action.then?.tool.name ?? action.tool.name) screen (⌥↩)")
                Button("Replace") { model.replace() }.disabled(!model.canAccept).help("Replace the box with the result (⇧⌘↩)")
                Button { model.copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canAccept)
                    .help("Copy the result (⌘↩)")
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm + 2)
    }
}

private struct StepBadge: View {
    let number: Int
    let name: String
    var body: some View {
        HStack(spacing: Space.xs) {
            Text("\(number)").font(.caption2.weight(.bold)).frame(width: 16, height: 16)
                .background(Palette.accent.opacity(0.15), in: Circle()).foregroundStyle(Palette.accent)
            Text(name).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, Space.sm).padding(.vertical, Space.xxs + 1)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }
}

private struct OpenToolCard: View {
    let action: SmartBox.Action
    let open: () -> Void
    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: action.tool.symbol).font(.system(size: 34, weight: .light)).foregroundStyle(Palette.accent)
            Text(action.tool.name).font(.title3.weight(.semibold))
            Text(action.tool.summary).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open \(action.tool.name)", action: open).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            Text("This tool needs more than one box; it opens in its own screen.").font(.caption).foregroundStyle(Palette.subtle)
        }
        .frame(maxWidth: 420)
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status bar

private struct SmartStatusBar: View {
    let model: SmartBoxModel
    var body: some View {
        HStack(spacing: Space.lg) {
            if model.isEmpty {
                Text("Ready")
            } else {
                Text(ByteFormatter.string(model.text.utf8.count))
                let lines = model.text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                Text(lines == 1 ? "1 line" : "\(lines) lines")
            }
            Spacer()
            Label("Learns on this Mac", systemImage: "circle.fill").labelStyle(DotLabelStyle())
                .help("Suggestions improve from what you choose. This stays on this Mac; Settings › History & Privacy can reset it.")
            Text("⌘K all tools")
        }
        .font(.caption)
        .foregroundStyle(Palette.subtle)
        .monospacedDigit()
        .padding(.horizontal, Space.lg)
        .frame(height: Layout.statusHeight)
        .background(Palette.chrome)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(Palette.success).frame(width: 6, height: 6)
            configuration.title
        }
    }
}
