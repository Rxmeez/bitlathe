import Foundation
import BitlatheCore

public struct SVGOptimizeTool: DevTool {
    public static let id = "svg.optimize"
    public static let name = "SVG Optimiser"
    public static let summary = "Shrink SVGs: strip editor metadata, comments and defaults, round numbers and collapse whitespace"
    public static let category = ToolCategory.media
    public static let symbol = "square.3.layers.3d.down.right"
    public static let keywords = ["svg", "optimise", "optimize", "minify", "svgo", "clean", "inkscape", "sketch", "figma"]
    public static let io = ToolIO.text(.xml, .xml)
    public static let samples = [ToolSample("Exported SVG", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n<!-- Created with Inkscape -->\n<svg xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:inkscape=\"http://www.inkscape.org/namespaces/inkscape\" xmlns=\"http://www.w3.org/2000/svg\" width=\"24.000000mm\" height=\"24mm\" viewBox=\"0 0 24.00000 24\" version=\"1.1\" inkscape:version=\"1.3\">\n  <metadata><rdf:RDF xmlns:rdf=\"x\"><dc:title>icon</dc:title></rdf:RDF></metadata>\n  <g id=\"layer1\" inkscape:label=\"Layer 1\" transform=\"translate(0,0)\">\n    <g></g>\n    <path style=\"fill:#000000;stroke:none;opacity:1\" d=\"M 4.0000,12.000001 L 9.00001,17.0 L 20.000,6.0000\" id=\"path1\" fill=\"black\" stroke-width=\"1.000\" />\n  </g>\n</svg>")]
    public static let optionFields: [OptionField] = [
        .stepper("precision", "Decimals", min: 0, max: 6, default: 2),
        .toggle("removeIDs", "Remove unused ids", default: true),
        .toggle("removeDimensions", "Remove width/height (keep viewBox)"),
        .toggle("pretty", "Pretty print"),
        .toggle("keepTitle", "Keep <title>/<desc>", default: true),
    ]
    public struct Options: ToolOptions {
        public var precision = 2
        public var removeIDs = true
        public var removeDimensions = false
        public var pretty = false
        public var keepTitle = true
        public init() {}
    }
    public init() {}

