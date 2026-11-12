import Foundation
import BitlatheCore

public struct MarkdownHTMLTool: DevTool {
    public static let id = "convert.markdown-html"
    public static let name = "Markdown ⇄ HTML"
    public static let summary = "Render GitHub-flavoured Markdown to HTML, or turn HTML back into Markdown"
    public static let category = ToolCategory.convert
    public static let symbol = "text.badge.checkmark"
    public static let keywords = ["markdown", "md", "html", "gfm", "convert", "render"]
    public static let io = ToolIO.text(.markdown, .html)
    public static let samples = [ToolSample("Markdown", "# Bitlathe\n\nA **native** toolbox.\n\n- [x] Fast\n- [ ] Cloud\n\n| Tool | Status |\n|------|--------|\n| JSON | ✅ |\n\n```swift\nlet x = 1\n```"),
                                 ToolSample("HTML", "<h2>Title</h2><p>Some <em>emphasis</em> and a <a href=\"https://example.com\">link</a>.</p><ul><li>one</li><li>two</li></ul><pre><code>let x = 1</code></pre>", options: ["direction": .string("html2md")])]
    public static let optionFields: [OptionField] = [
        .segmented("direction", "Direction", [.init("auto", "Auto"), .init("md2html", "Markdown → HTML"), .init("html2md", "HTML → Markdown")], default: "auto"),
        .toggle("fullDocument", "Full document", help: "Wrap in <html> with basic styles", visibleWhen: ("direction", ["auto", "md2html"])),
    ]
    public struct Options: ToolOptions {
        public var direction = "auto"
        public var fullDocument = false
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let toHTML: Bool = switch options.direction {
        case "md2html": true
        case "html2md": false
        default: !(text.trimmed().hasPrefix("<") && text.contains("</"))
        }
        if toHTML {
            var html = try await Markdown.render(text)
            if options.fullDocument { html = Markdown.wrapDocument(html) }
            return ToolOutput(text: html, language: .html)
        }
        return ToolOutput(text: HTMLToMarkdown.convert(text), language: .markdown)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard s.contains("\n"), !s.hasPrefix("<"), !s.hasPrefix("{") else { return nil }
        var hits = 0
        if s.range(of: "(?m)^#{1,6} ", options: .regularExpression) != nil { hits += 2 }
        if s.range(of: "(?m)^\\s*[-*+] ", options: .regularExpression) != nil { hits += 1 }
        if s.range(of: "\\*\\*[^*]+\\*\\*|`[^`]+`|\\[[^\\]]+\\]\\([^)]+\\)", options: .regularExpression) != nil { hits += 1 }
        if s.contains("```") { hits += 2 }
        if s.range(of: "(?m)^\\|.*\\|$", options: .regularExpression) != nil { hits += 1 }
        return hits >= 2 ? DetectionScore(0.6, "Markdown") : nil
    }
}

public enum Markdown {
    /// GitHub-flavoured Markdown → HTML via the bundled `marked`.
    public static func render(_ md: String) async throws -> String {
        try await JSRuntime.shared.evaluate("""
        marked.use({ gfm: true, breaks: false });
        return marked.parse(__source);
        """, in: JSBundles.marked, arguments: ["__source": md])
    }

