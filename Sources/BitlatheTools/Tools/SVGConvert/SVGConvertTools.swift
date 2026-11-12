import Foundation
import BitlatheCore

public struct SVGToCSSTool: DevTool {
    public static let id = "svg.to-css"
    public static let name = "SVG → CSS"
    public static let summary = "Turn SVG into a CSS data URI, background-image or Base64"
    public static let category = ToolCategory.convert
    public static let symbol = "square.on.circle"
    public static let keywords = ["svg", "css", "data uri", "background", "base64", "icon", "convert"]
    public static let io = ToolIO.text(.xml, .css)
    public static let samples = [ToolSample("Icon", "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#333\" stroke-width=\"2\"><circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M8 12l3 3 5-6\"/></svg>")]
    public static let optionFields: [OptionField] = [
        .segmented("encoding", "Encoding", [.init("url", "URL-encoded"), .init("base64", "Base64")], default: "url"),
        .segmented("output", "Output", [.init("background", "background-image"), .init("uri", "Data URI only"), .init("mask", "mask-image")], default: "background"),
        .text("selector", "Selector", placeholder: ".icon", default: ".icon", visibleWhen: ("output", ["background", "mask"])),
    ]
    public struct Options: ToolOptions {
        public var encoding = "url"
        public var output = "background"
        public var selector = ".icon"
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        var svg = input.text.trimmed()
        guard svg.contains("<svg") else { throw ToolError("Input is not an SVG", hint: "Paste markup that starts with <svg") }
        if !svg.contains("xmlns=") { svg = svg.replacingOccurrences(of: "<svg", with: "<svg xmlns=\"http://www.w3.org/2000/svg\"") }
        svg = svg.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        svg = svg.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression).replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        let uri: String
        if options.encoding == "base64" {
            uri = "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
        } else {
            var s = svg.replacingOccurrences(of: "\"", with: "'")
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: " -_.~!*'();:@&=+$,/?[]")
            s = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
            s = s.replacingOccurrences(of: " ", with: "%20")
            uri = "data:image/svg+xml," + s
        }
        let selector = options.selector.isEmpty ? ".icon" : options.selector
        let meta = [MetaRow("SVG size", ByteFormatter.string(svg.utf8.count)), MetaRow("URI size", ByteFormatter.string(uri.utf8.count))]
        switch options.output {
        case "uri": return ToolOutput(text: uri, language: .plain, metadata: meta)
        case "mask":
            return ToolOutput(text: "\(selector) {\n  -webkit-mask-image: url(\"\(uri)\");\n  mask-image: url(\"\(uri)\");\n  mask-size: contain;\n  mask-repeat: no-repeat;\n  background-color: currentColor;\n}", language: .css, metadata: meta)
        default:
            return ToolOutput(text: "\(selector) {\n  background-image: url(\"\(uri)\");\n  background-repeat: no-repeat;\n  background-size: contain;\n}", language: .css, metadata: meta)
        }
    }
    public static func detect(_ s: String) -> DetectionScore? {
        s.hasPrefix("<svg") || (s.hasPrefix("<?xml") && s.contains("<svg")) ? DetectionScore(0.8, "SVG markup") : nil
    }
}

