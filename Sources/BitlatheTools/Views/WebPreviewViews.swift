import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers
import BitlatheCore
import BitlatheUI

// MARK: - Assets

/// Bundled JS/CSS read once and cached. Mermaid is ~3.5 MB, so it is loaded off the main thread.
enum WebPreviewAssets {
    struct Bundle: Sendable {
        var hljsJS: String?
        var hljsLight: String?
        var hljsDark: String?
        var mermaidJS: String?
    }

    private static func read(_ name: String) -> String? {
        JSBundles.resourceURL(name).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// Lazily initialised exactly once (thread-safe static).
    static let shared: Bundle = Bundle(hljsJS: read("highlight.min.js"), hljsLight: read("hljs-github.min.css"),
                                       hljsDark: read("hljs-github-dark.min.css"), mermaidJS: read("mermaid.min.js"))

    static func load() async -> Bundle {
        await Task.detached(priority: .userInitiated) { shared }.value
    }
}

// MARK: - WebPreview

/// Offline, non-persistent WKWebView host. All network is blocked by a content rule list; links open in the
/// default browser only on an explicit user click.
struct WebPreview: NSViewRepresentable {
    var html: String
    var javascript: Bool
    /// "auto", "light" or "dark".
    var appearance: String
    var reloadToken: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = javascript
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false
        context.coordinator.web = web
        context.coordinator.install(on: web)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        web.appearance = switch appearance {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
        context.coordinator.update(html: html, javascript: javascript, token: reloadToken)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.cancel()
        web.navigationDelegate = nil
        web.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var web: WKWebView?
        private var ready = false
        private var html = ""
        private var javascript = false
        private var token = 0
        private var loaded: (html: String, javascript: Bool, token: Int)?
        private var debounce: Task<Void, Never>?
        private var scrollY: Double = 0
        private var allowJS = false

        private static var ruleListTask: Task<WKContentRuleList?, Never>?

        /// Blocks every URL, then un-blocks about:/data:/blob: so the inline document itself still renders.
        private static func ruleList() -> Task<WKContentRuleList?, Never> {
            if let t = ruleListTask { return t }
            let json = """
            [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
             {"trigger":{"url-filter":"^about:"},"action":{"type":"ignore-previous-rules"}},
             {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}},
             {"trigger":{"url-filter":"^blob:"},"action":{"type":"ignore-previous-rules"}}]
            """
            let t = Task { @MainActor in
                try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "bitlathe.block-all", encodedContentRuleList: json)
            }
            ruleListTask = t
            return t
        }

        func install(on web: WKWebView) {
            Task { @MainActor [weak self, weak web] in
                let list = await Self.ruleList().value
                guard let self, let web else { return }
                if let list { web.configuration.userContentController.add(list) }
                self.ready = true
                self.reload(now: true)
            }
        }

        func cancel() { debounce?.cancel() }

        func update(html: String, javascript: Bool, token: Int) {
            self.html = html
            self.javascript = javascript
            self.token = token
            guard ready else { return }
            if let l = loaded, l.html == html, l.javascript == javascript, l.token == token { return }
            let immediate = loaded == nil || loaded?.javascript != javascript || loaded?.token != token
            reload(now: immediate)
        }

