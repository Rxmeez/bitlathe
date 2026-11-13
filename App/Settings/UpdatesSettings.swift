// release: the "Updates" settings tab. In the App Store build the tab is not added and this view shows only the version.
import SwiftUI
import BitlatheCore

struct UpdatesSettings: View {
    @State private var settings = Settings.shared
    #if DIRECT_DISTRIBUTION
    @StateObject private var updater = Updater.shared
    #endif

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        @Bindable var s = settings
        Form {
            LabeledContent("Current version", value: versionString)
            #if DIRECT_DISTRIBUTION
            Section {
                Button("Check for updates now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                Toggle("Check for updates automatically", isOn: $s.automaticUpdates)
                    .disabled(!updater.isConfigured)
                    .onChange(of: settings.automaticUpdates) { _, on in updater.setAutomaticChecks(on) }
            } footer: {
                if updater.isConfigured {
                    Text("Updates are signed and verified before they are installed.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("This build has no update signing key (SUPublicEDKey), so update checks are off. Release builds set it; see Docs/Release.md.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            #else
            Text("Updates are delivered by the Mac App Store.").font(.caption).foregroundStyle(.secondary)
            #endif
        }
        .formStyle(.grouped)
    }
}
