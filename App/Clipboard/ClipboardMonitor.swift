import AppKit
import Observation
import BitlatheCore

/// Opt-in developer clipboard capture. Polls the general pasteboard's change count while enabled; everything that
/// is not a confidently recognised developer format is dropped before it is ever stored. See `ClipboardFilter`.
@MainActor
@Observable
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()
    /// Sidebar selection tag for the Clipboard view (not a tool id).
    static let sidebarID = "__clipboard.history"
    static let explainedKey = "bl.clipboardHistoryExplained"

    private(set) var isRunning = false
    /// Bumped whenever the stored history changes so views can reload.
    private(set) var revision = 0

    private let settings = Settings.shared
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var started = false

    /// Begin following the opt-in setting. Safe to call more than once.
    func start() {
        guard !started else { return }
        started = true
        apply()
        track()
    }

    private func track() {
        withObservationTracking {
            _ = settings.clipboardHistoryEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.apply()
                self?.track()
            }
        }
    }

    private func apply() {
        if settings.clipboardHistoryEnabled { begin() } else { end() }
    }

    private func begin() {
        guard timer == nil else { return }
        // Whatever is on the clipboard at opt-in time pre-dates consent, so it is never captured.
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
        isRunning = true
        prune()
    }

    private func end() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        let types = pb.types?.map(\.rawValue) ?? []
        // Privacy checks first: never even read the text of concealed items or items from excluded apps.
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let excluded = Set(settings.clipboardExcludedApps)
        let pre = ClipboardFilter.evaluate(text: nil, sourceBundleID: source, types: types, excludedApps: excluded, tools: [])
        if pre == .skip(.privateType) || pre == .skip(.excludedApp) { return }
        guard let text = pb.string(forType: .string) else { return }
        let tools = ToolRegistry.shared.tools
        Task.detached(priority: .utility) {
            let decision = ClipboardFilter.evaluate(text: text, sourceBundleID: source, types: types, excludedApps: excluded, tools: tools)
            guard case .keep(let toolID, _) = decision else { return }
            try? await DataStore.shared.addClipboard(content: text, toolID: toolID, sourceApp: source)
            await MainActor.run { ClipboardMonitor.shared.revision += 1 }
        }
    }

    private func prune() {
        let days = settings.historyRetentionDays
        Task {
            try? await DataStore.shared.pruneClipboard(olderThan: days)
            revision += 1
        }
    }

    func bump() { revision += 1 }

    // MARK: Mutations used by the UI

    func delete(_ entry: ClipboardEntry) {
        Task {
            try? await DataStore.shared.deleteClipboard(id: entry.id)
            revision += 1
        }
    }

    func clearAll() {
        Task {
            try? await DataStore.shared.clearClipboard()
            revision += 1
        }
    }
}

/// Resolves a stored bundle identifier to a display name and icon.
@MainActor
enum SourceApp {
    private static var cache: [String: (name: String, icon: NSImage)] = [:]

    static func info(_ bundleID: String?) -> (name: String, icon: NSImage)? {
        guard let bundleID else { return nil }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = (name, icon)
        return (name, icon)
    }
}
