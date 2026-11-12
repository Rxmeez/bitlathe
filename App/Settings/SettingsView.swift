import SwiftUI
import BitlatheCore
import BitlatheUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintbrush") }
            EditorSettings().tabItem { Label("Editor", systemImage: "text.cursor") }
            DetectionSettings().tabItem { Label("Detection", systemImage: "wand.and.stars") }
            HistorySettings().tabItem { Label("History & Privacy", systemImage: "clock.arrow.circlepath") }
            ToolsSettings().tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 560, height: 440)
    }
}

struct GeneralSettings: View {
    @State private var settings = Settings.shared
    var body: some View {
        @Bindable var s = settings
        Form {
            Toggle("Launch at login", isOn: $s.launchAtLogin)
            Picker("Show in", selection: $s.dockMode) { ForEach(DockMode.allCases, id: \.self) { Text($0.title).tag($0) } }
            Text("Menu bar Quick Panel, global hotkeys and Services arrive in the next milestone.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettings: View {
    @State private var settings = Settings.shared
    var body: some View {
        @Bindable var s = settings
        Form {
            Picker("Appearance", selection: $s.appearance) { ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) } }
            Toggle("Use Bitlathe accent colour", isOn: $s.useAppAccent)
            Picker("Editor theme", selection: $s.editorTheme) { ForEach(EditorTheme.all) { Text($0.name).tag($0.id) } }
            Toggle("Reduce motion", isOn: $s.reduceMotionOverride)
        }
        .formStyle(.grouped)
        .onChange(of: settings.appearance) { _, new in AppearanceController.apply(new) }
    }
}

struct EditorSettings: View {
    @State private var settings = Settings.shared
    var body: some View {
        @Bindable var s = settings
        Form {
            Picker("Font", selection: $s.editorFontName) {
                ForEach(["SF Mono", "Menlo", "Monaco", "Courier New", "JetBrains Mono", "Fira Code", "Source Code Pro"], id: \.self) { Text($0).tag($0) }
            }
            Slider(value: $s.editorFontSize, in: 9...24, step: 1) { Text("Size: \(Int(s.editorFontSize)) pt") }
            Stepper("Tab width: \(s.tabWidth)", value: $s.tabWidth, in: 2...8)
            Toggle("Wrap lines", isOn: $s.wrapLines)
            Toggle("Show line numbers", isOn: $s.showLineNumbers)
            Toggle("Show invisible characters", isOn: $s.showInvisibles)
            Toggle("Highlight current line", isOn: $s.highlightCurrentLine)
        }
        .formStyle(.grouped)
    }
}

struct DetectionSettings: View {
    @State private var settings = Settings.shared
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var s = settings
        Form {
            Toggle("Detect clipboard when the window becomes active", isOn: $s.detectOnFocus)
            Toggle("Read the clipboard for detection", isOn: $s.detectFromClipboard)
            Toggle("Smart Paste switches tools (⌘⌥V)", isOn: $s.detectOnPaste)
            Section("Ignore these tools during detection") {
                ForEach(model.registry.native) { tool in
                    Toggle(tool.name, isOn: Binding(get: { s.detectionIgnoreList.contains(tool.id) }, set: { on in
                        if on { s.detectionIgnoreList.append(tool.id) } else { s.detectionIgnoreList.removeAll { $0 == tool.id } }
                    }))
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct HistorySettings: View {
    @State private var settings = Settings.shared
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false
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
            Section("Tools that never record history") {
                ForEach(model.registry.native) { tool in
                    Toggle(tool.name, isOn: Binding(get: { s.historyDisabledTools.contains(tool.id) }, set: { on in
                        if on { s.historyDisabledTools.append(tool.id) } else { s.historyDisabledTools.removeAll { $0 == tool.id } }
                    }))
                }
            }
            Section {
                Toggle("Developer clipboard history (opt-in)", isOn: $s.clipboardHistoryEnabled)
                Text("Only items that look like developer formats are kept, password managers are excluded, and nothing ever leaves this Mac. The capture service ships with the menu bar milestone.").font(.caption).foregroundStyle(.secondary)
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