    public static func wrapDocument(_ body: String, title: String = "Document") -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
          body { font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; max-width: 760px; margin: 2rem auto; padding: 0 1rem; color: #1d1d1f; }
          pre { background: #f5f5f7; padding: 1rem; border-radius: 8px; overflow-x: auto; }
          code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em; }
          table { border-collapse: collapse; } th, td { border: 1px solid #ddd; padding: 0.4rem 0.8rem; }
          blockquote { border-left: 4px solid #ddd; margin: 0; padding-left: 1rem; color: #555; }
          @media (prefers-color-scheme: dark) { body { background: #1e1e1e; color: #e6e6e6; } pre { background: #2a2a2a; } th, td { border-color: #444; } }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}

/// HTML → Markdown using Foundation's HTML tidy parser.
public enum HTMLToMarkdown {
    public static func convert(_ html: String) -> String {
        guard let doc = try? XMLDocument(data: Data(html.utf8), options: [.documentTidyHTML]) else { return html }
        var out = ""
        if let body = HTMLToJSXTool.findContent(doc.rootElement()) ?? doc.rootElement() {
            for c in body.children ?? [] { render(c, into: &out, listDepth: 0, ordered: false, index: 0) }
        }
        return out.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression).trimmed()
    }

    static func inline(_ node: XMLNode) -> String {
        switch node.kind {
        case .text:
            return (node.stringValue ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        case .element:
            guard let el = node as? XMLElement else { return "" }
            let inner = (el.children ?? []).map(inline).joined()
            switch el.name {
            case "strong", "b": return "**\(inner.trimmed())**"
            case "em", "i": return "*\(inner.trimmed())*"
            case "code": return "`\(inner)`"
            case "a": return "[\(inner.trimmed())](\(el.attribute(forName: "href")?.stringValue ?? ""))"
            case "img": return "![\(el.attribute(forName: "alt")?.stringValue ?? "")](\(el.attribute(forName: "src")?.stringValue ?? ""))"
            case "br": return "  \n"
            case "del", "s", "strike": return "~~\(inner.trimmed())~~"
            case "span", "u", "small", "sup", "sub", "mark", "abbr", "kbd": return inner
            default: return inner
            }
        default: return ""
        }
    }

    static func render(_ node: XMLNode, into out: inout String, listDepth: Int, ordered: Bool, index: Int) {
        guard node.kind == .element, let el = node as? XMLElement else {
            let t = inline(node)
            if !t.trimmed().isEmpty { out += t }
            return
        }
        let name = el.name ?? ""
        let children = el.children ?? []
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(name.last!)) ?? 1   // swiftlint:disable:this force_unwrapping
            out += "\n\n" + String(repeating: "#", count: level) + " " + children.map(inline).joined().trimmed() + "\n\n"
        case "p":
            out += "\n\n" + children.map(inline).joined().trimmed() + "\n\n"
        case "br": out += "  \n"
        case "hr": out += "\n\n---\n\n"
        case "blockquote":
            var inner = ""
            for c in children { render(c, into: &inner, listDepth: listDepth, ordered: false, index: 0) }
            out += "\n\n" + inner.trimmed().split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n") + "\n\n"
        case "pre":
            let code = (children.first(where: { ($0 as? XMLElement)?.name == "code" }) ?? el)
            let lang = (code as? XMLElement)?.attribute(forName: "class")?.stringValue?.replacingOccurrences(of: "language-", with: "").split(separator: " ").first.map(String.init) ?? ""
            out += "\n\n```\(lang)\n" + (code.stringValue ?? "").trimmingCharacters(in: .newlines) + "\n```\n\n"
        case "ul", "ol":
            out += listDepth == 0 ? "\n\n" : "\n"
            var i = 0
            for c in children where (c as? XMLElement)?.name == "li" {
                i += 1
                render(c, into: &out, listDepth: listDepth + 1, ordered: name == "ol", index: i)
            }
            out += listDepth == 0 ? "\n" : ""
        case "li":
            let pad = String(repeating: "  ", count: max(0, listDepth - 1))
            var marker = ordered ? "\(index). " : "- "
            if let input = children.compactMap({ $0 as? XMLElement }).first(where: { $0.name == "input" }) {
                marker += input.attribute(forName: "checked") != nil ? "[x] " : "[ ] "
            }
            var text = ""
            var nested = ""
            for c in children {
                if let ce = c as? XMLElement, ce.name == "ul" || ce.name == "ol" { render(ce, into: &nested, listDepth: listDepth, ordered: false, index: 0) }
                else if let ce = c as? XMLElement, ce.name == "p" { text += children.count > 1 ? inline(ce) + " " : inline(ce) }
                else if let ce = c as? XMLElement, ce.name == "input" { continue }
                else { text += inline(c) }
            }
            out += pad + marker + text.trimmed() + "\n" + nested
        case "table":
            var rows: [[String]] = []
            func collect(_ n: XMLNode) {
                if let e = n as? XMLElement {
                    if e.name == "tr" { rows.append((e.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.name == "td" || $0.name == "th" }.map { ($0.children ?? []).map(inline).joined().trimmed() }) }
                    else { for c in e.children ?? [] { collect(c) } }
                }
            }
            collect(el)
            guard let header = rows.first else { return }
            out += "\n\n| " + header.joined(separator: " | ") + " |\n|" + header.map { _ in "---|" }.joined() + "\n"
            for r in rows.dropFirst() { out += "| " + r.joined(separator: " | ") + " |\n" }
            out += "\n"
        case "div", "section", "article", "main", "body", "html", "header", "footer", "nav", "aside", "figure", "details", "summary", "root":
            for c in children { render(c, into: &out, listDepth: listDepth, ordered: false, index: 0) }
        case "script", "style", "head", "meta", "link", "title":
            break
        default:
            out += inline(el)
        }
    }
}
