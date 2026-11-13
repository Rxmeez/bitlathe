import Foundation
import AppKit
import Observation
import BitlatheCore
import BitlatheTools

/// Owns the user-scripts folder: resolves it (default container folder or a security-scoped bookmark),
/// installs the examples on first run, registers scripts in the ToolRegistry and hot-reloads on change.
@MainActor
@Observable
final class ScriptsManager {
    static let shared = ScriptsManager()

    private(set) var folder: URL = ScriptLoader.defaultFolder
    private(set) var report = ScriptLoadReport()
    private(set) var lastReload = Date()
    private(set) var folderError: String?

    @ObservationIgnored private var registry: ToolRegistry?
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var signature = ""
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var debounce: Task<Void, Never>?

    var isCustomFolder: Bool { !Settings.shared.scriptsFolderPath.isEmpty }

    func start(registry: ToolRegistry) {
        self.registry = registry
        resolveFolder()
        installExamplesIfFirstRun()
        reload()
        watch()
    }

    // MARK: Folder

    private func resolveFolder() {
        scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = nil
        folderError = nil
        let s = Settings.shared
        if let data = s.scriptsFolderBookmark, !s.scriptsFolderPath.isEmpty {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
                if url.startAccessingSecurityScopedResource() { scopedURL = url }
                folder = url
                if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) { s.scriptsFolderBookmark = fresh }
                return
            }
            folderError = "Couldn't reopen the chosen folder. Choose it again, or reset to the default."
        }
        folder = ScriptLoader.defaultFolder
    }

    /// Sets a user-chosen folder (from an open panel) and remembers it with a security-scoped bookmark.
    func choose(folder url: URL) {
        let s = Settings.shared
        do {
            s.scriptsFolderBookmark = try url.bookmarkData(options: .withSecurityScope)
            s.scriptsFolderPath = url.path
        } catch {
            folderError = "Couldn't remember that folder: \(error.localizedDescription)"
            return
        }
        applyFolderChange()
    }

    func resetToDefault() {
        let s = Settings.shared
        s.scriptsFolderBookmark = nil
        s.scriptsFolderPath = ""
        applyFolderChange()
    }

    private func applyFolderChange() {
        resolveFolder()
        installExamplesIfFirstRun()
        reload()
        watch()
    }

    private func installExamplesIfFirstRun() {
        guard !isCustomFolder, !UserDefaults.standard.bool(forKey: "bl.scriptsExamplesInstalled") else { return }
        do {
            try ScriptExamples.install(into: ScriptLoader.defaultFolder)
            UserDefaults.standard.set(true, forKey: "bl.scriptsExamplesInstalled")
        } catch {
            folderError = "Couldn't install the example scripts: \(error.localizedDescription)"
        }
    }

    // MARK: Loading

    func reload() {
        guard let registry else { return }
        report = ScriptLoader.loadReport(folder: folder)
        registry.unregister(kind: .script)
        // A script must never shadow a native tool or pipeline id.
        for script in report.scripts where registry.tool(script.id) == nil { registry.register(script.asTool) }
        signature = currentSignature()
        lastReload = Date()
    }

    func installExamples() {
        do { try ScriptExamples.install(into: folder); reload() }
        catch { folderError = "Couldn't copy the examples: \(error.localizedDescription)" }
    }

    @discardableResult
    func newScript() -> URL? {
        do {
            let url = try ScriptExamples.createNewScript(in: folder)
            reload()
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return url
        } catch {
            folderError = "Couldn't create the script: \(error.localizedDescription)"
            return nil
        }
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    // MARK: Watching

    private func watch() {
        source?.cancel(); source = nil
        timer?.invalidate(); timer = nil
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fd = open(folder.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
            src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleReload() } }
            src.setCancelHandler { close(fd) }
            src.resume()
            source = src
        }
        // Directory events miss in-place edits of an existing file, so also compare names + modification times.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.currentSignature() != self.signature else { return }
                self.reload()
            }
        }
    }

    private func scheduleReload() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    private func currentSignature() -> String {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return items.filter { $0.pathExtension.lowercased() == "js" }
            .map { "\($0.lastPathComponent):\((try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate)?.timeIntervalSince1970 ?? 0)" }
            .sorted().joined(separator: "|")
    }
}
