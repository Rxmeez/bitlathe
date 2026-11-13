import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI
import Carbon.HIToolbox

/// A small "click, then press a shortcut" control. Esc cancels, Delete clears.
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo?
    var defaultCombo: HotKeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: Space.sm) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type shortcut…" : (combo?.display ?? "Not set"))
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(recording ? Color.secondary : Color.primary)
                    .frame(minWidth: 96)
            }
            .controlSize(.regular)
            .accessibilityLabel("Shortcut")
            .accessibilityValue(combo?.display ?? "Not set")
            if combo != defaultCombo {
                Button("Reset") { combo = defaultCombo }.buttonStyle(.link).font(.caption)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = HotKeyCombo.carbonModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            if event.keyCode == 53 { Task { @MainActor in stop() }; return nil }                       // Esc
            if event.keyCode == 51 || event.keyCode == 117 { Task { @MainActor in combo = nil; stop() }; return nil } // Delete
            // Require at least one of ⌘ ⌥ ⌃ so plain typing never becomes a global hotkey.
            guard mods & (UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)) != 0 else { NSSound.beep(); return nil }
            let new = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            Task { @MainActor in combo = new; stop() }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
