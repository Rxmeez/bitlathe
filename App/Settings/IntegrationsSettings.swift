import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

/// Settings › Integrations: `bl` CLI status, URL scheme tester, Raycast / Alfred instructions, Services note.
struct IntegrationsSettings: View {
    @State private var cli = CLIProbe.probe()
    // The running app's own scheme, so the dev build's tester opens the dev build, not the installed app.
    @State private var testURL = "\(DeepLink.appScheme)://tool/json.format?input=%7B%22a%22%3A1%7D&action=open"
    @State private var urlMessage = ""
    @State private var installMessage = ""
    @State private var installFailed = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    if let path = cli.path {
                        HStack(spacing: Space.sm) {
                            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.success)
                            Text((path as NSString).abbreviatingWithTildeInPath).font(Typography.captionMono)
                                .foregroundStyle(.secondary).textSelection(.enabled).help(path)
                        }
                    } else {
                        Label("Not installed", systemImage: "xmark.circle").foregroundStyle(.secondary)
                    }
                }
                if cli.path != nil, let version = cli.version {
                    LabeledContent("Version", value: version)
                }
                if CLIInstaller.isAvailable {
                    HStack {
                        Button(cli.path == nil ? "Install bl…" : "Reinstall bl…") { install() }
                        Button("Re-check") { cli = CLIProbe.probe() }
                        if !installMessage.isEmpty {
                            Text(installMessage).font(.caption).foregroundStyle(installFailed ? Palette.danger : .secondary)
                                .lineLimit(2).textSelection(.enabled)
                        }
                    }
                    if let link = CLIInstaller.symlinkCommand {
                        HStack {
                            Text(link).font(Typography.captionMono).foregroundStyle(.secondary)
                                .textSelection(.enabled).lineLimit(1).truncationMode(.middle).help(link)
                            Spacer()
                            CopyButton(text: link)
                        }
                    }
                } else {
                    Text(CLIInstaller.unavailableMessage).font(.caption).foregroundStyle(.secondary)
                    Button("Re-check") { cli = CLIProbe.probe() }
                }
            } header: {
                Text("Command line tool (bl)")
            } footer: {
                if CLIInstaller.isAvailable {
                    SettingsFooter("Install copies bl from inside Bitlathe into a folder you choose, such as /usr/local/bin. Or link it from Terminal with the command above.")
                }
            }

            // mcp: Bitlathe's tools for AI agents, served by `bl mcp`
            Section {
                LabeledContent("Claude Code") {
                    HStack {
                        Text(Self.claudeCommand(bl: mcpBinary)).font(Typography.captionMono).foregroundStyle(.secondary)
                            .textSelection(.enabled).lineLimit(1).truncationMode(.middle).help(Self.claudeCommand(bl: mcpBinary))
                        CopyButton(text: Self.claudeCommand(bl: mcpBinary))
                    }
                }
                LabeledContent("Other clients") {
                    HStack {
                        Text(#"{"mcpServers": {"bitlathe": {"command": "…", "args": ["mcp"]}}}"#)
                            .font(Typography.captionMono).foregroundStyle(.secondary).lineLimit(1)
                        CopyButton(text: Self.jsonConfig(bl: mcpBinary))
                    }
                }
            } header: {
                Text("AI agents (MCP)")
            } footer: {
                SettingsFooter("bl mcp gives Claude Code, Claude Desktop and other agents Bitlathe's tools: detect, smart_run, run_tool, list_tools and run_pipeline. It runs on this Mac and only sees what the agent sends it.")
            }

            Section("URL scheme") {
                TextField("URL", text: $testURL).font(Typography.captionMono).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Open") { openTestURL() }.disabled(testURL.isEmpty)
                    Text(urlMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(DeepLink.appScheme)://tool/<id>?input=…&action=open|copy · \(DeepLink.appScheme)://detect?input=…")
                    .font(Typography.captionMono).foregroundStyle(.secondary)
            }

            Section("Raycast and Alfred") {
                integrationRow("Raycast extension", folder: "Integrations/raycast",
                               steps: "cd Integrations/raycast && npm install && npm run dev")
                integrationRow("Alfred workflow", folder: "Integrations/alfred",
                               steps: "Integrations/alfred/build.sh && open Integrations/alfred/Bitlathe.alfredworkflow")
                Text("Both read their setup from the README.md in those folders of the Bitlathe repository, and call bl, so install the CLI first.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Services") {
                Text("Bitlathe adds services to the Services menu (right-click selected text in most apps, or app menu › Services). If they are missing, enable them in System Settings › Keyboard › Keyboard Shortcuts › Services › Text.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func integrationRow(_ title: String, folder: String, steps: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                CopyButton(text: steps, title: "Copy setup command")
            }
            Text("\(folder)/README.md").font(Typography.captionMono).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private func install() {
        switch CLIInstaller.install() {
        case .installed(let url):
            installMessage = "Installed to \((url.path as NSString).abbreviatingWithTildeInPath)."
            installFailed = false
        case .cancelled:
            installMessage = ""
        case .unavailable(let message), .failed(let message):
            installMessage = message
            installFailed = true
        }
        cli = CLIProbe.probe()
    }

    private func openTestURL() {
        guard let url = URL(string: testURL.trimmingCharacters(in: .whitespaces)), DeepLink.acceptedSchemes.contains(url.scheme?.lowercased() ?? "") else {
            urlMessage = "Enter a bitlathe:// URL."
            return
        }
        urlMessage = NSWorkspace.shared.open(url) ? "Opened." : "Could not open the URL."
    }
}

extension IntegrationsSettings {
    /// The `bl` an agent should launch: the installed copy if there is one, else the one inside this app.
    var mcpBinary: String { cli.path ?? CLIInstaller.bundledCLI?.path ?? "bl" }

    static func quoted(_ path: String) -> String { path.contains(" ") ? "'\(path)'" : path }

    static func claudeCommand(bl: String) -> String { "claude mcp add bitlathe -- \(quoted(bl)) mcp" }

    static func jsonConfig(bl: String) -> String {
        let escaped = bl.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "{\n  \"mcpServers\": {\n    \"bitlathe\": { \"command\": \"\(escaped)\", \"args\": [\"mcp\"] }\n  }\n}"
    }
}

/// A copy button that confirms with a checkmark for a moment instead of a separate message.
private struct CopyButton: View {
    let text: String
    var title = "Copy"
    @State private var done = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            done = true
            Task { try? await Task.sleep(for: .seconds(1.5)); done = false }
        } label: {
            Label(done ? "Copied" : title, systemImage: done ? "checkmark" : "doc.on.doc")
        }
        .help("Copy “\(text)”")
    }
}

/// Finds `bl` in the usual places (plus next to the app) and asks it for its version.
enum CLIProbe {
    struct Result { var path: String?; var version: String? }

    static func probe() -> Result {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = ["/usr/local/bin/bl", "/opt/homebrew/bin/bl", "\(home)/.local/bin/bl"]
        if let real = getpwuid(getuid())?.pointee.pw_dir { candidates.append(String(cString: real) + "/.local/bin/bl") }
        if let aux = Bundle.main.url(forAuxiliaryExecutable: "bl")?.path { candidates.append(aux) }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return Result(path: nil, version: nil) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return Result(path: path, version: process.terminationStatus == 0 && !text.isEmpty ? text : nil)
        } catch {
            return Result(path: path, version: nil)
        }
    }
}
