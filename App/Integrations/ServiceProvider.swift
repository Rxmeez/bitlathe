import AppKit
import BitlatheCore
import BitlatheUI

/// macOS Services menu provider. Selected text in any app is transformed and returned in place.
/// Message names match `NSServices` in Info.plist (project.yml): `formatJSON`, `decodeBase64`, `smartTransform`.
final class ServiceProvider: NSObject {
    typealias ErrorPointer = AutoreleasingUnsafeMutablePointer<NSString>

    @MainActor static let shared = ServiceProvider()

    @MainActor
    static func register() {
        NSApp.servicesProvider = shared
        NSUpdateDynamicServices()
    }

    @objc func formatJSON(_ pboard: NSPasteboard, userData: String, error: ErrorPointer) {
        transform(pboard, error: error) { text in
            try await HeadlessRunner.runTool(id: "json.format", input: text)
        }
    }

    @objc func decodeBase64(_ pboard: NSPasteboard, userData: String, error: ErrorPointer) {
        transform(pboard, error: error) { text in
            try await HeadlessRunner.runTool(id: "base64.text", input: text, options: ["mode": .string("decode")])
        }
    }

    @objc func smartTransform(_ pboard: NSPasteboard, userData: String, error: ErrorPointer) {
        transform(pboard, error: error) { text in
            try await HeadlessRunner.runSmart(input: text)
        }
    }

    private func transform(_ pboard: NSPasteboard, error: ErrorPointer,
                           _ work: @escaping @MainActor @Sendable (String) async throws -> HeadlessRunner.Result) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "Bitlathe: no text selected." as NSString
            return
        }
        // Services are delivered on the main thread; bridge to the async tools by spinning the run loop.
        let outcome = MainActor.assumeIsolated { HeadlessRunner.runBlocking { try await work(text) } }
        switch outcome {
        case .success(let r):
            pboard.clearContents()
            pboard.setString(r.text, forType: .string)
        case .failure(let e):
            error.pointee = "Bitlathe: \(e.localizedDescription)" as NSString
        }
    }
}
