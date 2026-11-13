import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

/// Applies a parsed `bitlathe://` URL. Every failure becomes a toast; nothing here can crash the app.
@MainActor
enum DeepLinkRouter {
    static func handle(_ urls: [URL]) {
        for url in urls { handle(url) }
    }

    static func handle(_ url: URL) {
        let link: DeepLink
        do { link = try DeepLink.parse(url) } catch {
            fail(error)
            return
        }
        Task { @MainActor in
            do { try await perform(link) } catch { fail(error) }
        }
    }

    private static func perform(_ link: DeepLink) async throws {
        let model = AppModel.shared
        let input = link.input ?? ""
        switch link.target {
        case .tool(let id):
            guard let tool = model.registry.tool(id) else { throw DeepLink.ParseError("Unknown tool \"\(id)\".") }
            let options = try link.resolveOptions(for: tool.optionFields)
            switch link.action {
            case .open:
                present { model.open(toolID: id, input: link.input, options: options) }
            case .copy, .replace:
                let r = try await HeadlessRunner.runTool(id: id, input: input, options: options)
                deliver(r, link: link)
            }
        case .pipeline(let name):
            switch link.action {
            case .open:
                let p = try await HeadlessRunner.findPipeline(name)
                present { model.open(toolID: p.toolID, input: link.input) }
            case .copy, .replace:
                deliver(try await HeadlessRunner.runPipeline(name, input: input), link: link)
            }
        case .detect:
            guard !input.isEmpty else { throw DeepLink.ParseError("detect needs input= or input64=.") }
            switch link.action {
            case .open:
                guard let best = HeadlessRunner.bestDetection(for: input) else { throw DeepLink.ParseError("Nothing recognisable in that input.") }
                present { model.open(toolID: best.tool.id, input: input, options: best.score.options) }
            case .copy, .replace:
                deliver(try await HeadlessRunner.runSmart(input: input), link: link)
            }
        }
    }

    /// Brings the app forward (re-creating the main window if all were closed) and runs `body`.
    private static func present(_ body: () -> Void) {
        body()
        WindowOpener.shared.ensureMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func deliver(_ r: HeadlessRunner.Result, link: DeepLink) {
        Clipboard.copy(r.text, toast: nil)
        let verb = link.action == .replace ? "Replaced with" : "Copied"
        ToastCenter.shared.show("\(verb) \(r.toolName) output", symbol: "doc.on.clipboard.fill")
    }

    private static func fail(_ error: Error) {
        ToastCenter.shared.show(error.localizedDescription, symbol: "xmark.octagon.fill")
    }
}
