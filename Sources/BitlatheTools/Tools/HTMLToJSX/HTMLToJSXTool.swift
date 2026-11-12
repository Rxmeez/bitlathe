import Foundation
import BitlatheCore

public struct HTMLToJSXTool: DevTool {
    public static let id = "html.to-jsx"
    public static let name = "HTML → JSX"
    public static let summary = "Convert HTML to React JSX (className, htmlFor, style objects, self-closing tags)"
    public static let category = ToolCategory.convert
    public static let symbol = "atom"
    public static let keywords = ["html", "jsx", "react", "tsx", "convert", "component"]
    public static let io = ToolIO.text(.html, .javascript)
    public static let samples = [ToolSample("Form", "<div class=\"card\" style=\"color: red; margin-top: 4px\"><label for=\"name\">Name</label><input type=\"text\" id=\"name\" tabindex=\"0\" disabled><br><!-- note --><p>Hi &amp; bye</p></div>")]
    public static let optionFields: [OptionField] = [
        .toggle("component", "Wrap in component", default: true),
        .text("name", "Component", placeholder: "Component", default: "Component", visibleWhen: ("component", ["true"])),
        .toggle("typescript", "TypeScript", visibleWhen: ("component", ["true"])),
    ]
    public struct Options: ToolOptions {
        public var component = true
        public var name = "Component"
        public var typescript = false
        public init() {}
    }
    public init() {}

