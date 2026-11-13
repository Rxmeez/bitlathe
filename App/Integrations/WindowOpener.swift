import SwiftUI
import AppKit

/// Lets AppKit-side code (URL handler, Services) open SwiftUI windows by capturing `openWindow` from a live view.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    private var openMain: (() -> Void)?

    func capture(_ action: OpenWindowAction) {
        openMain = { action(id: "main") }
    }

    /// Opens the main window only if no Bitlathe window is currently visible.
    func ensureMainWindow() {
        let visible = NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain }
        if !visible { openMain?() }
        for w in NSApp.windows where w.isMiniaturized { w.deminiaturize(nil) }
    }
}

/// Invisible helper placed in a scene's content to publish its `openWindow` action.
struct WindowOpenerCapture: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear { WindowOpener.shared.capture(openWindow) }
    }
}

extension View {
    func capturesOpenWindow() -> some View { modifier(WindowOpenerCapture()) }
}
