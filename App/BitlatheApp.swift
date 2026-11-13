import SwiftUI
import BitlatheCore
import BitlatheUI
import BitlatheTools

@main
struct BitlatheApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Bitlathe", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: Layout.minWindow.width, minHeight: Layout.minWindow.height)
                .toastOverlay()
                .background(MainWindowOpenerCapture()) // menubar:
                .capturesOpenWindow() // url-scheme:
                // scratchpad: DEBUG screenshot harness hook (no-op in release)
                .scratchpadDebugLaunch()
        }
        .defaultSize(width: 1280, height: 820)
        .commands { BitlatheCommands(model: model) }
        // scratchpad: Window menu entry + Scratchpad commands
        .commands { ScratchpadCommands() }

        // scratchpad: single large autosaved editor with the in-place tool picker
        Window("Scratchpad", id: ScratchpadWindow.id) {
            ScratchpadView(model: ScratchpadModel.shared)
        }
        .defaultSize(ScratchpadView.defaultSize)

        // url-scheme: extra windows ("Open in new window"). Value = "<toolID>#<uuid>" so every request is a distinct window.
        WindowGroup("Bitlathe", id: "tool-window", for: String.self) { $value in
            ToolWindowRoot(value: value)
                .frame(minWidth: Layout.minWindow.width, minHeight: Layout.minWindow.height)
                .toastOverlay()
        }
        .defaultSize(width: 1100, height: 760)

        Settings {
            SettingsView().environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        AppearanceController.apply(Settings.shared.appearance)
        MenuBarController.shared.start() // menubar:
        ServiceProvider.register() // url-scheme: Services menu
    }

    // url-scheme: bitlathe:// URLs (handled here, not via .onOpenURL, so SwiftUI does not spawn a window per URL).
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        DeepLinkRouter.handle(urls.filter { $0.scheme?.lowercased() == DeepLink.scheme })
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { for w in sender.windows { w.makeKeyAndOrderFront(nil) } }
        return true
    }
}

@MainActor
enum AppearanceController {
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
