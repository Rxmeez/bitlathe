import Foundation
import Observation

public enum DockMode: String, CaseIterable, Codable, Sendable {
    case dockAndMenuBar = "both", dockOnly = "dock", menuBarOnly = "menubar"
    public var title: String {
        switch self {
        case .dockAndMenuBar: "Dock and menu bar"
        case .dockOnly: "Dock only"
        case .menuBarOnly: "Menu bar only"
        }
    }
}

public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system, light, dark
    public var title: String { rawValue.capitalized }
}

public enum SplitOrientation: String, Codable, Sendable { case horizontal, vertical }

// menubar: a global hotkey combination (Carbon key code + Carbon modifier mask).
public struct HotKeyCombo: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    public var stored: String { "\(keyCode):\(modifiers)" }
    public init?(stored: String) {
        let p = stored.split(separator: ":")
        guard p.count == 2, let k = UInt32(p[0]), let m = UInt32(p[1]) else { return nil }
        self.init(keyCode: k, modifiers: m)
    }
    /// Control + Option + Space (Carbon controlKey 0x1000, optionKey 0x800). The dev build adds Shift (0x200)
    /// so it can run beside the installed app without the two fighting over one shortcut.
    public static var defaultQuickPanel: HotKeyCombo { HotKeyCombo(keyCode: 49, modifiers: 0x1000 | 0x800 | devShift) }
    /// Control + Option + B (plus Shift in the dev build).
    public static var defaultMainWindow: HotKeyCombo { HotKeyCombo(keyCode: 11, modifiers: 0x1000 | 0x800 | devShift) }
    private static var devShift: UInt32 { AppFlavour.isDev ? 0x200 : 0 }
}

/// Typed, observable settings backed by UserDefaults.
@MainActor
@Observable
public final class Settings {
    public static let shared = Settings()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // General
    public var launchAtLogin = false { didSet { set("launchAtLogin", launchAtLogin) } }
    public var dockMode: DockMode = .dockAndMenuBar { didSet { set("dockMode", dockMode.rawValue) } }
    public var showMenuBarIcon = true { didSet { set("showMenuBarIcon", showMenuBarIcon) } }
    public var onboardingCompleted = false { didSet { set("onboardingCompleted", onboardingCompleted) } }

    // Appearance
    public var appearance: AppearanceMode = .system { didSet { set("appearance", appearance.rawValue) } }
    public var useAppAccent = false { didSet { set("useAppAccent", useAppAccent) } }
    public var editorTheme = "bitlathe" { didSet { set("editorTheme", editorTheme) } }
    public var reduceMotionOverride = false { didSet { set("reduceMotionOverride", reduceMotionOverride) } }

    // Editor
    public var editorFontName = "SF Mono" { didSet { set("editorFontName", editorFontName) } }
    public var editorFontSize: Double = 13 { didSet { set("editorFontSize", editorFontSize) } }
    public var fontZoom: Double = 1.0 { didSet { set("fontZoom", fontZoom) } }
    public var tabWidth = 4 { didSet { set("tabWidth", tabWidth) } }
    public var wrapLines = true { didSet { set("wrapLines", wrapLines) } }
    public var showInvisibles = false { didSet { set("showInvisibles", showInvisibles) } }
    public var showLineNumbers = true { didSet { set("showLineNumbers", showLineNumbers) } }
    public var showMinimap = false { didSet { set("showMinimap", showMinimap) } }
    public var highlightCurrentLine = true { didSet { set("highlightCurrentLine", highlightCurrentLine) } }

    // Detection
    public var detectOnFocus = true { didSet { set("detectOnFocus", detectOnFocus) } }
    public var detectFromClipboard = true { didSet { set("detectFromClipboard", detectFromClipboard) } }
    public var detectOnPaste = true { didSet { set("detectOnPaste", detectOnPaste) } }
    public var detectionIgnoreList: [String] = [] { didSet { set("detectionIgnoreList", detectionIgnoreList) } }
    /// Ask the language model built into macOS which tool a request in words means. On this Mac only.
    public var useOnDeviceModel = true { didSet { set("useOnDeviceModel", useOnDeviceModel) } }

    // History & privacy
    public var historyEnabled = true { didSet { set("historyEnabled", historyEnabled) } }
    public var historyDisabledTools: [String] = ["jwt.debug", "aes.gcm", "password.hash"] { didSet { set("historyDisabledTools", historyDisabledTools) } }
    public var historyRetentionDays = 90 { didSet { set("historyRetentionDays", historyRetentionDays) } }
    public var clipboardHistoryEnabled = false { didSet { set("clipboardHistoryEnabled", clipboardHistoryEnabled) } }
    public var clipboardExcludedApps: [String] = [
        "com.agilebits.onepassword7", "com.1password.1password", "com.bitwarden.desktop", "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal", "com.apple.keychainaccess", "com.apple.Passwords", "org.keepassxc.keepassxc",
    ] { didSet { set("clipboardExcludedApps", clipboardExcludedApps) } }

