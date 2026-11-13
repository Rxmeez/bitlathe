// release: installs the bundled `bl` command-line tool. The Integrations settings pane (another worker) calls `CLIInstaller.install()`.
import AppKit
import Foundation

/// Copies the `bl` binary embedded in `Bitlathe.app/Contents/Helpers` to a folder the user picks.
/// Sandbox-safe: the destination comes from an `NSOpenPanel`, which grants write access to that folder only.
/// The Mac App Store build does not embed `bl` (a sandbox-inheriting helper cannot run once copied out), so
/// `isAvailable` is false there and callers should show `unavailableMessage`.
@MainActor
enum CLIInstaller {
    enum Outcome: Equatable {
        case installed(URL)
        case cancelled
        case unavailable(String)
        case failed(String)
    }

    /// The embedded CLI, or nil when this build does not ship one.
    static var bundledCLI: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/bl")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var isAvailable: Bool { bundledCLI != nil }

    static let unavailableMessage =
        "This build does not include the command-line tool. Install it with Homebrew (brew install --cask bitlathe) or download the direct build from GitHub."

    /// Shell command that links the bundled CLI into a folder on PATH (for people who prefer a symlink over a copy).
    static var symlinkCommand: String? {
        guard let cli = bundledCLI else { return nil }
        return "sudo ln -sf '\(cli.path)' /usr/local/bin/bl"
    }

    /// Asks the user for a folder, then copies `bl` into it (replacing an older copy).
    @discardableResult
    static func install() -> Outcome {
        guard let cli = bundledCLI else { return .unavailable(unavailableMessage) }
        let panel = NSOpenPanel()
        panel.title = "Install the bl command"
        panel.message = "Choose a folder on your PATH, such as /usr/local/bin or ~/.local/bin."
        panel.prompt = "Install Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return .cancelled }
        return install(to: folder, from: cli)
    }

    /// Copy step, separated from the panel so it can be tested.
    static func install(to folder: URL, from cli: URL) -> Outcome {
        let fm = FileManager.default
        let dest = folder.appendingPathComponent("bl")
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) || (try? fm.destinationOfSymbolicLink(atPath: dest.path)) != nil {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: cli, to: dest)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
            return .installed(dest)
        } catch {
            let hint = symlinkCommand.map { " You can also run: \($0)" } ?? ""
            return .failed("Couldn't write to \(folder.path): \(error.localizedDescription).\(hint)")
        }
    }
}
