import SwiftUI
import ServiceManagement
import BitlatheCore
import BitlatheUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    /// Screenshot harness: `-BLSettingsTab Detection` opens on that tab.
    @State private var tab = UserDefaults.standard.string(forKey: "BLSettingsTab") ?? "General"

    var body: some View {
        // Eight tabs at this width fit the toolbar without an overflow (») menu. Editor options live under
        // Appearance and update checks under General, rather than in tabs of their own.
        TabView(selection: $tab) {
            GeneralSettings().frame(width: SettingsMetrics.width, height: 640).tabItem { Label("General", systemImage: "gearshape") }.tag("General")
            AppearanceSettings().frame(width: SettingsMetrics.width, height: 560).tabItem { Label("Appearance", systemImage: "paintbrush") }.tag("Appearance")
            DetectionSettings().frame(width: SettingsMetrics.width, height: 520).tabItem { Label("Detection", systemImage: "wand.and.stars") }.tag("Detection")
            HistorySettings().frame(width: SettingsMetrics.width, height: 640).tabItem { Label("History & Privacy", systemImage: "clock.arrow.circlepath") }.tag("History & Privacy")
            ToolsSettings().frame(width: SettingsMetrics.width, height: 560).tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }.tag("Tools")
            ScriptsSettings().frame(width: SettingsMetrics.width, height: 560).tabItem { Label("Scripts", systemImage: "scroll") }.tag("Scripts") // scripts:
            IntegrationsSettings().frame(width: SettingsMetrics.width, height: 560).tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }.tag("Integrations") // integrations:
            AdvancedSettings().frame(width: SettingsMetrics.width, height: 300).tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }.tag("Advanced")
        }
    }
}

/// Explanatory text under a settings group, aligned with the group's leading edge
/// (grouped-form footers otherwise right-align, which reads badly once they wrap).
struct SettingsFooter: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.md)   // line up with the text inside the group above
    }
}

enum SettingsMetrics {
    /// Wide enough for every tab label in one row.
    static let width: CGFloat = 640
}

struct GeneralSettings: View {
    @State private var settings = Settings.shared
    @State private var loginError: String?

