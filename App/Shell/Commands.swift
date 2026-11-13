import SwiftUI
import BitlatheCore
import BitlatheUI

struct BitlatheCommands: Commands {
    let model: AppModel
    @FocusedValue(\.toolSession) private var session

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }.keyboardShortcut("x")
            Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }.keyboardShortcut("c")
            Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }.keyboardShortcut("v")
            Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }.keyboardShortcut("a")
            Divider()
            Button("Smart Paste") { model.smartPaste() }.keyboardShortcut("v", modifiers: [.command, .option])
        }
        CommandMenu("Tool") {
            Button("Command Palette…") { model.togglePalette() }.keyboardShortcut("k")
            Button("Go to Tool or Action…") { model.togglePalette() }.keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button("Copy Output") { session?.copyOutput() }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(session?.output == nil)
            Button("Replace Clipboard with Output") { session?.replaceClipboardWithOutput() }.keyboardShortcut("v", modifiers: [.command, .shift]).disabled(session?.output == nil)
            Button("Swap Input and Output") { session?.swapInputOutput() }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(session?.output == nil)
            Button("Clear") { session?.clear() }.keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button("Open File…") { session?.openFile() }.keyboardShortcut("o")
            Button("Save Output…") { session?.saveOutput() }.keyboardShortcut("s")
            Divider()
            Button("Run Again") { session?.run() }.keyboardShortcut("r")
            Button("Toggle Layout") { session?.orientation = session?.orientation == .horizontal ? .vertical : .horizontal }.keyboardShortcut("l", modifiers: [.command, .option])
            Button("Detect Clipboard Now") { if let s = Clipboard.string { model.detect(s) } }.keyboardShortcut("d", modifiers: [.command, .shift])
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Inspector") { model.showInspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Button("Zoom In") { Settings.shared.zoomIn() }.keyboardShortcut("+")
            Button("Zoom Out") { Settings.shared.zoomOut() }.keyboardShortcut("-")
            Button("Actual Size") { Settings.shared.resetZoom() }.keyboardShortcut("0")
        }
        CommandGroup(replacing: .help) {
            Button("Show Welcome…") { OnboardingController.shared.isPresented = true } // onboarding
            Button("Bitlathe Help") { if let u = URL(string: "https://github.com/bitlathe/bitlathe#readme") { NSWorkspace.shared.open(u) } }
        }
    }
}
