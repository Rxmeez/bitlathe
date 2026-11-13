// release: Sparkle wiring. Compiled only into the Direct (Developer ID) build.
#if DIRECT_DISTRIBUTION
import Foundation
import Sparkle
import BitlatheCore

/// Owns the Sparkle updater. The feed URL comes from Info.plist `SUFeedURL`; automatic checks follow
/// `Settings.automaticUpdates`. The updater only starts when `SUPublicEDKey` is set, so unconfigured
/// development builds never show Sparkle's "insecure update" alert.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController
    /// False when the build has no EdDSA public key (see Docs/Release.md).
    let isConfigured: Bool
    var feedURL: String { (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "" }

    private init() {
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) ?? ""
        isConfigured = !key.trimmingCharacters(in: .whitespaces).isEmpty
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        if isConfigured {
            controller.updater.automaticallyChecksForUpdates = Settings.shared.automaticUpdates
            controller.startUpdater()
        }
    }

    var canCheckForUpdates: Bool { isConfigured && controller.updater.canCheckForUpdates }

    func checkForUpdates() { if isConfigured { controller.checkForUpdates(nil) } }

    func setAutomaticChecks(_ on: Bool) {
        guard isConfigured else { return }
        controller.updater.automaticallyChecksForUpdates = on
    }
}
#endif
