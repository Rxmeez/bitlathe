import Foundation

/// Which copy of the app is running. The Debug configuration builds "Bitlathe Dev" (bundle id
/// `com.bitlathe.app.dev`) so it can run beside the installed app with its own settings, data, URL scheme,
/// hotkeys and menu bar icon.
public enum AppFlavour {
    public static let devBundleSuffix = ".dev"

    public static var isDev: Bool { Bundle.main.bundleIdentifier?.hasSuffix(devBundleSuffix) == true }

    /// "Bitlathe" or "Bitlathe Dev".
    public static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "Bitlathe"
    }
}