public struct SVGToCodeTool: DevTool {
    public static let id = "svg.to-code"
    public static let name = "SVG → SwiftUI / React"
    public static let summary = "Convert SVG paths to a SwiftUI Shape or a React component"
    public static let category = ToolCategory.convert
    public static let symbol = "scribble.variable"
    public static let keywords = ["svg", "swiftui", "path", "shape", "react", "component", "convert"]
    public static let io = ToolIO.text(.xml, .swift)
    public static let samples = [ToolSample("Check icon", "<svg viewBox=\"0 0 24 24\"><path d=\"M4 12 L9 17 L20 6\" stroke=\"black\" fill=\"none\"/><rect x=\"2\" y=\"2\" width=\"20\" height=\"20\" rx=\"4\"/><circle cx=\"12\" cy=\"12\" r=\"3\"/></svg>")]
    public static let optionFields: [OptionField] = [
        .segmented("target", "Target", [.init("swiftui", "SwiftUI Shape"), .init("react", "React")], default: "swiftui"),
        .text("name", "Name", placeholder: "IconShape", default: "IconShape"),
        .toggle("typescript", "TypeScript", visibleWhen: ("target", ["react"])),
    ]
    public struct Options: ToolOptions {
        public var target = "swiftui"
        public var name = "IconShape"
        public var typescript = false
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard text.contains("<svg") else { throw ToolError("Input is not an SVG") }
        let doc: XMLDocument
        do { doc = try XMLDocument(xmlString: text, options: []) } catch { throw XMLFormatTool.translate(error, text: text) }
        guard let root = doc.rootElement() else { throw ToolError("No <svg> root") }
        let name = options.name.isEmpty ? "IconShape" : options.name
        if options.target == "react" {
            var out = ""
            Self.renderReact(root, into: &out, level: 2)
            let sig = options.typescript ? "export function \(name)(props: React.SVGProps<SVGSVGElement>) {" : "export function \(name)(props) {"
            let body = out.trimmingCharacters(in: .newlines)
            let code = "\(sig)\n  return (\n\(body.replacingOccurrences(of: "<svg", with: "<svg {...props}"))\n  );\n}"
            return ToolOutput(text: code, language: options.typescript ? .typescript : .javascript)
        }
        // SwiftUI
        let viewBox = (root.attribute(forName: "viewBox")?.stringValue ?? "0 0 24 24").split { $0 == " " || $0 == "," }.compactMap { Double($0) }
        let vw = viewBox.count == 4 ? viewBox[2] : 24
        let vh = viewBox.count == 4 ? viewBox[3] : 24
        var lines: [String] = []
        var count = 0
        Self.collectSwift(root, into: &lines, count: &count)
        let body = lines.isEmpty ? "        // No drawable elements found" : lines.joined(separator: "\n")
        let code = """
        import SwiftUI

        /// Generated from SVG (viewBox \(Self.num(vw)) × \(Self.num(vh))). Scales to the proposed rect.
        struct \(name): Shape {
            func path(in rect: CGRect) -> Path {
                let sx = rect.width / \(Self.num(vw))
                let sy = rect.height / \(Self.num(vh))
                var p = Path()
        \(body)
                return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: sx, y: sy))
            }
        }

        #Preview {
            \(name)()
                .stroke(.primary, lineWidth: 2)
                .frame(width: 96, height: 96)
                .padding()
        }
        """
        return ToolOutput(text: code, language: .swift, metadata: [MetaRow("Elements", "\(count)")])
    }

