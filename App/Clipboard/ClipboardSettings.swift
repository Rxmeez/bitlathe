import SwiftUI
import BitlatheCore
import BitlatheUI

/// "Developer clipboard history" block for Settings › History & Privacy.
struct ClipboardSettingsSection: View {
    @State private var settings = Settings.shared
    @State private var showExplanation = false
    @State private var confirmClear = false
    @State private var cleared = false

    var body: some View {
        @Bindable var s = settings
        Section {
            Toggle("Developer clipboard history", isOn: Binding(
                get: { s.clipboardHistoryEnabled },
                set: { on in
                    if on && !UserDefaults.standard.bool(forKey: ClipboardMonitor.explainedKey) { showExplanation = true }
                    else { s.clipboardHistoryEnabled = on }
                }))
            Text("Off by default. When on, Bitlathe watches the clipboard while it is running and keeps only text it recognises as a developer format (JSON, JWT, UUID, timestamp, URL, hex, Base64, PEM, cron…). Everything else is discarded without being stored. Items marked concealed or transient, and anything copied from the apps below, are never read. Nothing leaves this Mac. Items are removed after the retention period above.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Clear clipboard history…", role: .destructive) { confirmClear = true }
            if cleared { Text("Clipboard history cleared.").font(.caption).foregroundStyle(.secondary) }
        } header: { Text("Clipboard") }
        .sheet(isPresented: $showExplanation) {
            ClipboardExplanationSheet {
                UserDefaults.standard.set(true, forKey: ClipboardMonitor.explainedKey)
                settings.clipboardHistoryEnabled = true
                showExplanation = false
            } cancel: { showExplanation = false }
        }
        .confirmationDialog("Delete all clipboard history?", isPresented: $confirmClear) {
            Button("Delete", role: .destructive) { ClipboardMonitor.shared.clearAll(); cleared = true }
        }

        Section("Never record clipboard from these apps") {
            ExcludedAppsEditor()
        }
    }
}

private struct ExcludedAppsEditor: View {
    @State private var settings = Settings.shared

    var body: some View {
        ForEach(settings.clipboardExcludedApps, id: \.self) { id in
            let info = SourceApp.info(id)
            HStack(spacing: Space.sm) {
                Image(nsImage: info?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                    .resizable().frame(width: 20, height: 20)
                    .opacity(info == nil ? 0.45 : 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(info?.name ?? Self.knownNames[id] ?? id)
                    Text(info == nil ? "\(id) · Not installed" : id)
                        .font(Typography.captionMono).foregroundStyle(Palette.subtle)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button { settings.clipboardExcludedApps.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("Stop excluding \(info?.name ?? Self.knownNames[id] ?? id)")
                    .accessibilityLabel("Remove \(info?.name ?? Self.knownNames[id] ?? id)")
            }
        }
        Menu("Add Running App") {
            let running = candidates
            if running.isEmpty { Text("No other apps running") }
            ForEach(running, id: \.bundleIdentifier) { app in
                Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                    if let id = app.bundleIdentifier { settings.clipboardExcludedApps.append(id) }
                }
            }
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    /// Names for the password managers excluded by default, so the list reads well even when they are not installed.
    static let knownNames: [String: String] = [
        "com.agilebits.onepassword7": "1Password 7",
        "com.1password.1password": "1Password",
        "com.bitwarden.desktop": "Bitwarden",
        "com.lastpass.LastPass": "LastPass",
        "com.dashlane.dashlanephonefinal": "Dashlane",
        "com.apple.keychainaccess": "Keychain Access",
        "com.apple.Passwords": "Passwords",
        "org.keepassxc.keepassxc": "KeePassXC",
    ]

    private var candidates: [NSRunningApplication] {
        let have = Set(settings.clipboardExcludedApps)
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !have.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

/// Shown once, the first time the user turns clipboard history on.
private struct ClipboardExplanationSheet: View {
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Image(systemName: "list.clipboard").font(.system(size: 34)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
            Text("Turn on developer clipboard history?").font(Typography.title)
            VStack(alignment: .leading, spacing: Space.md) {
                point("eye", "Bitlathe will check the clipboard about twice a second while it is running.")
                point("line.3.horizontal.decrease", "Only text it recognises as a developer format is kept. Everything else is thrown away immediately.")
                point("lock.shield", "Concealed and transient items, and copies from password managers and other apps you list, are never read.")
                point("internaldrive", "History stays in Bitlathe’s database on this Mac. Nothing is sent anywhere.")
                point("trash", "Delete single items or everything at any time, and turn it off again in Settings.")
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Turn On", action: confirm).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 460)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
