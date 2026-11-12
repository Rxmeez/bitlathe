import Foundation
import BitlatheCore

/// The engine sanitises/normalises; the custom view renders in a sandboxed WKWebView with JavaScript off by default.
public struct HTMLPreviewTool: DevTool {
    public static let id = "html.preview"
    public static let name = "HTML Preview"
    public static let summary = "Render HTML in a sandboxed, offline web view (JavaScript off by default)"
    public static let category = ToolCategory.inspect
    public static let symbol = "safari"
    public static let keywords = ["html", "preview", "render", "browser", "webview", "email"]
    public static let io = ToolIO.text(.html, .html)
    public static let samples = [ToolSample("Card", "<!DOCTYPE html><html><head><style>body{font-family:-apple-system;padding:2rem;background:#f5f5f7}.card{background:#fff;border-radius:12px;padding:1.5rem;box-shadow:0 2px 8px rgba(0,0,0,.08);max-width:420px}h1{margin:0 0 .5rem;font-size:1.4rem}p{color:#555}</style></head><body><div class=\"card\"><h1>Bitlathe</h1><p>Bits in, shape out. This preview runs fully offline.</p><button>Button</button></div></body></html>")]
    public static let optionFields: [OptionField] = [
        .toggle("javascript", "Allow JavaScript", help: "Off by default; scripts run in a sandboxed, offline process"),
        .toggle("wrapFragment", "Wrap fragments", default: true, help: "Add a minimal <html> shell around snippets"),
        .segmented("appearance", "Appearance", [.init("auto", "Auto"), .init("light", "Light"), .init("dark", "Dark")], default: "auto"),
    ]
    public struct Options: ToolOptions {
        public var javascript = false
        public var wrapFragment = true
        public var appearance = "auto"
        public init() {}
    }
    public init() {}

    public static func document(_ html: String, options: Options) -> String {
        var h = html
        if options.wrapFragment, !h.lowercased().contains("<html") {
            h = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><style>body{font-family:-apple-system,system-ui;margin:1rem;line-height:1.5}</style></head><body>\(h)</body></html>"
        }
        if options.appearance != "auto" {
            h = h.replacingOccurrences(of: "<head>", with: "<head><meta name=\"color-scheme\" content=\"\(options.appearance)\"><style>:root{color-scheme:\(options.appearance)}</style>")
        }
        return h
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let doc = Self.document(text, options: options)
        var rows = [MetaRow("Size", ByteFormatter.string(text.utf8.count)), MetaRow("JavaScript", options.javascript ? "Enabled (sandboxed)" : "Disabled", style: options.javascript ? .warning : .success)]
        let scripts = text.matches(of: /<script/).count
        if scripts > 0 { rows.append(MetaRow("Scripts", "\(scripts) <script> tag\(scripts == 1 ? "" : "s")" + (options.javascript ? "" : " (not executed)"))) }
        let external = text.matches(of: /(src|href)=["']https?:/).count
        if external > 0 { rows.append(MetaRow("External resources", "\(external) — not loaded (offline)", style: .muted)) }
        if let t = text.captures("<title>([^<]*)</title>") { rows.append(MetaRow("Title", t[1])) }
        return ToolOutput(text: doc, language: .html, metadata: rows)
    }
}
