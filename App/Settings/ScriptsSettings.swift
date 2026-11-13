import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

struct ScriptsSettings: View {
    @State private var manager = ScriptsManager.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(manager.folder.path).font(.callout).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        Text(manager.isCustomFolder ? "Custom folder" : "Default folder (inside Bitlathe's container)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Choose Folder…") { chooseFolder() }
                    Button("Use Default") { manager.resetToDefault() }.disabled(!manager.isCustomFolder)
                    Spacer()
                    Button("Open in Finder") { manager.revealFolder() }
                    Button("Reload") { manager.reload() }
                }
                if let e = manager.folderError { Text(e).font(.caption).foregroundStyle(Palette.danger) }
            } footer: {
                Text("Bitlathe watches this folder and reloads scripts whenever a .js file changes. Scripts appear in the sidebar, the command palette and the bl command line.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Loaded scripts (\(manager.report.scripts.count))") {
                let problems = manager.report.issues.filter(\.isFatal)
                if manager.report.scripts.isEmpty && problems.isEmpty {
                    Text("No scripts in this folder yet.").foregroundStyle(.secondary)
                }
                ForEach(manager.report.scripts) { script in
                    row(symbol: script.symbol, title: script.name, detail: script.summary, url: script.url,
                        issues: manager.report.issues(for: script.url))
                }
                ForEach(problems.filter { p in !manager.report.scripts.contains { $0.url == p.url } }) { p in
                    row(symbol: "exclamationmark.triangle", title: p.url.lastPathComponent, detail: nil, url: p.url, issues: [p])
                }
            }
            Section {
                HStack {
                    Button("New Script…") { manager.newScript() }
                    Button("Copy Example Scripts") { manager.installExamples() }
                    Spacer()
                    Text("Loaded \(manager.lastReload.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(symbol: String, title: String, detail: String?, url: URL, issues: [ScriptLoadIssue]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : "scroll")
                .frame(width: 20).foregroundStyle(issues.contains(where: \.isFatal) ? Palette.danger : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).fontWeight(.medium)
                    Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                }
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                ForEach(issues) { Text($0.message).font(.caption).foregroundStyle($0.isFatal ? Palette.danger : Palette.warning) }
            }
            Spacer()
            Button { manager.reveal(url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Reveal in Finder")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder that holds your Bitlathe scripts."
        panel.directoryURL = manager.folder
        if panel.runModal() == .OK, let url = panel.url { manager.choose(folder: url) }
    }
}