    static func num(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.3f", d).replacingOccurrences(of: "0+$", with: "", options: .regularExpression) }

    static func collectSwift(_ el: XMLElement, into lines: inout [String], count: inout Int) {
        func attr(_ n: String) -> Double? { el.attribute(forName: n)?.stringValue.flatMap(Double.init) }
        switch el.name {
        case "path":
            if let d = el.attribute(forName: "d")?.stringValue {
                count += 1
                lines.append("        // path")
                lines += SVGPathParser.swiftUI(d).map { "        " + $0 }
            }
        case "rect":
            count += 1
            let x = attr("x") ?? 0, y = attr("y") ?? 0, w = attr("width") ?? 0, h = attr("height") ?? 0, rx = attr("rx") ?? attr("ry") ?? 0
            if rx > 0 { lines.append("        p.addRoundedRect(in: CGRect(x: \(num(x)), y: \(num(y)), width: \(num(w)), height: \(num(h))), cornerSize: CGSize(width: \(num(rx)), height: \(num(rx))))") }
            else { lines.append("        p.addRect(CGRect(x: \(num(x)), y: \(num(y)), width: \(num(w)), height: \(num(h))))") }
        case "circle":
            count += 1
            let cx = attr("cx") ?? 0, cy = attr("cy") ?? 0, r = attr("r") ?? 0
            lines.append("        p.addEllipse(in: CGRect(x: \(num(cx - r)), y: \(num(cy - r)), width: \(num(r * 2)), height: \(num(r * 2))))")
        case "ellipse":
            count += 1
            let cx = attr("cx") ?? 0, cy = attr("cy") ?? 0, rx = attr("rx") ?? 0, ry = attr("ry") ?? 0
            lines.append("        p.addEllipse(in: CGRect(x: \(num(cx - rx)), y: \(num(cy - ry)), width: \(num(rx * 2)), height: \(num(ry * 2))))")
        case "line":
            count += 1
            lines.append("        p.move(to: CGPoint(x: \(num(attr("x1") ?? 0)), y: \(num(attr("y1") ?? 0))))")
            lines.append("        p.addLine(to: CGPoint(x: \(num(attr("x2") ?? 0)), y: \(num(attr("y2") ?? 0))))")
        case "polyline", "polygon":
            count += 1
            let pts = (el.attribute(forName: "points")?.stringValue ?? "").split { $0 == " " || $0 == "," || $0 == "\n" }.compactMap { Double($0) }
            var i = 0
            while i + 1 < pts.count {
                lines.append(i == 0 ? "        p.move(to: CGPoint(x: \(num(pts[i])), y: \(num(pts[i + 1]))))" : "        p.addLine(to: CGPoint(x: \(num(pts[i])), y: \(num(pts[i + 1]))))")
                i += 2
            }
            if el.name == "polygon" { lines.append("        p.closeSubpath()") }
        default: break
        }
        for c in el.children ?? [] { if let ce = c as? XMLElement { collectSwift(ce, into: &lines, count: &count) } }
    }

    static func renderReact(_ el: XMLElement, into out: inout String, level: Int) {
        let pad = String(repeating: "  ", count: level)
        var attrs = ""
        for a in el.attributes ?? [] {
            let raw = a.name ?? ""
            if raw.hasPrefix("xmlns:") { continue }
            let name = HTMLToJSXTool.attributeMap[raw.lowercased()] ?? (raw.contains("-") ? TypeModel.camel(raw) : raw)
            if raw == "style" { attrs += " style={{\(HTMLToJSXTool.styleObject(a.stringValue ?? ""))}}"; continue }
            attrs += " \(name)=\"\(a.stringValue ?? "")\""
        }
        let children = (el.children ?? []).compactMap { $0 as? XMLElement }
        if children.isEmpty {
            if let t = el.stringValue?.trimmed(), !t.isEmpty { out += "\(pad)<\(el.name ?? "g")\(attrs)>\(t)</\(el.name ?? "g")>\n" }
            else { out += "\(pad)<\(el.name ?? "g")\(attrs) />\n" }
            return
        }
        out += "\(pad)<\(el.name ?? "g")\(attrs)>\n"
        for c in children { renderReact(c, into: &out, level: level + 1) }
        out += "\(pad)</\(el.name ?? "g")>\n"
    }

    public static func detect(_ s: String) -> DetectionScore? {
        s.hasPrefix("<svg") && s.contains("<path") ? DetectionScore(0.6, "SVG with paths") : nil
    }
}

/// Converts SVG path data to SwiftUI Path calls (absolute coordinates, arcs approximated with Béziers).
enum SVGPathParser {
    static func swiftUI(_ d: String) -> [String] {
        var out: [String] = []
        var tokens: [String] = []
        var current = ""
        for c in d {
            if c.isLetter, c != "e", c != "E" {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(c))
            } else if c == "," || c.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if c == "-", !current.isEmpty, !current.hasSuffix("e"), !current.hasSuffix("E") {
                tokens.append(current); current = "-"
            } else if c == ".", current.contains(".") {
                tokens.append(current); current = "."
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var i = 0
        var cmd = ""
        var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0
        var lastCtrlX = 0.0, lastCtrlY = 0.0
        var lastCmd = ""
        func n() -> Double { defer { i += 1 }; return i < tokens.count ? Double(tokens[i]) ?? 0 : 0 }
        func pt(_ px: Double, _ py: Double) -> String { "CGPoint(x: \(SVGToCodeTool.num(px)), y: \(SVGToCodeTool.num(py)))" }
        while i < tokens.count {
            if let f = tokens[i].first, f.isLetter { cmd = tokens[i]; i += 1 }
            let rel = cmd == cmd.lowercased()
            switch cmd.uppercased() {
            case "M":
                let nx = n(), ny = n()
                x = rel ? x + nx : nx; y = rel ? y + ny : ny
                startX = x; startY = y
                out.append("p.move(to: \(pt(x, y)))")
                cmd = rel ? "l" : "L"
            case "L":
                let nx = n(), ny = n()
                x = rel ? x + nx : nx; y = rel ? y + ny : ny
                out.append("p.addLine(to: \(pt(x, y)))")
            case "H":
                let nx = n()
                x = rel ? x + nx : nx
                out.append("p.addLine(to: \(pt(x, y)))")
            case "V":
                let ny = n()
                y = rel ? y + ny : ny
                out.append("p.addLine(to: \(pt(x, y)))")
            case "C":
                let x1 = n(), y1 = n(), x2 = n(), y2 = n(), nx = n(), ny = n()
                let c1x = rel ? x + x1 : x1, c1y = rel ? y + y1 : y1, c2x = rel ? x + x2 : x2, c2y = rel ? y + y2 : y2
                x = rel ? x + nx : nx; y = rel ? y + ny : ny
                out.append("p.addCurve(to: \(pt(x, y)), control1: \(pt(c1x, c1y)), control2: \(pt(c2x, c2y)))")
                lastCtrlX = c2x; lastCtrlY = c2y
            case "S":
                let x2 = n(), y2 = n(), nx = n(), ny = n()
                let c1x = ["C", "S"].contains(lastCmd.uppercased()) ? 2 * x - lastCtrlX : x
                let c1y = ["C", "S"].contains(lastCmd.uppercased()) ? 2 * y - lastCtrlY : y
                let c2x = rel ? x + x2 : x2, c2y = rel ? y + y2 : y2
                x = rel ? x + nx : nx; y = rel ? y + ny : ny
                out.append("p.addCurve(to: \(pt(x, y)), control1: \(pt(c1x, c1y)), control2: \(pt(c2x, c2y)))")
                lastCtrlX = c2x; lastCtrlY = c2y
            case "Q":
                let x1 = n(), y1 = n(), nx = n(), ny = n()
                let cx = rel ? x + x1 : x1, cy = rel ? y + y1 : y1
                x = rel ? x + nx : nx; y = rel ? y + ny : ny
                out.append("p.addQuadCurve(to: \(pt(x, y)), control: \(pt(cx, cy)))")
                lastCtrlX = cx; lastCtrlY = cy
            case "T":
                let nx = n(), ny = n()
                let cx = ["Q", "T"].contains(lastCmd.uppercased()) ? 2 * x - lastCtrlX : x
                let cy = ["Q", "T"].contains(lastCmd.uppercased()) ? 2 * y - lastCtrlY : y
                x = rel ? x + nx : nx; y = rel ? y + ny : ny
                out.append("p.addQuadCurve(to: \(pt(x, y)), control: \(pt(cx, cy)))")
                lastCtrlX = cx; lastCtrlY = cy
            case "A":
                let rx = n(), ry = n(), rot = n(), large = n(), sweep = n(), nx = n(), ny = n()
                let ex = rel ? x + nx : nx, ey = rel ? y + ny : ny
                for seg in arcToBeziers(x0: x, y0: y, rx: rx, ry: ry, rotation: rot, largeArc: large != 0, sweep: sweep != 0, x: ex, y: ey) {
                    out.append("p.addCurve(to: \(pt(seg.4, seg.5)), control1: \(pt(seg.0, seg.1)), control2: \(pt(seg.2, seg.3)))")
                }
                x = ex; y = ey
            case "Z":
                out.append("p.closeSubpath()")
                x = startX; y = startY
            default:
                i += 1
            }
            lastCmd = cmd
        }
        return out
    }

    /// Standard SVG arc → cubic Bézier conversion (W3C implementation notes F.6.5).
    static func arcToBeziers(x0: Double, y0: Double, rx: Double, ry: Double, rotation: Double, largeArc: Bool, sweep: Bool, x: Double, y: Double) -> [(Double, Double, Double, Double, Double, Double)] {
        if rx == 0 || ry == 0 { return [(x0, y0, x, y, x, y)] }
        var rx = abs(rx), ry = abs(ry)
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (x0 - x) / 2, dy = (y0 - y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let sign: Double = largeArc == sweep ? -1 : 1
        var num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        if num < 0 { num = 0 }
        let coef = sign * sqrt(num / (rx * rx * y1p * y1p + ry * ry * x1p * x1p))
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (x0 + x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (y0 + y) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = Int(ceil(abs(delta) / (.pi / 2)))
        let step = delta / Double(segments)
        var result: [(Double, Double, Double, Double, Double, Double)] = []
        var t = theta1
        for _ in 0..<segments {
            let t2 = t + step
            let alpha = sin(step) * (sqrt(4 + 3 * pow(tan(step / 2), 2)) - 1) / 3
            func point(_ a: Double) -> (Double, Double) {
                let ex = cosPhi * rx * cos(a) - sinPhi * ry * sin(a) + cx
                let ey = sinPhi * rx * cos(a) + cosPhi * ry * sin(a) + cy
                return (ex, ey)
            }
            func deriv(_ a: Double) -> (Double, Double) {
                (-cosPhi * rx * sin(a) - sinPhi * ry * cos(a), -sinPhi * rx * sin(a) + cosPhi * ry * cos(a))
            }
            let p1 = point(t), p2 = point(t2), d1 = deriv(t), d2 = deriv(t2)
            result.append((p1.0 + alpha * d1.0, p1.1 + alpha * d1.1, p2.0 - alpha * d2.0, p2.1 - alpha * d2.1, p2.0, p2.1))
            t = t2
        }
        return result
    }
}