    static let editorNamespaces = ["inkscape", "sodipodi", "sketch", "figma", "illustrator", "xlink", "rdf", "dc", "cc", "i", "x", "serif", "adobe"]
    static let defaultAttrs: [String: String] = ["fill-opacity": "1", "stroke-opacity": "1", "opacity": "1", "stroke-width": "1", "stroke-linecap": "butt", "stroke-linejoin": "miter", "stroke-miterlimit": "4", "fill-rule": "nonzero", "stroke-dasharray": "none", "stroke": "none", "display": "inline", "overflow": "visible", "font-weight": "normal", "font-style": "normal", "stop-opacity": "1", "clip-rule": "nonzero"]

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard text.contains("<svg") else { throw ToolError("Input is not an SVG") }
        let before = text.utf8.count
        let doc: XMLDocument
        do { doc = try XMLDocument(xmlString: text, options: [.nodePreserveCDATA]) } catch { throw XMLFormatTool.translate(error, text: text) }
        guard let root = doc.rootElement() else { throw ToolError("No <svg> root") }
        var removedNodes = 0, removedAttrs = 0
        var referenced = Set<String>()
        for m in text.matches(of: /url\(#([^)]+)\)|href="#([^"]+)"|xlink:href="#([^"]+)"/) { referenced.insert(String(m.1 ?? m.2 ?? m.3 ?? "")) }
        let fmt = NumberFormatter()
        fmt.minimumFractionDigits = 0
        fmt.maximumFractionDigits = options.precision
        fmt.decimalSeparator = "."
        fmt.usesGroupingSeparator = false
        func roundNumbers(_ s: String) -> String {
            guard let re = try? NSRegularExpression(pattern: "-?\\d*\\.\\d+(?:e-?\\d+)?|-?\\d+\\.?(?:e-?\\d+)?") else { return s }
            let ns = s as NSString
            var out = ""
            var cursor = 0
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                let token = ns.substring(with: m.range)
                if let d = Double(token), let f = fmt.string(from: NSNumber(value: d)) { out += f == "-0" ? "0" : f } else { out += token }
                cursor = NSMaxRange(m.range)
            }
            out += ns.substring(from: cursor)
            return out.replacingOccurrences(of: " -", with: "-").replacingOccurrences(of: ", ", with: ",").replacingOccurrences(of: ",-", with: "-")
        }
        func clean(_ el: XMLElement) {
            for child in el.children ?? [] {
                if child.kind == .comment || child.kind == .processingInstruction { child.detach(); removedNodes += 1; continue }
                if child.kind == .text, (child.stringValue ?? "").trimmed().isEmpty, el.name != "text", el.name != "tspan" { child.detach(); continue }
                guard let ce = child as? XMLElement else { continue }
                let name = ce.name ?? ""
                let prefix = name.split(separator: ":").first.map(String.init) ?? ""
                if name == "metadata" || Self.editorNamespaces.contains(prefix) && name.contains(":") || (!options.keepTitle && (name == "title" || name == "desc")) { ce.detach(); removedNodes += 1; continue }
                clean(ce)
                if name == "g" || name == "defs", (ce.children ?? []).isEmpty, (ce.attributes ?? []).allSatisfy({ ($0.name ?? "") == "id" && !referenced.contains($0.stringValue ?? "") }) { ce.detach(); removedNodes += 1; continue }
            }
            for attr in el.attributes ?? [] {
                let n = attr.name ?? ""
                let v = attr.stringValue ?? ""
                let prefix = n.split(separator: ":").first.map(String.init) ?? ""
                if n.hasPrefix("xmlns:"), Self.editorNamespaces.contains(String(n.dropFirst(6))) { el.removeAttribute(forName: n); removedAttrs += 1; continue }
                if n.contains(":"), Self.editorNamespaces.contains(prefix), prefix != "xlink" { el.removeAttribute(forName: n); removedAttrs += 1; continue }
                if n == "id", options.removeIDs, !referenced.contains(v) { el.removeAttribute(forName: n); removedAttrs += 1; continue }
                if let d = Self.defaultAttrs[n], d == v { el.removeAttribute(forName: n); removedAttrs += 1; continue }
                if n == "version" || n == "baseProfile" || n == "enable-background" || n == "xml:space" { el.removeAttribute(forName: n); removedAttrs += 1; continue }
                if n == "transform", v.replacingOccurrences(of: " ", with: "") == "translate(0,0)" || v == "matrix(1,0,0,1,0,0)" { el.removeAttribute(forName: n); removedAttrs += 1; continue }
                if options.removeDimensions, el === root, n == "width" || n == "height", root.attribute(forName: "viewBox") != nil { el.removeAttribute(forName: n); removedAttrs += 1; continue }
                if n == "style" {
                    // Expand style into attributes, dropping defaults.
                    var kept: [String] = []
                    for decl in v.split(separator: ";") {
                        let kv = decl.split(separator: ":", maxSplits: 1).map { $0.trimmed() }
                        guard kv.count == 2 else { continue }
                        if let d = Self.defaultAttrs[kv[0]], d == kv[1] { removedAttrs += 1; continue }
                        if el.attribute(forName: kv[0]) == nil, kv[0].range(of: "^[a-z-]+$", options: .regularExpression) != nil {
                            let a = XMLNode.attribute(withName: kv[0], stringValue: kv[1]) as! XMLNode   // swiftlint:disable:this force_cast
                            el.addAttribute(a)
                        } else { kept.append("\(kv[0]):\(kv[1])") }
                    }
                    if kept.isEmpty { el.removeAttribute(forName: "style") } else { attr.stringValue = kept.joined(separator: ";") }
                    continue
                }
                if ["d", "points", "viewBox", "x", "y", "width", "height", "cx", "cy", "r", "rx", "ry", "x1", "y1", "x2", "y2", "transform", "stroke-width", "opacity", "offset", "dx", "dy"].contains(n) {
                    var nv = roundNumbers(v)
                    if n == "d" { nv = nv.replacingOccurrences(of: "\\s*([MLHVCSQTAZmlhvcsqtaz])\\s*", with: "$1", options: .regularExpression).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
                    if (n == "width" || n == "height"), nv.hasSuffix("px") { nv.removeLast(2) }
                    attr.stringValue = nv
                }
                if n == "fill" || n == "stroke" || n == "stop-color", v.hasPrefix("#") || v.hasPrefix("rgb"), let parsed = ColorParser.parse(v) {
                    attr.stringValue = Self.shortHex(parsed.0.hex.lowercased())
                }
            }
        }
        clean(root)
        if root.attribute(forName: "xmlns") == nil { root.addAttribute(XMLNode.attribute(withName: "xmlns", stringValue: "http://www.w3.org/2000/svg") as! XMLNode) }   // swiftlint:disable:this force_cast
        var out = root.xmlString(options: options.pretty ? [.nodePrettyPrint, .nodeCompactEmptyElement] : [.nodeCompactEmptyElement])
        if !options.pretty { out = out.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression) }
        let after = out.utf8.count
        let rows = [MetaRow("Size", "\(ByteFormatter.string(before)) → \(ByteFormatter.string(after))"), MetaRow("Saved", String(format: "%.1f%%", Double(before - after) / Double(before) * 100), style: .success),
                    MetaRow("Removed", "\(removedNodes) nodes, \(removedAttrs) attributes")]
        return ToolOutput(.image(Data(out.utf8), .svg), facets: [OutputFacet("SVG source", text: out, language: .xml)], metadata: rows, suggestedFileName: ((input.fileName ?? "icon") as NSString).deletingPathExtension + ".min.svg")
    }

    static func shortHex(_ hex: String) -> String {
        let c = Array(hex)
        guard c.count == 7, c[1] == c[2], c[3] == c[4], c[5] == c[6] else { return hex }
        return "#\(c[1])\(c[3])\(c[5])"
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard s.contains("<svg") else { return nil }
        if s.contains("inkscape") || s.contains("sodipodi") || s.contains("<metadata") || s.contains("sketch:") || s.contains("Generator: Adobe") { return DetectionScore(0.85, "SVG with editor metadata") }
        return DetectionScore(0.55, "SVG")
    }
}
