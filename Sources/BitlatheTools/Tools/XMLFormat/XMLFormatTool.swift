import Foundation
import BitlatheCore

public struct XMLFormatTool: DevTool {
    public static let id = "xml.format"
    public static let name = "XML Formatter"
    public static let summary = "Beautify, minify and validate XML"
    public static let category = ToolCategory.format
    public static let symbol = "chevron.left.slash.chevron.right"
    public static let keywords = ["xml", "beautify", "minify", "validate", "pretty"]
    public static let io = ToolIO.text(.xml, .xml)
    public static let samples = [ToolSample("Feed", "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Bitlathe</title><item><title>Hello</title><link>https://example.com</link></item></channel></rss>")]
    public static let optionFields: [OptionField] = [
        .mode([.init("format", "Beautify"), .init("minify", "Minify"), .init("validate", "Validate")], default: "format"),
        .picker("indent", "Indent", [.init("2", "2 spaces"), .init("4", "4 spaces"), .init("tab", "Tab")], default: "2", visibleWhen: ("mode", ["format"])),
        .toggle("declaration", "XML declaration", default: true, visibleWhen: ("mode", ["format"])),
    ]
    public struct Options: ToolOptions {
        public var mode = "format"
        public var indent = "2"
        public var declaration = true
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let doc: XMLDocument
        do {
            doc = try XMLDocument(xmlString: text, options: [.nodePreserveCDATA, .nodePreserveWhitespace])
        } catch {
            throw Self.translate(error, text: text)
        }
        let rootName = doc.rootElement()?.name ?? "?"
        let meta = [MetaRow("Root", rootName), MetaRow("Elements", "\(Self.count(doc.rootElement()))")]
        switch options.mode {
        case "validate":
            return ToolOutput(text: text, language: .xml, metadata: meta, isValid: true)
        case "minify":
            var opts: XMLNode.Options = [.nodeCompactEmptyElement]
            _ = opts.insert(.nodePreserveCDATA)
            Self.stripWhitespace(doc.rootElement())
            var out = doc.xmlString(options: opts)
            out = out.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)
            if !options.declaration, out.hasPrefix("<?xml") { out = String(out.drop { $0 != ">" }.dropFirst()).trimmed() }
            return ToolOutput(text: out, language: .xml, metadata: meta, isValid: true)
        default:
            Self.stripWhitespace(doc.rootElement())
            var out = doc.xmlString(options: [.nodePrettyPrint, .nodeCompactEmptyElement, .nodePreserveCDATA])
            if options.indent != "4" {
                let unit = options.indent == "tab" ? "\t" : "  "
                out = out.components(separatedBy: "\n").map { line -> String in
                    let lead = line.prefix { $0 == " " }.count
                    return String(repeating: unit, count: lead / 4) + line.dropFirst(lead)
                }.joined(separator: "\n")
            }
            if !options.declaration, out.hasPrefix("<?xml"), let nl = out.firstIndex(of: "\n") { out = String(out[out.index(after: nl)...]) }
            return ToolOutput(text: out, language: .xml, metadata: meta, isValid: true)
        }
    }

    static func stripWhitespace(_ node: XMLNode?) {
        guard let el = node as? XMLElement else { return }
        for child in el.children ?? [] {
            if child.kind == .text, child.stringValue?.trimmed().isEmpty == true, (el.children?.count ?? 0) > 1 {
                child.detach()
            } else {
                stripWhitespace(child)
            }
        }
    }

    static func count(_ node: XMLNode?) -> Int {
        guard let el = node as? XMLElement else { return 0 }
        return 1 + (el.children ?? []).reduce(0) { $0 + count($1) }
    }

    static func translate(_ error: any Error, text: String) -> ToolError {
        let ns = error as NSError
        var msg = (ns.userInfo[NSLocalizedDescriptionKey] as? String) ?? "Invalid XML"
        var line: Int?
        var col: Int?
        if let r = msg.range(of: "line (\\d+)", options: .regularExpression) {
            line = Int(msg[r].split(separator: " ").last ?? "")
        }
        if let r = msg.range(of: "column (\\d+)", options: .regularExpression) {
            col = Int(msg[r].split(separator: " ").last ?? "")
        }
        msg = msg.replacingOccurrences(of: "Line \\d+: ", with: "", options: .regularExpression).trimmed()
        if let first = msg.split(separator: Character("\n")).first { msg = String(first) }
        if line == nil, let first = msg.split(separator: ":").first, let n = Int(first) { line = n }
        return ToolError(msg.isEmpty ? "Invalid XML" : msg, line: line, column: col)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.hasPrefix("<?xml") { return DetectionScore(0.95, "XML declaration") }
        if s.hasPrefix("<"), s.hasSuffix(">"), s.range(of: "</[A-Za-z][\\w:.-]*>\\s*$", options: .regularExpression) != nil,
           s.lowercased().range(of: "<(html|body|div|span|p|a)\\b", options: .regularExpression) == nil {
            return DetectionScore(0.7, "XML markup")
        }
        return nil
    }
}
