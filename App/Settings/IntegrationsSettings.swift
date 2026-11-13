import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

/// Settings › Integrations: `bl` CLI status, URL scheme tester, Raycast / Alfred instructions, Services note.
struct IntegrationsSettings: View {
    @State private var cli = CLIProbe.probe()
    @State private var testURL = "bitlathe://tool/json.format?input=%7B%22a%22%3A1%7D&action=open"
    @State private var urlMessage = ""
    @State private var copied = ""

    private static let installCommand = "swift build -c release --product bl && sudo cp .build/release/bl /usr/local/bin/bl"

    var body: some View {
        Form {
            Section("Command line tool (bl)") {
                LabeledContent("Status") {
                    if let path = cli.path {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.success)
                        Text(path).font(Typography.captionMono).textSelection(.enabled).help(path)
                    } else {
                        Label("Not installed", systemImage: "xmark.circle").foregroundStyle(.secondary)
                    }
                }
                if cli.path != nil {
                    LabeledContent("Version", value: cli.version ?? "unavailable (the sandbox may block running bl from here)")
                }
                if cli.path == nil {
                    Text("bl is built from the Bitlathe repository. From its root, run in Terminal:")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(Self.installCommand).font(Typography.captionMono).textSelection(.enabled).lineLimit(2)
                        Spacer()
                        Button("Copy") { copy(Self.installCommand, label: "install command") }
                    }
                }
                HStack {
                    Button("Re-check") { cli = CLIProbe.probe() }
                    if !copied.isEmpty { Text("Copied \(copied).").font(.caption).foregroundStyle(.secondary) }
                }
            }

            Section("URL scheme") {
                TextField("URL", text: $testURL).font(Typography.captionMono).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Open") { openTestURL() }.disabled(testURL.isEmpty)
                    Text(urlMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("bitlathe://tool/<id>?input=…&action=open|copy · bitlathe://detect?input=…")
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
                Button("Copy setup command") { copy(steps, label: title.lowercased() + " command") }
            }
            Text("\(folder)/README.md").font(Typography.captionMono).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = label
    }

    private func openTestURL() {
        guard let url = URL(string: testURL.trimmingCharacters(in: .whitespaces)), url.scheme?.lowercased() == "bitlathe" else {
            urlMessage = "Enter a bitlathe:// URL."
            return
        }
        urlMessage = NSWorkspace.shared.open(url) ? "Opened." : "Could not open the URL."
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
