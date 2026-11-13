import SwiftUI
import BitlatheCore

/// Renders a tool's declarative `OptionField`s as a compact bar (or a form in the inspector).
public struct OptionBar: View {
    @Bindable var session: ToolSession
    let advanced: Bool
    let asForm: Bool
    /// Option keys not to show (the Smart Box offers a formatter's modes as actions instead).
    let hiding: Set<String>

    public init(session: ToolSession, advanced: Bool = false, asForm: Bool = false, hiding: Set<String> = []) {
        self.session = session
        self.advanced = advanced
        self.asForm = asForm
        self.hiding = hiding
    }

    var fields: [OptionField] {
        session.tool.optionFields.filter { f in
            f.advanced == advanced && isVisible(f) && !hiding.contains(f.key)
        }
    }

    func isVisible(_ f: OptionField) -> Bool {
        f.isVisible(among: session.tool.optionFields) { session.option($0).stringValue }
    }

    public var body: some View {
        if !fields.isEmpty {
            if advanced || asForm {
                Section(advanced ? "Advanced" : "Options") {
                    ForEach(fields) { f in OptionControl(field: f, session: session, compact: false) }
                }
            } else {
                FlowLayout(spacing: Space.lg, rowSpacing: Space.sm) {
                    ForEach(fields) { f in OptionControl(field: f, session: session, compact: true) }
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .frame(maxWidth: .infinity, minHeight: Layout.optionBarHeight, alignment: .leading)
                .background(Palette.chrome)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }
}

struct OptionControl: View {
    let field: OptionField
    @Bindable var session: ToolSession
    let compact: Bool

    var binding: Binding<OptionValue> {
        Binding(get: { session.option(field.key) }, set: { session.setOption(field.key, $0) })
    }
    var stringBinding: Binding<String> {
        Binding(get: { binding.wrappedValue.stringValue }, set: { binding.wrappedValue = .string($0) })
    }
    var boolBinding: Binding<Bool> {
        Binding(get: { binding.wrappedValue.boolValue }, set: { binding.wrappedValue = .bool($0) })
    }
    var intBinding: Binding<Int> {
        Binding(get: { binding.wrappedValue.intValue }, set: { binding.wrappedValue = .int($0) })
    }
    var doubleBinding: Binding<Double> {
        Binding(get: { binding.wrappedValue.doubleValue }, set: { binding.wrappedValue = .double($0) })
    }

    var body: some View {
        Group {
            switch field.kind {
            case .text(let placeholder) where !compact:
                TextField(field.label, text: stringBinding, prompt: Text(placeholder))
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity)
            case .secret(let placeholder) where !compact:
                SecureField(field.label, text: stringBinding, prompt: Text(placeholder))
            case .stepper(let min, let max, let step) where !compact:
                Stepper(value: intBinding, in: min...max, step: step) {
                    HStack { Text(field.label); Spacer(); Text("\(intBinding.wrappedValue)").monospacedDigit().foregroundStyle(.secondary) }
                }
            case .segmented(let choices) where !compact:
                Picker(field.label, selection: stringBinding) { ForEach(choices) { Text($0.label).tag($0.value) } }
                    .pickerStyle(.menu)
            case .toggle:
                if compact {
                    Toggle(field.label, isOn: boolBinding).toggleStyle(.checkbox)
                } else {
                    Toggle(field.label, isOn: boolBinding).toggleStyle(.switch)
                }
            case .picker(let choices):
                Picker(field.label, selection: stringBinding) {
                    ForEach(choices) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            case .segmented(let choices):
                Picker(field.label, selection: stringBinding) {
                    ForEach(choices) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(field.label)
            case .stepper(let min, let max, let step):
                HStack(spacing: Space.xs) {
                    Text(field.label).font(.callout).foregroundStyle(.secondary)
                    TextField("", value: intBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: intBinding, in: min...max, step: step).labelsHidden()
                }
            case .slider(let min, let max):
                HStack(spacing: Space.xs) {
                    Text(field.label).font(.callout).foregroundStyle(.secondary)
                    Slider(value: doubleBinding, in: min...max).frame(width: compact ? 100 : 200)
                    Text(String(format: "%.2f", doubleBinding.wrappedValue)).font(.caption.monospacedDigit()).frame(width: 36)
                }
            case .text(let placeholder):
                HStack(spacing: Space.xs) {
                    Text(field.label).font(.callout).foregroundStyle(.secondary)
                    TextField(placeholder, text: stringBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: compact ? 170 : nil)
                        .frame(minWidth: compact ? nil : 240)
                        .font(.system(.callout, design: .monospaced))
                }
            case .secret(let placeholder):
                HStack(spacing: Space.xs) {
                    Text(field.label).font(.callout).foregroundStyle(.secondary)
                    SecureField(placeholder, text: stringBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: compact ? 170 : nil)
                        .frame(minWidth: compact ? nil : 240)
                }
            case .multiline(let placeholder):
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(field.label).font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: stringBinding)
                        .font(Typography.mono)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if stringBinding.wrappedValue.isEmpty {
                                Text(placeholder).foregroundStyle(Palette.subtle).padding(Space.xs).allowsHitTesting(false)
                            }
                        }
                }
            }
        }
        .help(field.help ?? field.label)
        .controlSize(.small)
    }
}