    var body: some View {
        @Bindable var s = settings
        Form {
            Section {
                Toggle("Open Bitlathe at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { on in setLaunchAtLogin(on) }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(Palette.danger) }
            }
            // menubar: Show in / Quick Panel / hotkeys
            Section {
                Picker("Show in", selection: $s.dockMode) { ForEach(DockMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                if s.dockMode == .dockAndMenuBar {
                    Toggle("Show the menu bar icon", isOn: $s.showMenuBarIcon)
                }
                Toggle("Option-click the menu bar icon to copy the result", isOn: $s.quickPanelCopyOnOptionClick)
            } header: { Text("Menu bar") } footer: {
                SettingsFooter("Click the menu bar icon for the Quick Panel. It detects the clipboard and shows the result right away.")
            }
            Section("Global shortcuts") {
                LabeledContent("Quick Panel") { HotKeyRecorder(combo: $s.quickPanelHotKey, defaultCombo: .defaultQuickPanel) }
                LabeledContent("Open \(AppFlavour.displayName)") { HotKeyRecorder(combo: $s.mainWindowHotKey, defaultCombo: .defaultMainWindow) }
            }
            UpdatesSection() // release: update checks (Direct build); nothing in the App Store build
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = on
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
    }
}

struct AppearanceSettings: View {
    @State private var settings = Settings.shared
    var body: some View {
        @Bindable var s = settings
        Form {
            Section {
                Picker("Appearance", selection: $s.appearance) { ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                Toggle("Use Bitlathe accent colour", isOn: $s.useAppAccent)
                Toggle("Reduce motion", isOn: $s.reduceMotionOverride)
            }
            Section("Editor") {
                Picker("Theme", selection: $s.editorTheme) { ForEach(EditorTheme.all) { Text($0.name).tag($0.id) } }
                Picker("Font", selection: $s.editorFontName) {
                    ForEach(["SF Mono", "Menlo", "Monaco", "Courier New", "JetBrains Mono", "Fira Code", "Source Code Pro"], id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Size") {
                    HStack(spacing: Space.sm) {
                        Slider(value: $s.editorFontSize, in: 9...24, step: 1).frame(maxWidth: 220).labelsHidden()
                        Text("\(Int(s.editorFontSize)) pt").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 36, alignment: .trailing)
                    }
                }
                Stepper("Tab width: \(s.tabWidth)", value: $s.tabWidth, in: 2...8)
                Toggle("Wrap lines", isOn: $s.wrapLines)
                Toggle("Show line numbers", isOn: $s.showLineNumbers)
                Toggle("Show invisible characters", isOn: $s.showInvisibles)
                Toggle("Highlight current line", isOn: $s.highlightCurrentLine)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.appearance) { _, new in AppearanceController.apply(new) }
    }
}

struct DetectionSettings: View {
    @State private var settings = Settings.shared
    @State private var modelStatus: ModelAdvisor.Status?
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var s = settings
        Form {
            Toggle("Detect clipboard when the window becomes active", isOn: $s.detectOnFocus)
            Toggle("Read the clipboard for detection", isOn: $s.detectFromClipboard)
            Toggle("Smart Paste switches tools (⌘⌥V)", isOn: $s.detectOnPaste)
            Section {
                Toggle("Ask the on-device model about requests in words", isOn: $s.useOnDeviceModel)
                    .disabled(modelStatus == .missing)
            } footer: {
                SettingsFooter("For a request the Smart Box does not recognise (“what is this timestamp in Tokyo”), the language model built into macOS picks the tool. It only chooses: the tool produces the result, and text that looks like a secret is never shown to it. " + (modelStatus?.summary ?? "Checking…"))
            }
            .task { modelStatus = await ModelAdvisor.status(refresh: true) }
            Section {
                ForEach(ToolCategory.allCases.filter { $0 != .scripting }) { category in
                    let tools = model.registry.tools(in: category)
                    let ignored = tools.filter { s.detectionIgnoreList.contains($0.id) }.count
                    if !tools.isEmpty {
                        DisclosureGroup {
                            ForEach(tools) { tool in
                                Toggle(isOn: Binding(get: { s.detectionIgnoreList.contains(tool.id) }, set: { on in
                                    if on { s.detectionIgnoreList.append(tool.id) } else { s.detectionIgnoreList.removeAll { $0 == tool.id } }
                                })) { Label(tool.name, systemImage: tool.symbol) }
                            }
                        } label: {
                            HStack {
                                Text(category.title)
                                Spacer()
                                if ignored > 0 { Text("\(ignored) ignored").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                            }
                        }
                    }
                }
            } header: {
                Text("Ignore during detection")
            } footer: {
                SettingsFooter("Ignored tools are never suggested for what you paste or copy. You can still open them yourself.")
            }
        }
        .formStyle(.grouped)
    }
}

struct HistorySettings: View {
    @State private var settings = Settings.shared
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false
    @State private var confirmForget = false
    var body: some View {
        @Bindable var s = settings
        Form {
            Toggle("Keep input history", isOn: $s.historyEnabled)
            Picker("Keep history for", selection: $s.historyRetentionDays) {
                Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365); Text("Forever").tag(36500)
            }
            Button("Clear all history…", role: .destructive) { confirmClear = true }
                .confirmationDialog("Delete all history and clipboard entries?", isPresented: $confirmClear) {
                    Button("Delete", role: .destructive) { Task { try? await DataStore.shared.clearHistory(includePinned: false); try? await DataStore.shared.clearClipboard() } }
                }
            // smartbox: what the home box learned from your choices
            Section {
                LabeledContent("Learned suggestions") {
                    Button("Forget…", role: .destructive) { confirmForget = true }
                }
            } header: {
                Text("Smart Box")
            } footer: {
                SettingsFooter("The home box puts the actions you usually pick first. It learns only on this Mac, from what you copy, replace or open.")
            }
            .confirmationDialog("Forget what the Smart Box learned?", isPresented: $confirmForget) {
                Button("Forget", role: .destructive) { Task { await model.smartBox.forgetLearning() } }
            } message: {
                Text("Suggestions go back to detection order. Your history is kept.")
            }
            ClipboardSettingsSection() // clipboard: opt-in capture, privacy note, exclude list
            Section("Tools that never record history") {
                ForEach(model.registry.native) { tool in
                    Toggle(tool.name, isOn: Binding(get: { s.historyDisabledTools.contains(tool.id) }, set: { on in
                        if on { s.historyDisabledTools.append(tool.id) } else { s.historyDisabledTools.removeAll { $0 == tool.id } }
                    }))
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ToolsSettings: View {
    @State private var settings = Settings.shared
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var s = settings
        Form {
            Toggle("Show “Frequently used” section", isOn: $s.showFrequentlyUsed)
            Section("Visible tools") {
                ForEach(ToolCategory.allCases.filter { $0 != .scripting }) { c in
                    DisclosureGroup(c.title) {
                        ForEach(model.registry.tools(in: c)) { tool in
                            Toggle(isOn: Binding(get: { !s.hiddenTools.contains(tool.id) }, set: { on in
                                if on { s.hiddenTools.removeAll { $0 == tool.id } } else { s.hiddenTools.append(tool.id) }
                            })) { Label(tool.name, systemImage: tool.symbol) }
                        }
                    }
                }
            }
            Button("Show all tools") { s.hiddenTools = [] }
        }
        .formStyle(.grouped)
    }
}

struct AdvancedSettings: View {
    @State private var settings = Settings.shared
    @State private var message = ""
    var body: some View {
        Form {
            Button("Export settings…") {
                if let data = try? settings.exportJSON() { FilePanels.save(data, suggestedName: "bitlathe-settings.json") }
            }
            Button("Import settings…") {
                if let url = FilePanels.open().first, let data = try? Data(contentsOf: url) {
                    do { try settings.importJSON(data); message = "Imported." } catch { message = error.localizedDescription }
                }
            }
            Button("Reset to defaults", role: .destructive) { settings.resetToDefaults(); message = "Settings reset." }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            Section("Data") {
                Text("Database: \(StorePaths.database.path)").font(Typography.captionMono).textSelection(.enabled)
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([StorePaths.database]) }
            }
        }
        .formStyle(.grouped)
    }
}
