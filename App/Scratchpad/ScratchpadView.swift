import SwiftUI
import BitlatheCore
import BitlatheUI

private enum ScratchpadMetrics {
    static let minSize = CGSize(width: 520, height: 360)
    static let defaultSize = CGSize(width: 780, height: 560)
    static let dim: Double = 0.18
    static let pickerTopFraction: CGFloat = 0.14
}

/// The Scratchpad window: one big editor, a transient error banner, a status bar and the floating picker.
struct ScratchpadView: View {
    @Bindable var model: ScratchpadModel

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                CodeEditor(text: $model.text, placeholder: "Type or paste here. ⌘⇧P applies a tool to the selection, or to everything.",
                           config: .current, controller: model.controller)
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ScratchpadStatusBar(model: model)
            }
            if model.showPicker {
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        Color.black.opacity(ScratchpadMetrics.dim)
                            .contentShape(Rectangle())
                            .onTapGesture { model.closePicker() }
                            .accessibilityHidden(true)
                        ScratchpadPicker(model: model)
                            .padding(.top, geo.size.height * ScratchpadMetrics.pickerTopFraction)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.animation(Motion.fast), value: model.showPicker)
        .animation(Motion.animation(Motion.fast), value: model.errorMessage)
        .frame(minWidth: ScratchpadMetrics.minSize.width, minHeight: ScratchpadMetrics.minSize.height)
        // Mouse users need a way in too: the picker and "repeat" were keyboard/menu only.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.repeatLast() } label: { Label("Repeat", systemImage: "arrow.clockwise") }
                    .disabled(model.lastTool == nil || model.isRunning)
                    .help(model.lastTool.map { "Apply \($0.name) again (⌘⇧R)" } ?? "Repeat the last tool (⌘⇧R)")
                Button { model.openPicker() } label: { Label("Apply Tool", systemImage: "wand.and.stars") }
                    .help("Apply a tool to the selection, or to everything (⌘⇧P)")
            }
        }
        .focusedSceneValue(\.scratchpad, model)
    }

    static var defaultSize: CGSize { ScratchpadMetrics.defaultSize }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.danger).accessibilityHidden(true)
            Text(message).lineLimit(2).textSelection(.enabled)
            Spacer(minLength: Space.md)
            Button(action: dismiss) { Image(systemName: "xmark").font(.caption.weight(.semibold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss error")
        }
        .font(Typography.caption)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Palette.danger.opacity(0.12))
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

private struct ScratchpadStatusBar: View {
    let model: ScratchpadModel

    var body: some View {
        HStack(spacing: Space.lg) {
            Text("\(model.charCount.formatted()) chars")
            Text(model.lineCount == 1 ? "1 line" : "\(model.lineCount.formatted()) lines")
            let n = model.activeSelections.count
            if n > 0 { Text(n == 1 ? "1 selection" : "\(n) selections") }
            Spacer()
            if model.isRunning { ProgressView().controlSize(.small) }
            if let tool = model.lastTool {
                Button { model.repeatLast() } label: {
                    Label("Last: \(tool.name)", systemImage: tool.symbol).labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .help("Apply \(tool.name) again (⌘⇧R)")
            } else {
                Text("No tool applied yet").foregroundStyle(.tertiary)
            }
        }
        .font(Typography.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, Space.md)
        .frame(height: Layout.statusHeight)
        .background(Palette.chrome)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
    }
}
