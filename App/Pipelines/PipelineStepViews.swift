import SwiftUI
import BitlatheCore
import BitlatheUI

enum PipelineMetrics {
    static let editorHeight: CGFloat = 150
    static let previewMin: CGFloat = 56
    static let previewMax: CGFloat = 190
    static let outputMax: CGFloat = 320
    static let pickerSize = CGSize(width: 380, height: 420)
    static let contentMaxWidth: CGFloat = 880
    static let numberBadge: CGFloat = 20
    static let borderWidth: CGFloat = 1
}

/// Text shown for a payload in previews.
enum PipelinePreview {
    static func text(_ output: ToolOutput, limit: Int = 60_000) -> String {
        switch output.payload {
        case .text(let s): return s.count > limit ? String(s.prefix(limit)) + "\n… truncated" : s
        case .data(let d): return "Binary data · \(ByteFormatter.string(d.count))\n" + HexDump.dump(Data(d.prefix(256)))
        case .image(let d, let f): return "Image (\(f.rawValue.uppercased())) · \(ByteFormatter.string(d.count))"
        case .file(let u): return u.path
        case .none: return "No output"
        }
    }

    static func size(_ output: ToolOutput) -> String {
        switch output.payload {
        case .text(let s): return "\(s.utf8.count) B"
        case .data(let d), .image(let d, _): return ByteFormatter.string(d.count)
        default: return ""
        }
    }

    static func height(for text: String) -> CGFloat {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return min(PipelineMetrics.previewMax, max(PipelineMetrics.previewMin, CGFloat(lines) * Space.lg + Space.md))
    }
}

// MARK: - Step card

struct StepCardView: View {
    let editor: PipelineEditor
    let step: PipelineStep
    let index: Int
    @State private var showAdvanced = false
    @State private var dropTargeted = false

    private var tool: AnyTool? { ToolRegistry.shared.tool(step.toolID) }
    private var result: PipelineStepResult? { editor.result(for: step) }
    private var failed: Bool { result?.error != nil }
    private var skipped: Bool { !step.enabled || (result?.skipped ?? false) }