    static let attributeMap: [String: String] = [
        "class": "className", "for": "htmlFor", "tabindex": "tabIndex", "readonly": "readOnly", "maxlength": "maxLength", "minlength": "minLength",
        "colspan": "colSpan", "rowspan": "rowSpan", "cellpadding": "cellPadding", "cellspacing": "cellSpacing", "autocomplete": "autoComplete",
        "autofocus": "autoFocus", "autoplay": "autoPlay", "enctype": "encType", "formaction": "formAction", "frameborder": "frameBorder",
        "novalidate": "noValidate", "srcset": "srcSet", "crossorigin": "crossOrigin", "datetime": "dateTime", "accesskey": "accessKey",
        "contenteditable": "contentEditable", "spellcheck": "spellCheck", "allowfullscreen": "allowFullScreen", "charset": "charSet",
        "http-equiv": "httpEquiv", "accept-charset": "acceptCharset", "viewbox": "viewBox", "stroke-width": "strokeWidth", "stroke-linecap": "strokeLinecap",
        "stroke-linejoin": "strokeLinejoin", "fill-rule": "fillRule", "clip-rule": "clipRule", "fill-opacity": "fillOpacity", "stroke-opacity": "strokeOpacity",
        "font-size": "fontSize", "font-family": "fontFamily", "text-anchor": "textAnchor", "xlink:href": "xlinkHref", "xml:lang": "xmlLang", "xmlns:xlink": "xmlnsXlink",
        "stop-color": "stopColor", "stop-opacity": "stopOpacity", "dominant-baseline": "dominantBaseline", "alignment-baseline": "alignmentBaseline",
    ]
    static let booleanAttrs: Set<String> = ["disabled", "checked", "selected", "readonly", "required", "autofocus", "multiple", "hidden", "autoplay", "controls", "loop", "muted", "open", "novalidate", "defer", "async"]
    static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let doc: XMLDocument
        do { doc = try XMLDocument(xmlString: "<root>" + text + "</root>", options: [.documentTidyHTML, .nodePreserveWhitespace]) } catch {
            doc = try XMLDocument(data: Data(text.utf8), options: [.documentTidyHTML])
        }
        let container = Self.findContent(doc.rootElement()) ?? doc.rootElement()
        let nodes = container?.children ?? []
        var out = ""
        for n in nodes { Self.render(n, into: &out, level: options.component ? 2 : 0) }
        var jsx = out.trimmingCharacters(in: .newlines)
        let topLevel = nodes.filter { $0.kind == .element || !($0.stringValue ?? "").trimmed().isEmpty }.count
        if topLevel > 1 {
            jsx = "<>\n" + jsx.indented(by: "  ") + "\n</>"
            if options.component { jsx = jsx.indented(by: "    ") }
        }
        if options.component {
            let name = options.name.isEmpty ? "Component" : options.name
            let sig = options.typescript ? "export function \(name)(): JSX.Element {" : "export function \(name)() {"
            jsx = "\(sig)\n  return (\n\(topLevel > 1 ? jsx : jsx)\n  );\n}"
        }
        return ToolOutput(text: jsx, language: options.typescript ? .typescript : .javascript)
    }

    /// Tidy wraps fragments in html/body; dig down to the original content.
    static func findContent(_ el: XMLElement?) -> XMLElement? {
        guard let el else { return nil }
        if el.name == "root" { return el }
        for c in el.children ?? [] {
            if let ce = c as? XMLElement, let found = findContent(ce) { return found }
        }
        if el.name == "body" { return el }
        return nil
    }

    static func render(_ node: XMLNode, into out: inout String, level: Int) {
        let pad = String(repeating: "  ", count: level)
        switch node.kind {
        case .text:
            let t = node.stringValue ?? ""
            let trimmed = t.trimmed()
            guard !trimmed.isEmpty else { return }
            var s = trimmed.replacingOccurrences(of: "{", with: "{'{'}").replacingOccurrences(of: "}", with: "{'}'}")
            s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            out += pad + s + "\n"
        case .comment:
            out += pad + "{/* " + (node.stringValue ?? "").trimmed() + " */}\n"
        case .element:
            guard let el = node as? XMLElement, var name = el.name else { return }
            if name.contains(":") {
                let parts: [String] = name.split(separator: ":").map { String($0) }
                name = parts.enumerated().map { (i: Int, p: String) -> String in i == 0 ? p : p.capitalizedFirst() }.joined()
            }
            var attrs = ""
            for a in el.attributes ?? [] {
                let raw = (a.name ?? "").lowercased()
                let value = a.stringValue ?? ""
                if raw == "style" {
                    attrs += " style={{" + styleObject(value) + "}}"
                    continue
                }
                var jsxName = attributeMap[raw] ?? (a.name ?? "")
                if raw.hasPrefix("on"), raw.count > 2 { jsxName = "on" + raw.dropFirst(2).capitalizedFirst() }
                if raw.hasPrefix("data-") || raw.hasPrefix("aria-") { jsxName = raw }
                if booleanAttrs.contains(raw), value.isEmpty || value == raw { attrs += " \(jsxName)"; continue }
                if raw == "value", el.name == "input" || el.name == "select" || el.name == "textarea" { attrs += " defaultValue=\"\(value)\""; continue }
                if raw == "checked" { attrs += " defaultChecked"; continue }
                attrs += value.contains("\"") ? " \(jsxName)={\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\"}" : " \(jsxName)=\"\(value)\""
            }
            let children = el.children ?? []
            let meaningful = children.filter { $0.kind == .element || $0.kind == .comment || !($0.stringValue ?? "").trimmed().isEmpty }
            if meaningful.isEmpty || voidTags.contains(name) {
                out += pad + "<\(name)\(attrs) />\n"
                return
            }
            if meaningful.count == 1, meaningful[0].kind == .text {
                let raw: String = (meaningful[0].stringValue ?? "").trimmed()
                let collapsed = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                let t = collapsed.replacingOccurrences(of: "{", with: "{'{'}").replacingOccurrences(of: "}", with: "{'}'}")
                out += pad + "<\(name)\(attrs)>\(t)</\(name)>\n"
                return
            }
            out += pad + "<\(name)\(attrs)>\n"
            for c in meaningful { render(c, into: &out, level: level + 1) }
            out += pad + "</\(name)>\n"
        default:
            break
        }
    }

    static func styleObject(_ css: String) -> String {
        css.split(separator: ";").compactMap { decl -> String? in
            let kv = decl.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { return nil }
            let prop = kv[0].trimmed()
            let val = kv[1].trimmed()
            let name = prop.hasPrefix("--") ? "'\(prop)'" : TypeModel.camel(prop)
            if let n = Double(val) { return "\(name): \(n == n.rounded() ? String(Int(n)) : val)" }
            return "\(name): '\(val.replacingOccurrences(of: "'", with: "\\'"))'"
        }.joined(separator: ", ")
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard let h = HTMLFormatTool.detect(s), h.confidence >= 0.8, !s.lowercased().hasPrefix("<!doctype"), !s.lowercased().hasPrefix("<html") else { return nil }
        return DetectionScore(0.5, "HTML snippet → JSX")
    }
}
