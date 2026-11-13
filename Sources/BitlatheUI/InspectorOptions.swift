import SwiftUI
import BitlatheCore

/// Every option for a tool, stacked vertically for a narrow inspector column.
/// Unlike `Form`, it never asks for more width than the column offers.
public struct InspectorOptions: View {
    @Bindable var session: ToolSession
    public init(session: ToolSession) { self.session = session }

    private func visible(_ f: OptionField) -> Bool {
        guard let c = f.visibleWhen else { return true }
        return c.values.contains(session.option(c.key).stringValue)
    }

    public var body: some View {
        let fields = session.tool.optionFields.filter(visible)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                section("Options", fields.filter { !$0.advanced })
                section("Advanced", fields.filter(\.advanced))
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ fields: [OptionField]) -> some View {
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(title).font(Typography.headline)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(fields.enumerated()), id: \.element.id) { i, f in
                        InspectorOptionRow(field: f, session: session)
                            .padding(.horizontal, Space.md)
                            .padding(.vertical, Space.sm + 2)
                        if i < fields.count - 1 { Divider().padding(.leading, Space.md) }
                    }
                }
                .background(Palette.editorBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.separator.opacity(0.6)))
            }
        }
    }
}

struct InspectorOptionRow: View {
    let field: OptionField
    @Bindable var session: ToolSession

    private var string: Binding<String> {
        Binding(get: { session.option(field.key).stringValue }, set: { session.setOption(field.key, .string($0)) })
    }
    private var bool: Binding<Bool> {
        Binding(get: { session.option(field.key).boolValue }, set: { session.setOption(field.key, .bool($0)) })
    }
    private var int: Binding<Int> {
        Binding(get: { session.option(field.key).intValue }, set: { session.setOption(field.key, .int($0)) })
    }
    private var double: Binding<Double> {
        Binding(get: { session.option(field.key).doubleValue }, set: { session.setOption(field.key, .double($0)) })
    }

    var body: some View {
        Group {
            switch field.kind {
            case .toggle:
                Toggle(isOn: bool) { Text(field.label).frame(maxWidth: .infinity, alignment: .leading) }
                    .toggleStyle(.switch)
                    .controlSize(.small)
            case .picker(let choices), .segmented(let choices):
                HStack {
                    Text(field.label)
                    Spacer(minLength: Space.sm)
                    Picker(field.label, selection: string) { ForEach(choices) { Text($0.label).tag($0.value) } }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                }
            case .stepper(let lo, let hi, let step):
                HStack {
                    Text(field.label)
                    Spacer(minLength: Space.sm)
                    TextField("", value: int, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    Stepper("", value: int, in: lo...hi, step: step).labelsHidden()
                }
            case .slider(let lo, let hi):
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack { Text(field.label); Spacer(); Text(String(format: "%.2f", double.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: double, in: lo...hi).labelsHidden()
                }
            case .text(let placeholder):
                stacked { TextField(field.label, text: string, prompt: Text(placeholder)).textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced)).labelsHidden() }
            case .secret(let placeholder):
                stacked { SecureField(field.label, text: string, prompt: Text(placeholder)).textFieldStyle(.roundedBorder).labelsHidden() }
            case .multiline(let placeholder):
                stacked {
                    TextEditor(text: string)
                        .font(.system(.callout, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(Space.xs)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 90, maxHeight: 180)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.small))
                        .overlay(alignment: .topLeading) {
                            if string.wrappedValue.isEmpty {
                                Text(placeholder).font(.callout).foregroundStyle(Palette.subtle).padding(Space.sm).allowsHitTesting(false)
                            }
                        }
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(field.help ?? field.label)
    }

    private func stacked<C: View>(@ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(field.label)
            control().frame(maxWidth: .infinity, alignment: .leading)
            if let help = field.help { Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
