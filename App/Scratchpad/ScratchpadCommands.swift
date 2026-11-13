import SwiftUI
import BitlatheCore

/// Window-menu entry plus the Scratchpad commands (enabled only while the Scratchpad window is focused).
struct ScratchpadCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.scratchpad) private var scratchpad

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Scratchpad") { openWindow(id: ScratchpadWindow.id) }.keyboardShortcut("p", modifiers: [.command, .option])
        }
        CommandMenu("Scratchpad") {
            Button("Apply Tool…") { scratchpad?.openPicker() }.disabled(scratchpad == nil)
            Button("Repeat Last Tool") { scratchpad?.repeatLast() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(scratchpad?.lastTool == nil)
        }
    }
}

enum ScratchpadWindow {
    static let id = "scratchpad"
}

#if DEBUG
/// DEBUG screenshot harness: `-BLScratchpad YES [-BLScratchpadText …] [-BLScratchpadSelect 0-5,9-12]
/// [-BLScratchpadApply tool.id] [-BLScratchpadPicker query] [-BLScratchpadDump name (written into the app support folder)]`.
struct ScratchpadDebugLauncher: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @MainActor private static var didRun = false

    func body(content: Content) -> some View {
        content.task {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "BLScratchpad"), !Self.didRun else { return }
            Self.didRun = true
            let model = ScratchpadModel.shared
            if let seed = defaults.string(forKey: "BLScratchpadText") {
                model.persistenceEnabled = false
                model.text = seed.replacingOccurrences(of: "\\n", with: "\n")
            }
            openWindow(id: ScratchpadWindow.id)
            try? await Task.sleep(for: .seconds(1))
            if let spec = defaults.string(forKey: "BLScratchpadSelect") {
                let ranges: [NSRange] = spec.split(separator: ",").compactMap { part in
                    let b = part.split(separator: "-").compactMap { Int($0) }
                    return b.count == 2 ? NSRange(location: b[0], length: b[1] - b[0]) : nil
                }
                model.controller.setSelectedRanges(ranges)
            }
            let dump = defaults.string(forKey: "BLScratchpadDump")
            if let id = defaults.string(forKey: "BLScratchpadApply"), let tool = model.registry.tool(id) {
                model.apply(tool)
                try? await Task.sleep(for: .seconds(1))
                if let dump { try? model.text.write(to: StorePaths.appSupport.appendingPathComponent(dump + ".applied"), atomically: true, encoding: .utf8) }
                if defaults.bool(forKey: "BLScratchpadUndo") {
                    model.controller.undo()
                    try? await Task.sleep(for: .milliseconds(300))
                    if let dump { try? model.text.write(to: StorePaths.appSupport.appendingPathComponent(dump + ".undone"), atomically: true, encoding: .utf8) }
                }
            }
            if defaults.string(forKey: "BLScratchpadPicker") != nil { model.openPicker() }
        }
    }
}
#endif

extension View {
    func scratchpadDebugLaunch() -> some View {
        #if DEBUG
        modifier(ScratchpadDebugLauncher())
        #else
        self
        #endif
    }
}
