import Foundation
import BitlatheCore

/// Runs the `bl-advisor` helper, which asks the language model built into macOS (on this Mac, no network) which tool
/// a request in words is asking for. What goes in and what is accepted back is decided by `SmartBox.Advisor`.
enum ModelAdvisor {
    enum Status: Equatable {
        case available
        /// The helper is there but the model cannot be used; the text says why ("Apple Intelligence is switched off…").
        case unavailable(String)
        /// This build has no helper (the App Store build, or a development build without it).
        case missing

        var summary: String {
            switch self {
            case .available: "Ready. Runs on this Mac; nothing is sent anywhere."
            case .unavailable(let why): "Not available: \(why)."
            case .missing: "Not included in this copy of Bitlathe."
            }
        }
    }

    static var helper: URL? {
        // Contents/Helpers, where the build puts it (`url(forAuxiliaryExecutable:)` does not always look there).
        let candidates = [Bundle.main.url(forAuxiliaryExecutable: "bl-advisor"),
                          Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/bl-advisor")]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    @MainActor private static var cached: (status: Status, at: Date)?

    /// Whether the model can be used right now. Remembered for a minute: it changes rarely (a download finishing,
    /// a switch in System Settings), and asking starts a process.
    @MainActor
    static func status(refresh: Bool = false) async -> Status {
        if !refresh, let c = cached, Date().timeIntervalSince(c.at) < 60 { return c.status }
        let status: Status
        if let helper {
            let r = await run(helper, arguments: ["--status"], input: nil, timeout: 5)
            if r.code == 0 { status = .available } else {
                let text = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
                status = .unavailable(text.hasPrefix("unavailable: ") ? String(text.dropFirst(13)) : (text.isEmpty ? "the helper did not answer" : text))
            }
        } else {
            status = .missing
        }
        cached = (status, Date())
        return status
    }

    /// The model's reply to a query, or nil when there is no usable model or it failed. Never throws: a missing
    /// suggestion is not an error the person needs to hear about.
    @MainActor
    static func ask(_ query: SmartBox.Advisor.Query) async -> String? {
        guard let helper, await status() == .available else { return nil }
        guard let body = try? JSONSerialization.data(withJSONObject: ["instructions": query.instructions, "prompt": query.prompt]) else { return nil }
        let r = await run(helper, arguments: [], input: body, timeout: 12)
        if r.code == 3 { cached = nil }   // became unavailable: check again next time
        return r.code == 0 && !r.output.isEmpty ? r.output : nil
    }

    private static func run(_ url: URL, arguments: [String], input: Data?, timeout: TimeInterval) async -> (code: Int32, output: String) {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            let out = Pipe(), stdin = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()
            process.standardInput = stdin
            do { try process.run() } catch { return (-1, "") }
            if let input { stdin.fileHandleForWriting.write(input) }
            try? stdin.fileHandleForWriting.close()
            let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            killer.cancel()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
