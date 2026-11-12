import Foundation
import BitlatheCore

/// JSON ⇄ XML conversion with the conventional `@attr` / `#text` mapping.
enum XMLJSON {
    static func toJSON(_ text: String, attributesPrefix: String = "@", textKey: String = "#text") throws -> JSONValue {
        let doc: XMLDocument
        do { doc = try XMLDocument(xmlString: text, options: [.nodePreserveCDATA]) } catch { throw XMLFormatTool.translate(error, text: text) }
        guard let root = doc.rootElement() else { throw ToolError("XML has no root element") }
        return .object([(key: root.name ?? "root", value: convert(root, attributesPrefix: attributesPrefix, textKey: textKey))])
    }

    static func convert(_ el: XMLElement, attributesPrefix: String, textKey: String) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = []
        for a in el.attributes ?? [] { pairs.append((key: attributesPrefix + (a.name ?? ""), value: typed(a.stringValue ?? ""))) }
        var text = ""
        var childGroups: [(key: String, value: JSONValue)] = []
        for child in el.children ?? [] {
            if let ce = child as? XMLElement {
                let v = convert(ce, attributesPrefix: attributesPrefix, textKey: textKey)
                let name = ce.name ?? "item"
                if let idx = childGroups.firstIndex(where: { $0.key == name }) {
                    if case .array(var arr) = childGroups[idx].value { arr.append(v); childGroups[idx].value = .array(arr) }
                    else { childGroups[idx].value = .array([childGroups[idx].value, v]) }
                } else {
                    childGroups.append((key: name, value: v))
                }
            } else if child.kind == .text || child.kind == .comment {
                if child.kind == .text { text += child.stringValue ?? "" }
            }
        }
        let trimmed = text.trimmed()
        if pairs.isEmpty && childGroups.isEmpty { return typed(trimmed) }
        pairs += childGroups
        if !trimmed.isEmpty { pairs.append((key: textKey, value: typed(trimmed))) }
        return .object(pairs)
    }

    static func typed(_ s: String) -> JSONValue {
        if s.isEmpty { return .string("") }
        if s == "true" { return .bool(true) }
        if s == "false" { return .bool(false) }
        if s.range(of: "^-?(0|[1-9]\\d*)(\\.\\d+)?$", options: .regularExpression) != nil, s.count < 16 { return .number(s) }
        return .string(s)
    }

    static func toXML(_ v: JSONValue, rootName: String = "root", attributesPrefix: String = "@", textKey: String = "#text", indent: Int = 2, declaration: Bool = true) -> String {
        var out = declaration ? "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" : ""
        if case .object(let o) = v, o.count == 1, case .object = o[0].value {
            write(o[0].value, name: o[0].key, level: 0, into: &out, attributesPrefix: attributesPrefix, textKey: textKey, indent: indent)
        } else {
            write(v, name: rootName, level: 0, into: &out, attributesPrefix: attributesPrefix, textKey: textKey, indent: indent)
        }
        if out.hasSuffix("\n") { out.removeLast() }
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func safeName(_ s: String) -> String {
        var n = s.replacingOccurrences(of: "[^A-Za-z0-9_.:-]", with: "_", options: .regularExpression)
        if n.isEmpty || !(n.first!.isLetter || n.first == "_") { n = "_" + n }   // swiftlint:disable:this force_unwrapping
        return n
    }

    private static func write(_ v: JSONValue, name: String, level: Int, into out: inout String, attributesPrefix: String, textKey: String, indent: Int) {
        let pad = String(repeating: " ", count: level * indent)
        let tag = safeName(name)
        switch v {
        case .array(let a):
            for item in a { write(item, name: name, level: level, into: &out, attributesPrefix: attributesPrefix, textKey: textKey, indent: indent) }
        case .object(let o):
            var attrs = ""
            var text: String?
            var children: [(key: String, value: JSONValue)] = []
            for (k, val) in o {
                if k.hasPrefix(attributesPrefix), !attributesPrefix.isEmpty { attrs += " \(safeName(String(k.dropFirst(attributesPrefix.count))))=\"\(escape(scalar(val)))\"" }
                else if k == textKey { text = scalar(val) }
                else { children.append((key: k, value: val)) }
            }
            if children.isEmpty {
                if let text { out += "\(pad)<\(tag)\(attrs)>\(escape(text))</\(tag)>\n" }
                else { out += "\(pad)<\(tag)\(attrs)/>\n" }
            } else {
                out += "\(pad)<\(tag)\(attrs)>\n"
                if let text { out += "\(pad)\(String(repeating: " ", count: indent))\(escape(text))\n" }
                for (k, val) in children { write(val, name: k, level: level + 1, into: &out, attributesPrefix: attributesPrefix, textKey: textKey, indent: indent) }
                out += "\(pad)</\(tag)>\n"
            }
        default:
            out += "\(pad)<\(tag)>\(escape(scalar(v)))</\(tag)>\n"
        }
    }

    static func scalar(_ v: JSONValue) -> String {
        switch v {
        case .null: ""
        case .bool(let b): b ? "true" : "false"
        case .number(let s): s
        case .string(let s): s
        default: JSONSerializer.string(v, options: .minified)
        }
    }
}