        private func reload(now: Bool) {
            debounce?.cancel()
            debounce = Task { @MainActor [weak self] in
                if !now { try? await Task.sleep(for: .milliseconds(180)) }
                guard !Task.isCancelled, let self, let web = self.web else { return }
                if self.loaded != nil {
                    if let y = try? await web.evaluateJavaScript("window.scrollY") as? Double { self.scrollY = y }
                }
                guard !Task.isCancelled else { return }
                self.allowJS = self.javascript
                self.loaded = (self.html, self.javascript, self.token)
                web.loadHTMLString(self.html, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let y = scrollY
            guard y > 0 else { return }
            Task { @MainActor [weak webView] in
                _ = try? await webView?.evaluateJavaScript("window.scrollTo(0,\(y))")
                try? await Task.sleep(for: .milliseconds(350))
                _ = try? await webView?.evaluateJavaScript("window.scrollTo(0,\(y))")
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
            preferences.allowsContentJavaScript = allowJS
            let url = navigationAction.request.url
            let scheme = url?.scheme?.lowercased()
            if navigationAction.navigationType == .linkActivated, let url {
                if scheme == "http" || scheme == "https" || scheme == "mailto" { NSWorkspace.shared.open(url) }
                else if scheme == "about", url.absoluteString.contains("#") { return (.allow, preferences) }
                return (.cancel, preferences)
            }
            if navigationAction.navigationType == .other || navigationAction.navigationType == .reload,
               scheme == nil || scheme == "about" || scheme == "data" {
                return (.allow, preferences)
            }
            return (.cancel, preferences)
        }
    }
}

// MARK: - Shared screen

/// Editor | live preview with a small toolbar on the preview pane.
private struct WebPreviewScreen<Badges: View, Menus: View>: View {
    @Bindable var session: ToolSession
    let document: String?
    let javascript: Bool
    let appearance: String
    let exportName: String
    @ViewBuilder var badges: Badges
    @ViewBuilder var optionMenu: Menus

    @State private var reloadToken = 0

    var body: some View {
        let config = EditorConfig.current
        SplitPane(orientation: $session.orientation, initialRatio: 0.5, minFirst: 220) {
            VStack(spacing: 0) {
                PaneTitle(title: session.inputFileName ?? "Source", trailing: { EmptyView() })
                ZStack {
                    CodeEditor(text: $session.inputText, language: session.inputLanguage, isEditable: true, placeholder: "",
                               error: session.error, config: config, selection: $session.selection,
                               onDrop: { session.load(urls: $0) })
                    if session.inputText.isEmpty {
                        EmptyState(symbol: session.tool.symbol, title: "Paste or type \(session.inputLanguage.displayName) here",
                                   samples: session.tool.samples, onPaste: { session.pasteFromClipboard() },
                                   onSample: { session.useSample($0) })
                    }
                }
            }
        } second: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if let error = session.error { ErrorBanner(error) }
                ZStack {
                    if let document {
                        WebPreview(html: document, javascript: javascript, appearance: appearance, reloadToken: reloadToken)
                    } else {
                        VStack(spacing: Space.sm) {
                            Image(systemName: "safari").font(.system(size: 28, weight: .light)).foregroundStyle(.quaternary)
                            Text("The live preview appears here").font(.callout).foregroundStyle(Palette.subtle)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(Palette.editorBackground)
                Divider()
                HStack(spacing: Space.md) { badges; Spacer(minLength: 0) }
                    .controlSize(.small).font(.caption).lineLimit(1)
                    .padding(.horizontal, Space.md)
                    .frame(height: Layout.statusHeight)
                    .background(Palette.paneTitle)
            }
        }
    }

    var toolbar: some View {
        HStack(spacing: Space.sm) {
            Picker("Appearance", selection: Binding(get: { session.option("appearance").stringValue },
                                                    set: { session.setOption("appearance", .string($0)) })) {
                Image(systemName: "circle.lefthalf.filled").tag("auto").help("Match system")
                Image(systemName: "sun.max").tag("light").help("Light")
                Image(systemName: "moon").tag("dark").help("Dark")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("Preview appearance")
            optionMenu
            Spacer(minLength: Space.sm)
            Button { reloadToken += 1 } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Reload preview").disabled(document == nil)
            Button { if let document { Clipboard.copy(document, toast: "HTML copied") } } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("Copy the full standalone HTML document").disabled(document == nil)
            Button {
                if let document, let data = document.data(using: .utf8) {
                    FilePanels.save(data, suggestedName: exportName, type: .html)
                }
            } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.borderless).help("Save the standalone HTML document").disabled(document == nil)
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .font(.caption)
        .padding(.horizontal, Space.md)
        .frame(height: 32)
        .background(Palette.paneTitle)
    }
}

// MARK: - HTML preview

private struct HTMLPreviewView: View {
    @Bindable var session: ToolSession

    var body: some View {
        let js = session.option("javascript").boolValue
        let external = session.output?.metadata.first { $0.label == "External resources" }
        let base = (session.inputFileName as NSString?)?.deletingPathExtension ?? "preview"
        WebPreviewScreen(session: session, document: session.output?.text, javascript: js,
                         appearance: session.option("appearance").stringValue,
                         exportName: base + ".html") {
            Button { session.setOption("javascript", .bool(!js)) } label: {
                StatusBadge(js ? "JavaScript on" : "JavaScript off", js ? .warning : .success)
            }
            .buttonStyle(.plain)
            .help(js ? "Scripts run in a sandboxed, offline web view. Click to turn off." : "Scripts do not run. Click to allow JavaScript.")
            if let external {
                Label("External resources blocked", systemImage: "network.slash")
                    .foregroundStyle(.secondary)
                    .help(external.value)
            }
        } optionMenu: {
            Menu {
                Toggle("Wrap fragments in <html>", isOn: Binding(get: { session.option("wrapFragment").boolValue },
                                                                set: { session.setOption("wrapFragment", .bool($0)) }))
            } label: { Image(systemName: "slider.horizontal.3") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Preview options")
        }
    }
}

// MARK: - Markdown preview

private struct MarkdownPreviewView: View {
    @Bindable var session: ToolSession
    @State private var assets: WebPreviewAssets.Bundle?
    @Environment(\.colorScheme) private var scheme

    var document: String? {
        guard let out = session.output, let assets else { return nil }
        var o = MarkdownPreviewTool.Options()
        o.mermaid = session.option("mermaid").boolValue
        o.highlight = session.option("highlight").boolValue
        o.appearance = session.option("appearance").stringValue
        let dark = o.appearance == "dark" || (o.appearance == "auto" && scheme == .dark)
        var doc = MarkdownPreviewTool.document(html: out.text, options: o, hljsJS: assets.hljsJS,
                                               hljsCSS: dark ? assets.hljsDark : assets.hljsLight, mermaidJS: assets.mermaidJS)
        // Pin the Mermaid theme to the resolved appearance (matchMedia can't see a forced appearance reliably).
        doc = doc.replacingOccurrences(of: "theme: (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'default'",
                                       with: "theme: '\(dark ? "dark" : "default")'")
        return doc
    }

    var body: some View {
        let words = session.output?.metadata.first { $0.label == "Words" }?.value
        let reading = session.output?.metadata.first { $0.label == "Reading time" }?.value
        let base = (session.inputFileName as NSString?)?.deletingPathExtension ?? "document"
        WebPreviewScreen(session: session, document: document, javascript: true,
                         appearance: session.option("appearance").stringValue,
                         exportName: base + ".html") {
            if let words { Label("\(words) words", systemImage: "textformat.size").foregroundStyle(.secondary) }
            if let reading { Label(reading, systemImage: "clock").foregroundStyle(.secondary) }
        } optionMenu: {
            Menu {
                Toggle("Code highlighting", isOn: Binding(get: { session.option("highlight").boolValue },
                                                         set: { session.setOption("highlight", .bool($0)) }))
                Toggle("Mermaid diagrams", isOn: Binding(get: { session.option("mermaid").boolValue },
                                                        set: { session.setOption("mermaid", .bool($0)) }))
            } label: { Image(systemName: "slider.horizontal.3") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Preview options")
        }
        .task { assets = await WebPreviewAssets.load() }
    }
}

// MARK: - Registration

@MainActor
enum WebPreviewViews {
    static func register() {
        ToolViewRegistry.register(HTMLPreviewTool.id) { AnyView(HTMLPreviewView(session: $0)) }
        ToolViewRegistry.register(MarkdownPreviewTool.id) { AnyView(MarkdownPreviewView(session: $0)) }
    }
}

extension String { func appendingToFile(_ p: String) throws { if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(Data(utf8)); h.closeFile() } else { try write(toFile: p, atomically: false, encoding: .utf8) } } }
