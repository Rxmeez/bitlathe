import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

/// Owns the status item, the Quick Panel, global hotkeys and the Dock / menu bar activation policy.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private let settings = Settings.shared
    private var statusItem: NSStatusItem?
    private var panel: QuickNSPanel?
    private let panelModel = QuickPanelModel()
    private var hotKeyIDs: [UInt32] = []
    private var flashTask: Task<Void, Never>?
    private var started = false

    /// Set by a SwiftUI view so the controller can reopen the main window after it was closed.
    var openMainWindowAction: (() -> Void)?

    func start() {
        guard !started else { return }
        started = true
        apply()
        observe()
        #if DEBUG
        // Screenshot harness: `-BLQuickPanel YES -BLQuickPanelText '{"a":1}'`
        let d = UserDefaults.standard
        if let t = d.string(forKey: "BLQuickPanelText") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t.replacingOccurrences(of: "\\n", with: "\n"), forType: .string) }
        if d.bool(forKey: "BLQuickPanel") {
            Task { try? await Task.sleep(for: .seconds(1)); showPanel(anchoredToStatusItem: false) }
        }
        #endif
    }

    // MARK: Settings -> state

    private func observe() {
        withObservationTracking {
            _ = settings.dockMode; _ = settings.showMenuBarIcon
            _ = settings.quickPanelHotKey; _ = settings.mainWindowHotKey
        } onChange: { [weak self] in
            Task { @MainActor in self?.apply(); self?.observe() }
        }
    }

    private func apply() {
        let mode = settings.dockMode
        let wantsPolicy: NSApplication.ActivationPolicy = mode == .menuBarOnly ? .accessory : .regular
        if NSApp.activationPolicy() != wantsPolicy {
            NSApp.setActivationPolicy(wantsPolicy)
            // Switching policy deactivates the app; bring Settings / windows back so the change feels instant.
            NSApp.activate(ignoringOtherApps: true)
        }
        let showIcon = mode == .menuBarOnly || (mode == .dockAndMenuBar && settings.showMenuBarIcon)
        showIcon ? installStatusItem() : removeStatusItem()
        registerHotKeys()
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = item.button {
            b.image = Self.icon(Self.restingSymbol)
            b.target = self
            b.action = #selector(statusClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.toolTip = "Bitlathe — click for Quick Panel, Option-click to copy the result"
        }
        statusItem = item
    }

    private func removeStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    /// The dev build uses a hammer so the two menu bar icons can be told apart.
    private static var restingSymbol: String { AppFlavour.isDev ? "hammer" : "wrench.and.screwdriver" }

    private static func icon(_ symbol: String) -> NSImage? {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Bitlathe")
        img?.isTemplate = true
        return img
    }

    private func registerHotKeys() {
        for id in hotKeyIDs { HotKeyCenter.shared.unregister(id) }
        hotKeyIDs = []
        if let c = settings.quickPanelHotKey, let id = HotKeyCenter.shared.register(c, handler: { [weak self] in self?.togglePanel(anchoredToStatusItem: false) }) { hotKeyIDs.append(id) }
        if let c = settings.mainWindowHotKey, let id = HotKeyCenter.shared.register(c, handler: { [weak self] in self?.showMainWindow() }) { hotKeyIDs.append(id) }
    }

    // MARK: Status item

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp { showContextMenu(); return }
        if event?.modifierFlags.contains(.option) == true, settings.quickPanelCopyOnOptionClick {
            copyTopResult()
            return
        }
        togglePanel(anchoredToStatusItem: true)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open Bitlathe", action: #selector(menuOpenMain), keyEquivalent: "")
        open.target = self
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Bitlathe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        guard let item = statusItem else { return }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func menuOpenMain() { showMainWindow() }
    @objc private func menuSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// Option-click: run detection on the clipboard and put the top result straight back on it.
    private func copyTopResult() {
        Task {
            if let out = await panelModel.topOutput() {
                Clipboard.copy(out, toast: nil)
                flash("checkmark")
            } else {
                NSSound.beep()
                flash("exclamationmark.triangle")
            }
        }
    }

    private func flash(_ symbol: String) {
        flashTask?.cancel()
        statusItem?.button?.image = Self.icon(symbol)
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.statusItem?.button?.image = Self.icon(Self.restingSymbol)
        }
    }

    // MARK: Panel

    func togglePanel(anchoredToStatusItem: Bool) {
        if let panel, panel.isVisible { closePanel(); return }
        showPanel(anchoredToStatusItem: anchoredToStatusItem)
    }

    private func showPanel(anchoredToStatusItem: Bool) {
        panelModel.refresh()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let host = panel.contentView as? NSHostingView<QuickPanelView> {
            host.layoutSubtreeIfNeeded()
            panel.setContentSize(host.fittingSize)
        }
        position(panel, anchoredToStatusItem: anchoredToStatusItem)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        let reduce = settings.reduceMotionOverride || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduce ? 0 : Motion.fast
            panel.animator().alphaValue = 1
        }
        // The preview is computed asynchronously, so refit once it lands.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            self?.refit(anchoredToStatusItem: anchoredToStatusItem)
        }
    }

    private func refit(anchoredToStatusItem: Bool) {
        guard let panel, panel.isVisible, let host = panel.contentView as? NSHostingView<QuickPanelView> else { return }
        let old = panel.frame
        let size = host.fittingSize
        guard abs(size.height - old.height) > 1 else { return }
        panel.setFrame(NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    private func makePanel() -> QuickNSPanel {
        let view = QuickPanelView(model: panelModel,
                                  copy: { [weak self] in self?.copyFromPanel() },
                                  openInApp: { [weak self] in self?.openInApp() },
                                  close: { [weak self] in self?.closePanel() })
        let host = NSHostingView(rootView: view)
        let p = QuickNSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.onResign = { [weak self] in self?.closePanel() }
        return p
    }

    private func position(_ panel: NSPanel, anchoredToStatusItem: Bool) {
        let size = panel.frame.size
        if anchoredToStatusItem, let button = statusItem?.button, let win = button.window {
            let r = win.frame
            let screen = win.screen ?? NSScreen.main
            var x = r.midX - size.width / 2
            if let vf = screen?.visibleFrame { x = min(max(x, vf.minX + Space.sm), vf.maxX - size.width - Space.sm) }
            panel.setFrameOrigin(NSPoint(x: x, y: r.minY - size.height - Space.xs))
        } else {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            let vf = screen?.visibleFrame ?? .zero
            panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - vf.height * 0.2))
        }
    }

    private func closePanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func copyFromPanel() {
        guard let out = panelModel.computed?.copyText, !out.isEmpty else { return }
        Clipboard.copy(out, toast: nil)
        panelModel.learn()
        closePanel()
        flash("checkmark")
    }

    private func openInApp() {
        let model = AppModel.shared
        if let r = panelModel.current {
            model.open(toolID: r.tool.id, input: r.inputOverride ?? panelModel.clipboardText, options: r.options)
        }
        closePanel()
        showMainWindow()
    }

    // MARK: Main window

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) && $0.identifier?.rawValue.contains("settings") != true && $0.title == "Bitlathe" }) ?? NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else {
            openMainWindowAction?()
        }
    }
}

/// Captures SwiftUI's `openWindow` so AppKit code can reopen the main window.
struct MainWindowOpenerCapture: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { MenuBarController.shared.openMainWindowAction = { openWindow(id: "main") } }
    }
}
