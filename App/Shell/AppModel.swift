import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI
import BitlatheTools

/// App-wide state: registry, current selection, per-tool sessions, sidebar data.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let registry = ToolRegistry.shared
    let settings = Settings.shared

    var selectedToolID: String? {
        didSet {
            guard let id = selectedToolID, id != oldValue else { return }
            settings.lastToolID = id
            Task { try? await DataStore.shared.recordUse(id); await refreshUsage() }
        }
    }
    var searchText = ""
    var favourites: [String] = []
    var frequent: [String] = []
    var recent: [String] = []
    var showInspector = Settings.shared.inspectorVisible { didSet { settings.inspectorVisible = showInspector } }
    var detectionReport: DetectionReport?
    var detectedText: String?

    private var sessions: [String: ToolSession] = [:]
    /// -1 so whatever is on the clipboard when the app first opens gets examined once.
    private var lastClipboardChange = -1

    init() {
        ToolCatalog.registerAll(in: registry)
        selectedToolID = registry.tool(settings.lastToolID)?.id ?? registry.tools.first?.id
        Task { await refreshUsage() }
        #if DEBUG
        // Screenshot harness: `open Bitlathe.app --args -BLTool json.format -BLSample 0`
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "BLTool"), let tool = registry.tool(id) {
            selectedToolID = id
            if defaults.object(forKey: "BLSample") != nil {
                let idx = defaults.integer(forKey: "BLSample")
                if tool.samples.indices.contains(idx) { session(for: tool).useSample(tool.samples[idx]) }
            }
            if defaults.bool(forKey: "BLInspector") { showInspector = true }
        }
        if let q = defaults.string(forKey: "BLSearch") { searchText = q }
        #endif
        NotificationCenter.default.addObserver(forName: .bitlatheFavouritesChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshUsage() }
        }
    }

    var selectedTool: AnyTool? { selectedToolID.flatMap { registry.tool($0) } }

    func session(for tool: AnyTool) -> ToolSession {
        if let s = sessions[tool.id] { return s }
        let s = ToolSession(tool: tool)
        s.openInTool = { [weak self] id, text in self?.open(toolID: id, input: text) }
        sessions[tool.id] = s
        return s
    }

    var currentSession: ToolSession? { selectedTool.map(session(for:)) }

    func open(toolID: String, input: String? = nil, options: OptionValues = [:]) {
        guard let tool = registry.tool(toolID) else { return }
        let s = session(for: tool)
        for (k, v) in options { s.options[k] = v }
        if let input { s.inputText = input }
        selectedToolID = toolID
    }

    func refreshUsage() async {
        favourites = (try? await DataStore.shared.favourites()) ?? []
        frequent = (try? await DataStore.shared.frequentlyUsed(limit: 6)) ?? []
        recent = (try? await DataStore.shared.recentlyUsed(limit: 6)) ?? []
    }

    // MARK: Sidebar data

    var visibleTools: [AnyTool] {
        let hidden = Set(settings.hiddenTools)
        return registry.tools.filter { !hidden.contains($0.id) }
    }

    var filteredTools: [AnyTool] {
        let q = searchText.trimmed()
        guard !q.isEmpty else { return visibleTools }
        let hidden = Set(settings.hiddenTools)
        return registry.search(q).filter { !hidden.contains($0.id) }
    }

    func tools(in category: ToolCategory) -> [AnyTool] { filteredTools.filter { $0.category == category && $0.kind == .native } }

    // MARK: Smart detection

    /// Runs detection on the clipboard when the window becomes active (if enabled) and surfaces the result as a banner.
    func detectClipboardIfNeeded() {
        guard settings.detectOnFocus, settings.detectFromClipboard else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastClipboardChange, let text = pb.string(forType: .string), text.utf8.count < DetectionEngine.maxInputBytes else { return }
        lastClipboardChange = pb.changeCount
        detect(text)
    }

    func detect(_ text: String) {
        let report = DetectionEngine.detect(text, tools: registry.tools, ignoring: Set(settings.detectionIgnoreList))
        guard let best = report.best, best.score.confidence >= 0.5, best.tool.id != selectedToolID || currentSession?.inputText != text else { detectionReport = nil; return }
        detectionReport = report
        detectedText = text
    }

    func applyDetection(_ result: DetectionResult) {
        guard let text = detectedText else { return }
        open(toolID: result.tool.id, input: text, options: result.score.options)
        detectionReport = nil
    }

    func dismissDetection() { detectionReport = nil }

    /// "Paste and it just works": paste into the current tool, but if detection is confident about a different tool, switch.
    func smartPaste() {
        guard let text = Clipboard.string else { currentSession?.pasteFromClipboard(); return }
        if settings.detectOnPaste {
            let report = DetectionEngine.detect(text, tools: registry.tools, ignoring: Set(settings.detectionIgnoreList))
            if let best = report.best, best.score.confidence >= 0.8, best.tool.id != selectedToolID, !(currentSession.map { $0.tool.detect(text.trimmed()) != nil } ?? false) {
                open(toolID: best.tool.id, input: text, options: best.score.options)
                detectionReport = report
                detectedText = text
                return
            }
        }
        currentSession?.inputText = text
    }
}
