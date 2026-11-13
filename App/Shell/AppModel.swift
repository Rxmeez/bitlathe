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
    /// smartbox: the home screen (one box that works out what you pasted). Selected when no tool is.
    static let homeID = "bitlathe.home"
    let smartBox = SmartBoxModel()
    var isHome: Bool { selectedToolID == Self.homeID }
    func goHome() { selectedToolID = Self.homeID }

    var selectedToolID: String? {
        didSet {
            guard let id = selectedToolID, id != oldValue, id != ClipboardMonitor.sidebarID, id != Self.homeID else { return } // clipboard/home: not tools
            settings.lastToolID = id
            Task { try? await DataStore.shared.recordUse(id); await refreshUsage() }
        }
    }
    var searchText = ""
    // pipelines: saved pipelines, registered as tools
    let pipelines = PipelineLibrary()
    var favourites: [String] = []
    var frequent: [String] = []
    var recent: [String] = []
    var showInspector = Settings.shared.inspectorVisible { didSet { settings.inspectorVisible = showInspector } }
    var showPalette = false
    var detectionReport: DetectionReport?
    var detectedText: String?

    private var sessions: [String: ToolSession] = [:]
    /// -1 so whatever is on the clipboard when the app first opens gets examined once.
    private var lastClipboardChange = -1

    init() {
        ToolCatalog.registerAll(in: registry)
        ScriptsManager.shared.start(registry: registry) // scripts:
        selectedToolID = Self.homeID   // smartbox: always open on the box; tools are one step away
        smartBox.app = self
        Task { await refreshUsage() }
        ClipboardMonitor.shared.start() // clipboard: begins polling only if the user opted in
        Task { await pipelines.bootstrap(model: self) } // pipelines:
        #if DEBUG
        // Screenshot harness: `open Bitlathe.app --args -BLTool json.format -BLSample 0`
        let defaults = UserDefaults.standard
        // smartbox: `-BLTool home -BLHomeText64 <base64>` opens the box with text (base64 so JSON survives launch args).
        if defaults.string(forKey: "BLTool") == "home" {
            selectedToolID = Self.homeID
            if let b64 = defaults.string(forKey: "BLHomeText64"), let d = Data(base64Encoded: b64), let t = String(data: d, encoding: .utf8) {
                smartBox.paste(t)
            }
        }
        if let id = defaults.string(forKey: "BLTool"), let tool = registry.tool(id) {
            selectedToolID = id
            if defaults.object(forKey: "BLSample") != nil {
                let idx = defaults.integer(forKey: "BLSample")
                if tool.samples.indices.contains(idx) { session(for: tool).useSample(tool.samples[idx]) }
            }
            if let sec = defaults.string(forKey: "BLSecondary") { session(for: tool).secondaryText = sec.replacingOccurrences(of: "\\n", with: "\n") }
            if defaults.bool(forKey: "BLInspector") { showInspector = true }
            switch defaults.string(forKey: "BLInspectorTab") { case "history": debugInspectorTab = 1; case "about": debugInspectorTab = 2; default: break }
            if defaults.bool(forKey: "BLSeedHistory"), StorePaths.isHarnessLaunch { Self.seedHistory(for: tool) }  // throwaway DB only
            if let path = defaults.string(forKey: "BLInputFile") { session(for: tool).load(urls: [URL(fileURLWithPath: path)]) }
        }
        // clipboard: screenshot harness. Never flips the (privacy-sensitive) setting itself: pass
        // `-bl.clipboardHistoryEnabled YES` too, which lives in the launch-argument domain and is not saved.
        // Seeding only happens against the harness's throwaway database.
        if defaults.bool(forKey: "BLClipboard"), StorePaths.isHarnessLaunch {
            Task { await Self.seedClipboard(); selectedToolID = ClipboardMonitor.sidebarID }
        }
        if let q = defaults.string(forKey: "BLSearch") { searchText = q }
        if defaults.bool(forKey: "BLPalette") { showPalette = true }
        #endif
        NotificationCenter.default.addObserver(forName: .bitlatheFavouritesChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshUsage() }
        }
    }

    func togglePalette() { showPalette.toggle(); if !showPalette { focusEditor() } }
    func closePalette(refocus: Bool = true) { guard showPalette else { return }; showPalette = false; if refocus { focusEditor() } }
    /// DEBUG screenshot harness only: which inspector tab to open on.
    var debugInspectorTab = 0

    #if DEBUG
    // clipboard: seeds representative entries (screenshots only)
    private static func seedClipboard() async {
        try? await DataStore.shared.clearClipboard()
        let apps = ["com.apple.finder", "com.apple.Safari", "com.apple.Terminal", "com.apple.TextEdit"]
        let items: [(String, String)] = [
            ("{\"name\":\"bitlathe\",\"version\":\"1.0.0\",\"tools\":[\"json\",\"jwt\"]}", "json.format"),
            ("550e8400-e29b-41d4-a716-446655440000", "id.generate"),
            ("https://example.com/search?q=swift+concurrency&page=2", "url.parse"),
            ("1700000000", "time.unix"),
            ("*/15 * * * 1-5", "cron.parse"),
        ]
        for (i, item) in items.enumerated() {
            try? await DataStore.shared.addClipboard(content: item.0, toolID: item.1, sourceApp: apps[i % apps.count])
        }
        ClipboardMonitor.shared.bump()
    }
    #endif

    #if DEBUG
    private static func seedHistory(for tool: AnyTool) {
        Task {
            try? await DataStore.shared.clearHistory(toolID: tool.id, includePinned: true)
            let base = tool.samples.map { ($0.input, $0.options) }
            var seeds = base
            if let first = base.first {
                let lines = first.0.split(separator: "\n").map(String.init)
                if lines.count > 2 { seeds.append((lines.dropLast().joined(separator: "\n"), first.1)) }
                seeds.append((String(first.0.prefix(max(8, first.0.count / 2))), first.1))
            }
            let field = tool.optionFields.first { if case .toggle = $0.kind { return true } else if case .picker = $0.kind { return true } else { return false } }
            for (i, seed) in seeds.enumerated() {
                var opts = seed.1
                if i == 1, let f = field {
                    switch f.kind {
                    case .toggle: opts[f.key] = .bool(!f.defaultValue.boolValue)
                    case .picker(let cs): if let c = cs.first(where: { .string($0.value) != f.defaultValue }) { opts[f.key] = .string(c.value) }
                    default: break
                    }
                }
                try? await DataStore.shared.addHistory(toolID: tool.id, input: seed.0, options: opts)
            }
            if let e = try? await DataStore.shared.history(toolID: tool.id, limit: 50).last {
                try? await DataStore.shared.setPinned(e.id, true, title: "Saved example")
            }
        }
    }
    #endif

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
        if isHome, let text = Clipboard.string { smartBox.paste(text); return } // smartbox: the box is already smart
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
