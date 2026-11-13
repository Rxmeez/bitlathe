import AppKit
import SwiftUI
import QuickLookUI

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let model = try await Task.detached(priority: .userInitiated) { try PreviewBuilder.build(url: url) }.value
        let host = NSHostingView(rootView: PreviewRoot(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.topAnchor.constraint(equalTo: view.topAnchor), host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