    var body: some View {
        let expanded = editor.isExpanded(step)
        VStack(alignment: .leading, spacing: Space.sm) {
            header(expanded: expanded)
            if let tool, step.enabled {
                optionsRow(tool)
            }
            if !expanded, let out = result?.output, case .text(let s) = out.payload, !s.isEmpty {
                Text(s.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? "")
                    .font(Typography.captionMono).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            if expanded { preview }
        }
        .padding(Space.md)
        .background(failed ? Palette.danger.opacity(0.06) : Palette.editorBackground, in: RoundedRectangle(cornerRadius: Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium)
                .strokeBorder(dropTargeted ? Palette.accent : (failed ? Palette.danger.opacity(0.7) : Palette.separator),
                              lineWidth: dropTargeted || failed ? PipelineMetrics.borderWidth * 2 : PipelineMetrics.borderWidth)
        )
        .opacity(skipped && !failed ? 0.6 : 1)
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let id = UUID(uuidString: s) else { return false }
            editor.moveStep(id, to: step.id)
            return true
        } isTargeted: { dropTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(index + 1): \(tool?.name ?? step.toolID)")
    }

    // MARK: Header

    private func header(expanded: Bool) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: Space.lg)
                .contentShape(Rectangle())
                .help("Drag to reorder")
                .draggable(step.id.uuidString) {
                    Label(tool?.name ?? step.toolID, systemImage: tool?.symbol ?? "questionmark")
                        .padding(Space.sm)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.small))
                }
                .accessibilityLabel("Reorder handle")
            Text("\(index + 1)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(width: PipelineMetrics.numberBadge, height: PipelineMetrics.numberBadge)
                .background(Palette.raised, in: Circle())
                .foregroundStyle(.secondary)
            Image(systemName: tool?.symbol ?? "questionmark.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tool == nil ? Palette.danger : Palette.accent)
                .frame(width: Space.xl)
            VStack(alignment: .leading, spacing: 0) {
                Text(tool?.name ?? "Unknown tool").font(.headline)
                Text(tool?.summary ?? step.toolID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.sm)
            status
            Toggle("Enabled", isOn: Binding(get: { step.enabled }, set: { editor.setEnabled(step.id, $0) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .help(step.enabled ? "Disable this step" : "Enable this step")
            Button { editor.removeStep(step.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Remove step").accessibilityLabel("Remove step")
            Button {
                withAnimation(Motion.animation()) { editor.expanded[step.id] = !expanded }
            } label: {
                Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: Space.lg)
            }
            .buttonStyle(.borderless)
            .help(expanded ? "Hide output" : "Show output of this step")
            .accessibilityLabel(expanded ? "Hide step output" : "Show step output")
        }
    }

    @ViewBuilder
    private var status: some View {
        if !step.enabled {
            StatusBadge("Disabled", .neutral)
        } else if let r = result {
            if r.error != nil { StatusBadge("Failed", .danger) }
            else if r.skipped { StatusBadge("Skipped", .neutral) }
            else if let out = r.output {
                Text("\(PipelinePreview.size(out)) · \(DurationFormatter.ms(r.duration))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        } else if tool == nil {
            StatusBadge("Missing", .danger)
        }
    }

    // MARK: Options

    @ViewBuilder
    private func optionsRow(_ tool: AnyTool) -> some View {
        let binding = Binding<OptionValues>(get: { editor.options(for: step.id) }, set: { editor.setOptions(step.id, $0) })
        let current = binding.wrappedValue
        let fields = tool.optionFields.filter { f in
            f.isVisible(among: tool.optionFields) { key in
                (current[key] ?? tool.optionFields.first { $0.key == key }?.defaultValue ?? .string("")).stringValue
            }
        }
        let basic = fields.filter { !$0.advanced }
        let advanced = fields.filter(\.advanced)
        if !basic.isEmpty || !advanced.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                if !basic.isEmpty {
                    FlowLayout(spacing: Space.lg, rowSpacing: Space.sm) {
                        ForEach(basic) { StepOptionControl(field: $0, options: binding) }
                    }
                }
                if !advanced.isEmpty {
                    Button { withAnimation(Motion.animation()) { showAdvanced.toggle() } } label: {
                        Label(showAdvanced ? "Fewer options" : "More options", systemImage: showAdvanced ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                    if showAdvanced {
                        FlowLayout(spacing: Space.lg, rowSpacing: Space.sm) {
                            ForEach(advanced) { StepOptionControl(field: $0, options: binding) }
                        }
                    }
                }
            }
            .padding(.leading, Space.lg)
        }
    }

    // MARK: Output preview

    @ViewBuilder
    private var preview: some View {
        let config = EditorConfig.current
        if let e = result?.error {
            ErrorBanner(e).clipShape(RoundedRectangle(cornerRadius: Radius.small))
        } else if let r = result, r.skipped || !step.enabled {
            Text(step.enabled ? "Skipped because an earlier step failed." : "This step is disabled; its input passes on unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        } else if let out = result?.output {
            let text = PipelinePreview.text(out)
            CodeEditor(text: .constant(text), language: out.language, isEditable: false, config: config)
                .frame(height: PipelinePreview.height(for: text))
                .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Palette.separator, lineWidth: PipelineMetrics.borderWidth))
        } else {
            Text("Add input above to see this step's output.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Option controls bound to a step's OptionValues

struct StepOptionControl: View {
    let field: OptionField
    @Binding var options: OptionValues

    private var value: OptionValue { options[field.key] ?? field.defaultValue }

    private func set(_ v: OptionValue) {
        // Keep the stored options minimal: a value equal to the default is removed (also keeps `bl pipe` expressions short).
        if v.stringValue == field.defaultValue.stringValue { options[field.key] = nil } else { options[field.key] = v }
    }
    private var string: Binding<String> { Binding(get: { value.stringValue }, set: { set(.string($0)) }) }
    private var bool: Binding<Bool> { Binding(get: { value.boolValue }, set: { set(.bool($0)) }) }
    private var int: Binding<Int> { Binding(get: { value.intValue }, set: { set(.int($0)) }) }
    private var double: Binding<Double> { Binding(get: { value.doubleValue }, set: { set(.double($0)) }) }

    var body: some View {
        switch field.kind {
        case .toggle:
            Toggle(field.label, isOn: bool).toggleStyle(.checkbox)
        case .picker(let choices):
            Picker(field.label, selection: string) { ForEach(choices) { Text($0.label).tag($0.value) } }
                .pickerStyle(.menu).fixedSize()
        case .segmented(let choices):
            Picker(field.label, selection: string) { ForEach(choices) { Text($0.label).tag($0.value) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize().accessibilityLabel(field.label)
        case .stepper(let min, let max, let step):
            HStack(spacing: Space.xs) {
                label
                TextField("", value: int, format: .number).textFieldStyle(.roundedBorder).frame(width: Layout.sidebarMin / 5).multilineTextAlignment(.trailing)
                Stepper("", value: int, in: min...max, step: step).labelsHidden()
            }
        case .slider(let min, let max):
            HStack(spacing: Space.xs) {
                label
                Slider(value: double, in: min...max).frame(width: Layout.sidebarMin / 2)
                Text(String(format: "%.2f", double.wrappedValue)).font(.caption.monospacedDigit())
            }
        case .text(let placeholder):
            HStack(spacing: Space.xs) {
                label
                TextField(placeholder, text: string).textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced)).frame(width: Layout.sidebarMax / 1.6)
            }
        case .secret(let placeholder):
            HStack(spacing: Space.xs) {
                label
                SecureField(placeholder, text: string).textFieldStyle(.roundedBorder).frame(width: Layout.sidebarMax / 1.6)
            }
        case .multiline(let placeholder):
            VStack(alignment: .leading, spacing: Space.xs) {
                label
                TextEditor(text: string).font(Typography.mono)
                    .frame(width: Layout.sidebarMax * 1.5, height: PipelineMetrics.previewMin)
                    .overlay(alignment: .topLeading) {
                        if string.wrappedValue.isEmpty { Text(placeholder).foregroundStyle(.tertiary).padding(Space.xs).allowsHitTesting(false) }
                    }
                    .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Palette.separator, lineWidth: PipelineMetrics.borderWidth))
            }
        }
    }

    private var label: some View { Text(field.label).font(.callout).foregroundStyle(.secondary) }
}

// MARK: - Tool picker

struct StepToolPicker: View {
    let onPick: (AnyTool) -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var results: [AnyTool] {
        let registry = ToolRegistry.shared
        let list = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? registry.tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            : registry.search(query)
        return list.filter { $0.kind != .pipeline }
    }

    var body: some View {
        let items = results
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search tools to add", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if items.indices.contains(highlighted) { onPick(items[highlighted]) } }
                    .onChange(of: query) { highlighted = 0 }
                    .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(items.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
            }
            .padding(Space.md)
            Divider()
            if items.isEmpty {
                ContentUnavailableView("No tools match “\(query)”", systemImage: "magnifyingglass")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, tool in
                                Button { onPick(tool) } label: {
                                    HStack(spacing: Space.md) {
                                        Image(systemName: tool.symbol).symbolRenderingMode(.hierarchical).foregroundStyle(Palette.accent).frame(width: Space.xl)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(tool.name)
                                            Text(tool.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, Space.md)
                                    .padding(.vertical, Space.xs)
                                    .background(i == highlighted ? Palette.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: Radius.small))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(tool.id)
                            }
                        }
                        .padding(Space.xs)
                    }
                    .onChange(of: highlighted) { if items.indices.contains(highlighted) { proxy.scrollTo(items[highlighted].id) } }
                }
            }
        }
        .frame(width: PipelineMetrics.pickerSize.width, height: PipelineMetrics.pickerSize.height)
        .onAppear { focused = true }
    }
}
