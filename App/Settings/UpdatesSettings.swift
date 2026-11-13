// release: the Updates section of Settings › General (Direct build only).
import SwiftUI
import BitlatheCore

/// Update checks, shown as a section at the end of Settings › General. Empty in the App Store build,
/// where the Mac App Store handles updates.
struct UpdatesSection: View {
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
        #if DIRECT_DISTRIBUTION
        @Bindable var s = settings
        Section {
            LabeledContent("Version", value: versionString)
            // Shown off (and disabled) when this build cannot check, rather than "on but not working".
            Toggle("Check for updates automatically", isOn: updater.isConfigured ? $s.automaticUpdates : .constant(false))
                .disabled(!updater.isConfigured)
                .onChange(of: settings.automaticUpdates) { _, on in updater.setAutomaticChecks(on) }
            Button("Check for Updates Now") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        } header: {
            Text("Updates")
        } footer: {
            if updater.isConfigured {
                SettingsFooter("Updates are signed and verified before they are installed.")
            } else {
                SettingsFooter("This build has no update signing key, so update checks are off. Release builds include one.")
            }
        }
        #else
        EmptyView()
        #endif
    }
}