    // Tools
    public var hiddenTools: [String] = [] { didSet { set("hiddenTools", hiddenTools) } }
    public var toolOrder: [String] = [] { didSet { set("toolOrder", toolOrder) } }
    public var showFrequentlyUsed = true { didSet { set("showFrequentlyUsed", showFrequentlyUsed) } }
    public var splitOrientations: [String: String] = [:] { didSet { set("splitOrientations", splitOrientations) } }
    public var lastToolID = "json.format" { didSet { set("lastToolID", lastToolID) } }
    public var inspectorVisible = false { didSet { set("inspectorVisible", inspectorVisible) } }

    // Scripts
    public var scriptsFolderBookmark: Data? { didSet { set("scriptsFolderBookmark", scriptsFolderBookmark) } }
    public var scriptsFolderPath: String = "" { didSet { set("scriptsFolderPath", scriptsFolderPath) } }

    // Integrations
    public var cliInstalledPath: String = "" { didSet { set("cliInstalledPath", cliInstalledPath) } }

    // AI
    public var onDeviceAIEnabled = false { didSet { set("onDeviceAIEnabled", onDeviceAIEnabled) } }

    // Updates
    public var automaticUpdates = true { didSet { set("automaticUpdates", automaticUpdates) } }

    // Quick panel
    public var quickPanelCopyOnOptionClick = true { didSet { set("quickPanelCopyOnOptionClick", quickPanelCopyOnOptionClick) } }

    // menubar: global hotkeys (nil = disabled)
    public var quickPanelHotKey: HotKeyCombo? = .defaultQuickPanel { didSet { set("quickPanelHotKey", quickPanelHotKey?.stored ?? "none") } }
    public var mainWindowHotKey: HotKeyCombo? = .defaultMainWindow { didSet { set("mainWindowHotKey", mainWindowHotKey?.stored ?? "none") } }

    // MARK: Persistence

    private var loading = false

    private func set(_ key: String, _ value: Any?) {
        guard !loading else { return }
        if let value { defaults.set(value, forKey: "bl." + key) } else { defaults.removeObject(forKey: "bl." + key) }
    }

    private func load() {
        loading = true
        defer { loading = false }
        // bool/integer/double(forKey:) also parse strings ("YES", "1", "0.5"), so a launch argument such as
        // `-bl.wrapLines NO` overrides a setting for one run without being saved.
        func b(_ k: String, _ d: Bool) -> Bool { defaults.object(forKey: "bl." + k) == nil ? d : defaults.bool(forKey: "bl." + k) }
        func s(_ k: String, _ d: String) -> String { defaults.string(forKey: "bl." + k) ?? d }
        func i(_ k: String, _ d: Int) -> Int { defaults.object(forKey: "bl." + k) == nil ? d : defaults.integer(forKey: "bl." + k) }
        func dbl(_ k: String, _ d: Double) -> Double { defaults.object(forKey: "bl." + k) == nil ? d : defaults.double(forKey: "bl." + k) }
        func arr(_ k: String, _ d: [String]) -> [String] { defaults.stringArray(forKey: "bl." + k) ?? d }

        launchAtLogin = b("launchAtLogin", launchAtLogin)
        dockMode = DockMode(rawValue: s("dockMode", dockMode.rawValue)) ?? .dockAndMenuBar
        showMenuBarIcon = b("showMenuBarIcon", showMenuBarIcon)
        onboardingCompleted = b("onboardingCompleted", onboardingCompleted)
        appearance = AppearanceMode(rawValue: s("appearance", appearance.rawValue)) ?? .system
        useAppAccent = b("useAppAccent", useAppAccent)
        editorTheme = s("editorTheme", editorTheme)
        reduceMotionOverride = b("reduceMotionOverride", reduceMotionOverride)
        editorFontName = s("editorFontName", editorFontName)
        editorFontSize = dbl("editorFontSize", editorFontSize)
        fontZoom = dbl("fontZoom", fontZoom)
        tabWidth = i("tabWidth", tabWidth)
        wrapLines = b("wrapLines", wrapLines)
        showInvisibles = b("showInvisibles", showInvisibles)
        showLineNumbers = b("showLineNumbers", showLineNumbers)
        showMinimap = b("showMinimap", showMinimap)
        highlightCurrentLine = b("highlightCurrentLine", highlightCurrentLine)
        detectOnFocus = b("detectOnFocus", detectOnFocus)
        detectFromClipboard = b("detectFromClipboard", detectFromClipboard)
        detectOnPaste = b("detectOnPaste", detectOnPaste)
        detectionIgnoreList = arr("detectionIgnoreList", detectionIgnoreList)
        useOnDeviceModel = b("useOnDeviceModel", useOnDeviceModel)
        historyEnabled = b("historyEnabled", historyEnabled)
        historyDisabledTools = arr("historyDisabledTools", historyDisabledTools)
        historyRetentionDays = i("historyRetentionDays", historyRetentionDays)
        clipboardHistoryEnabled = b("clipboardHistoryEnabled", clipboardHistoryEnabled)
        clipboardExcludedApps = arr("clipboardExcludedApps", clipboardExcludedApps)
        hiddenTools = arr("hiddenTools", hiddenTools)
        toolOrder = arr("toolOrder", toolOrder)
        showFrequentlyUsed = b("showFrequentlyUsed", showFrequentlyUsed)
        splitOrientations = defaults.dictionary(forKey: "bl.splitOrientations") as? [String: String] ?? [:]
        lastToolID = s("lastToolID", lastToolID)
        inspectorVisible = b("inspectorVisible", inspectorVisible)
        scriptsFolderBookmark = defaults.data(forKey: "bl.scriptsFolderBookmark")
        scriptsFolderPath = s("scriptsFolderPath", scriptsFolderPath)
        cliInstalledPath = s("cliInstalledPath", cliInstalledPath)
        onDeviceAIEnabled = b("onDeviceAIEnabled", onDeviceAIEnabled)
        automaticUpdates = b("automaticUpdates", automaticUpdates)
        quickPanelCopyOnOptionClick = b("quickPanelCopyOnOptionClick", quickPanelCopyOnOptionClick)
        // menubar:
        func hk(_ k: String, _ d: HotKeyCombo?) -> HotKeyCombo? {
            guard let raw = defaults.string(forKey: "bl." + k) else { return d }
            return HotKeyCombo(stored: raw)
        }
        quickPanelHotKey = hk("quickPanelHotKey", .defaultQuickPanel)
        mainWindowHotKey = hk("mainWindowHotKey", .defaultMainWindow)
    }

