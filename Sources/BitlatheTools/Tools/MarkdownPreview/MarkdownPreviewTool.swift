import Foundation
import BitlatheCore

public struct MarkdownPreviewTool: DevTool {
    public static let id = "markdown.preview"
    public static let name = "Markdown Preview"
    public static let summary = "GitHub-flavoured Markdown preview with syntax highlighting, task lists, tables and Mermaid diagrams"
    public static let category = ToolCategory.inspect
    public static let symbol = "doc.richtext"
    public static let keywords = ["markdown", "md", "preview", "readme", "gfm", "mermaid", "render"]
    public static let io = ToolIO.text(.markdown, .html)
    public static let samples = [ToolSample("README", "# Bitlathe\n\n> Bits in, shape out.\n\n- [x] 90+ tools\n- [ ] Cloud sync (never)\n\n| Tool | Status |\n|---|---|\n| JSON | ✅ |\n\n```swift\nlet tools = ToolCatalog.all\nprint(tools.count)\n```\n\n```mermaid\ngraph LR\n  Paste --> Detect --> Tool --> Copy\n```\n\nMath-ish: `E = mc^2`. ~~strike~~ **bold** _em_ [link](https://example.com)")]
    public static let optionFields: [OptionField] = [
        .toggle("mermaid", "Mermaid diagrams", default: true),
        .toggle("highlight", "Code highlighting", default: true),
        .segmented("appearance", "Appearance", [.init("auto", "Auto"), .init("light", "Light"), .init("dark", "Dark")], default: "auto"),
    ]
    public struct Options: ToolOptions {
        public var mermaid = true
        public var highlight = true
        public var appearance = "auto"
        public init() {}
    }
    public init() {}

    static let css = """
    :root { color-scheme: light dark; --fg: #1d1d1f; --bg: #ffffff; --muted: #6e6e73; --border: #e5e5ea; --code: #f5f5f7; --accent: #3d7bff; }
    @media (prefers-color-scheme: dark) { :root { --fg: #e6e6e6; --bg: #1e1e22; --muted: #9a9aa0; --border: #3a3a3f; --code: #2a2a2f; --accent: #5b93ff; } }
    html[data-theme=light] { --fg: #1d1d1f; --bg: #ffffff; --muted: #6e6e73; --border: #e5e5ea; --code: #f5f5f7; color-scheme: light; }
    html[data-theme=dark] { --fg: #e6e6e6; --bg: #1e1e22; --muted: #9a9aa0; --border: #3a3a3f; --code: #2a2a2f; color-scheme: dark; }
    body { font: 15px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; color: var(--fg); background: var(--bg); max-width: 820px; margin: 0 auto; padding: 24px 32px; }
    h1, h2, h3, h4 { line-height: 1.25; margin: 1.6em 0 .6em; font-weight: 650; } h1 { font-size: 1.9em; border-bottom: 1px solid var(--border); padding-bottom: .3em; } h2 { font-size: 1.45em; border-bottom: 1px solid var(--border); padding-bottom: .25em; } h3 { font-size: 1.2em; }
    a { color: var(--accent); text-decoration: none; } a:hover { text-decoration: underline; }
    code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .88em; background: var(--code); padding: .15em .35em; border-radius: 5px; }
    pre { background: var(--code); border-radius: 10px; padding: 14px 16px; overflow-x: auto; } pre code { background: none; padding: 0; font-size: .85em; }
    blockquote { border-left: 4px solid var(--border); margin: 1em 0; padding: .2em 1em; color: var(--muted); }
    table { border-collapse: collapse; margin: 1em 0; } th, td { border: 1px solid var(--border); padding: .4em .8em; text-align: left; } th { background: var(--code); }
    img { max-width: 100%; } hr { border: 0; border-top: 1px solid var(--border); margin: 2em 0; }
    ul.contains-task-list { list-style: none; padding-left: .4em; } input[type=checkbox] { margin-right: .5em; }
    .mermaid { background: var(--code); border-radius: 10px; padding: 12px; text-align: center; } kbd { border: 1px solid var(--border); border-bottom-width: 2px; border-radius: 4px; padding: 0 .35em; font-size: .85em; }
    """

    public static func document(html: String, options: Options, hljsJS: String?, hljsCSS: String?, mermaidJS: String?) -> String {
        var head = "<meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><style>\(css)</style>"
        if options.highlight, let hljsCSS { head += "<style>\(hljsCSS)</style>" }
        var scripts = ""
        if options.highlight, let hljsJS { scripts += "<script>\(hljsJS)</script><script>document.querySelectorAll('pre code:not(.language-mermaid)').forEach(function(b){ try { hljs.highlightElement(b); } catch(e){} });</script>" }
        if options.mermaid, let mermaidJS {
            scripts += "<script>\(mermaidJS)</script><script>document.querySelectorAll('pre code.language-mermaid').forEach(function(c){ var d=document.createElement('div'); d.className='mermaid'; d.textContent=c.textContent; c.parentNode.replaceWith(d); }); try { mermaid.initialize({ startOnLoad: true, theme: (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'default', securityLevel: 'strict' }); } catch(e){}</script>"
        }
        let theme = options.appearance == "auto" ? "" : " data-theme=\"\(options.appearance)\""
        return "<!DOCTYPE html><html\(theme)><head>\(head)</head><body class=\"markdown-body\">\(html)\(scripts)</body></html>"
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let html = try await Markdown.render(text)
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        func count(_ pattern: String) -> Int { (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(in: text, range: text.nsRange) ?? 0 }
        let headings = count("(?m)^#{1,6} ")
        let rows = [MetaRow("Words", "\(words)"), MetaRow("Reading time", "\(max(1, words / 220)) min"), MetaRow("Headings", "\(headings)"), MetaRow("Code blocks", "\(count("```") / 2)"), MetaRow("Links", "\(count("\\]\\("))")]
        // The custom view builds the full document with bundled scripts; the engine output is the rendered HTML fragment.
        return ToolOutput(text: html, language: .html, metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard let m = MarkdownHTMLTool.detect(s) else { return nil }
        return DetectionScore(m.confidence + 0.1, "Markdown document")
    }
}
