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
        }
        .defaultSize(width: 1280, height: 820)
        .commands { BitlatheCommands(model: model) }

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