    // MARK: Helpers

    public func isHistoryEnabled(for toolID: String) -> Bool {
        historyEnabled && !historyDisabledTools.contains(toolID)
    }

    public func splitOrientation(for toolID: String) -> SplitOrientation {
        storedSplitOrientation(for: toolID) ?? .horizontal
    }

    /// The layout the user explicitly chose for a tool, if any.
    public func storedSplitOrientation(for toolID: String) -> SplitOrientation? {
        SplitOrientation(rawValue: splitOrientations[toolID] ?? "")
    }

    public func setSplitOrientation(_ o: SplitOrientation, for toolID: String) {
        splitOrientations[toolID] = o.rawValue
    }

    public var effectiveMonoSize: Double { editorFontSize * fontZoom }

    public func zoomIn() { fontZoom = min(fontZoom + 0.1, 2.5) }
    public func zoomOut() { fontZoom = max(fontZoom - 0.1, 0.7) }
    public func resetZoom() { fontZoom = 1.0 }

    /// Export every `bl.*` key as JSON.
    public func exportJSON() throws -> Data {
        var dict: [String: Any] = [:]
        for (k, v) in defaults.dictionaryRepresentation() where k.hasPrefix("bl.") {
            if let d = v as? Data { dict[k] = ["__data": d.base64EncodedString()] } else { dict[k] = v }
        }
        return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }

    public func importJSON(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ToolError("Not a settings file") }
        for (k, v) in dict where k.hasPrefix("bl.") {
            if let d = v as? [String: String], let b64 = d["__data"], let bytes = Data(base64Encoded: b64) {
                defaults.set(bytes, forKey: k)
            } else {
                defaults.set(v, forKey: k)
            }
        }
        load()
    }

    public func resetToDefaults() {
        for (k, _) in defaults.dictionaryRepresentation() where k.hasPrefix("bl.") { defaults.removeObject(forKey: k) }
        let fresh = Settings(defaults: UserDefaults(suiteName: "bl.ephemeral.\(UUID().uuidString)") ?? .standard)
        launchAtLogin = fresh.launchAtLogin
        dockMode = fresh.dockMode
        showMenuBarIcon = fresh.showMenuBarIcon
        quickPanelHotKey = fresh.quickPanelHotKey // menubar:
        mainWindowHotKey = fresh.mainWindowHotKey
        appearance = fresh.appearance
        useAppAccent = fresh.useAppAccent
        editorTheme = fresh.editorTheme
        editorFontName = fresh.editorFontName
        editorFontSize = fresh.editorFontSize
        fontZoom = fresh.fontZoom
        tabWidth = fresh.tabWidth
        wrapLines = fresh.wrapLines
        showInvisibles = fresh.showInvisibles
        showLineNumbers = fresh.showLineNumbers
        detectOnFocus = fresh.detectOnFocus
        detectFromClipboard = fresh.detectFromClipboard
        detectOnPaste = fresh.detectOnPaste
        detectionIgnoreList = fresh.detectionIgnoreList
        useOnDeviceModel = fresh.useOnDeviceModel
        historyEnabled = fresh.historyEnabled
        historyDisabledTools = fresh.historyDisabledTools
        historyRetentionDays = fresh.historyRetentionDays
        clipboardHistoryEnabled = fresh.clipboardHistoryEnabled
        hiddenTools = fresh.hiddenTools
        toolOrder = fresh.toolOrder
        splitOrientations = [:]
        onDeviceAIEnabled = fresh.onDeviceAIEnabled
    }
}
