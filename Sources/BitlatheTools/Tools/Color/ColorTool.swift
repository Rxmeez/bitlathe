import Foundation
import BitlatheCore

public struct ColorTool: DevTool {
    public static let id = "color.convert"
    public static let name = "Colour Converter"
    public static let summary = "HEX, RGB, HSL, HSB, CMYK, OKLCH, Lab and Display P3 with WCAG contrast, palettes and code output"
    public static let category = ToolCategory.inspect
    public static let symbol = "paintpalette"
    public static let keywords = ["color", "colour", "hex", "rgb", "hsl", "hsb", "cmyk", "oklch", "p3", "contrast", "wcag", "palette", "swiftui", "tailwind", "picker", "eyedropper"]
    public static let samples = [ToolSample("Hex", "#3D7BFF"), ToolSample("OKLCH", "oklch(70% 0.15 250)"), ToolSample("Named", "rebeccapurple"), ToolSample("SwiftUI", "Color(red: 0.24, green: 0.48, blue: 1.0)")]
    public static let optionFields: [OptionField] = [
        .text("against", "Contrast vs", placeholder: "#FFFFFF", default: "#FFFFFF", help: "Background colour for the WCAG contrast check"),
        .picker("paletteKind", "Palette", [.init("tints", "Tints & shades"), .init("harmony", "Harmonies"), .init("scale", "Tailwind-style scale")], default: "tints"),
    ]
    public struct Options: ToolOptions {
        public var against = "#FFFFFF"
        public var paletteKind = "tints"
        public init() {}
    }
    public init() {}

    static func f(_ d: Double, _ places: Int = 1) -> String {
        let s = String(format: "%.\(places)f", d)
        return s.contains(".") ? s.replacingOccurrences(of: "0+$", with: "", options: .regularExpression).replacingOccurrences(of: "\\.$", with: "", options: .regularExpression) : s
    }

    public static func formats(_ c: RGBA) -> [(String, String)] {
        let hsl = c.hsl, hsb = c.hsb, cmyk = c.cmyk, ok = c.oklch, lab = c.lab, p3 = c.displayP3
        let a = c.a
        let alphaCSS = a < 1 ? " / \(f(a, 2))" : ""
        var out: [(String, String)] = [
            ("HEX", c.hex),
            ("RGB", a < 1 ? "rgba(\(c.r255), \(c.g255), \(c.b255), \(f(a, 2)))" : "rgb(\(c.r255), \(c.g255), \(c.b255))"),
            ("RGB (modern)", "rgb(\(c.r255) \(c.g255) \(c.b255)\(alphaCSS))"),
            ("HSL", "hsl(\(f(hsl.h)) \(f(hsl.s * 100))% \(f(hsl.l * 100))%\(alphaCSS))"),
            ("HSB / HSV", "hsb(\(f(hsb.h)), \(f(hsb.s * 100))%, \(f(hsb.b * 100))%)"),
            ("HWB", "hwb(\(f(hsb.h)) \(f((1 - hsb.s) * hsb.b * 100))% \(f((1 - hsb.b) * 100))%\(alphaCSS))"),
            ("CMYK", "cmyk(\(f(cmyk.c * 100))%, \(f(cmyk.m * 100))%, \(f(cmyk.y * 100))%, \(f(cmyk.k * 100))%)"),
            ("OKLCH", "oklch(\(f(ok.l * 100))% \(f(ok.c, 3)) \(f(ok.h))\(alphaCSS))"),
            ("OKLab", "oklab(\(f(c.oklab.l * 100))% \(f(c.oklab.a, 3)) \(f(c.oklab.b, 3))\(alphaCSS))"),
            ("CIELAB", "lab(\(f(lab.l)) \(f(lab.a)) \(f(lab.b))\(alphaCSS))"),
            ("Display P3", "color(display-p3 \(f(p3.r, 4)) \(f(p3.g, 4)) \(f(p3.b, 4))\(alphaCSS))"),
            ("sRGB (0–1)", "\(f(c.clamped.r, 4)), \(f(c.clamped.g, 4)), \(f(c.clamped.b, 4))"),
            ("SwiftUI", "Color(red: \(f(c.clamped.r, 3)), green: \(f(c.clamped.g, 3)), blue: \(f(c.clamped.b, 3))\(a < 1 ? ", opacity: \(f(a, 2))" : ""))"),
            ("SwiftUI (hex ext.)", "Color(hex: 0x\(c.hex.dropFirst().prefix(6)))"),
            ("NSColor", "NSColor(srgbRed: \(f(c.clamped.r, 3)), green: \(f(c.clamped.g, 3)), blue: \(f(c.clamped.b, 3)), alpha: \(f(a, 2)))"),
            ("UIColor", "UIColor(red: \(f(c.clamped.r, 3)), green: \(f(c.clamped.g, 3)), blue: \(f(c.clamped.b, 3)), alpha: \(f(a, 2)))"),
            ("Android", "Color(0x\(a < 1 ? String(format: "%02X", Int(a * 255)) : "FF")\(c.hex.dropFirst().prefix(6)))"),
            ("Flutter", "Color(0x\(a < 1 ? String(format: "%02X", Int(a * 255)) : "FF")\(c.hex.dropFirst().prefix(6)))"),
            ("CSS variable", "--color: \(c.hex.lowercased());"),
            ("Tailwind (nearest)", ColorParser.nearestTailwind(c)),
            ("Integer", String(Int(c.r255) << 16 | Int(c.g255) << 8 | Int(c.b255))),
        ]
        let (name, dist) = ColorParser.nearestName(c)
        out.append(("Nearest CSS name", dist < 0.001 ? name : "\(name) (approx.)"))
        return out
    }

    public static func contrastRows(_ c: RGBA, against bg: RGBA) -> [MetaRow] {
        let fg = c.a < 1 ? c.blended(over: bg) : c
        let ratio = fg.contrast(with: bg)
        func grade(_ r: Double, _ aa: Double, _ aaa: Double) -> (String, MetaRow.Style) {
            r >= aaa ? ("AAA", .success) : (r >= aa ? ("AA", .success) : ("Fail", .danger))
        }
        let normal = grade(ratio, 4.5, 7), large = grade(ratio, 3, 4.5), ui = grade(ratio, 3, 3)
        return [
            MetaRow("Contrast vs \(bg.hex)", String(format: "%.2f : 1", ratio), style: ratio >= 4.5 ? .success : (ratio >= 3 ? .warning : .danger)),
            MetaRow("Normal text (AA 4.5, AAA 7)", normal.0, style: normal.1),
            MetaRow("Large text (AA 3, AAA 4.5)", large.0, style: large.1),
            MetaRow("UI components (3)", ui.0, style: ui.1),
            MetaRow("On white", String(format: "%.2f : 1", fg.contrast(with: RGBA(r: 1, g: 1, b: 1))), style: .mono),
            MetaRow("On black", String(format: "%.2f : 1", fg.contrast(with: RGBA(r: 0, g: 0, b: 0))), style: .mono),
            MetaRow("Best text colour", fg.contrast(with: RGBA(r: 1, g: 1, b: 1)) >= fg.contrast(with: RGBA(r: 0, g: 0, b: 0)) ? "White" : "Black"),
        ]
    }

    public static func palette(_ c: RGBA, kind: String) -> [(String, RGBA)] {
        let ok = c.oklch
        switch kind {
        case "harmony":
            func rot(_ d: Double) -> RGBA { RGBA.fromOKLCH(l: ok.l, c: ok.c, h: (ok.h + d).truncatingRemainder(dividingBy: 360), alpha: c.a).clamped }
            return [("Base", c), ("Complementary", rot(180)), ("Analogous −30°", rot(-30)), ("Analogous +30°", rot(30)), ("Triadic +120°", rot(120)), ("Triadic +240°", rot(240)),
                    ("Split −150°", rot(-150)), ("Split +150°", rot(150)), ("Tetradic +90°", rot(90)), ("Tetradic +270°", rot(270))]
        case "scale":
            let stops: [(String, Double)] = [("50", 0.97), ("100", 0.93), ("200", 0.87), ("300", 0.78), ("400", 0.68), ("500", ok.l), ("600", ok.l * 0.85), ("700", ok.l * 0.70), ("800", ok.l * 0.56), ("900", ok.l * 0.44), ("950", ok.l * 0.33)]
            return stops.map { name, l in
                let targetL = name == "500" ? ok.l : l
                let chroma = ok.c * (targetL > ok.l ? max(0.25, 1 - (targetL - ok.l) * 2.2) : max(0.4, 1 - (ok.l - targetL) * 1.2))
                return (name, RGBA.fromOKLCH(l: min(max(targetL, 0.05), 0.99), c: chroma, h: ok.h, alpha: 1).clamped)
            }
        default:
            let white = RGBA(r: 1, g: 1, b: 1), black = RGBA(r: 0, g: 0, b: 0)
            var out: [(String, RGBA)] = []
            for t in stride(from: 0.8, through: 0.2, by: -0.2) { out.append(("Tint \(Int(t * 100))%", c.mixed(with: white, t).clamped)) }
            out.append(("Base", c))
            for t in stride(from: 0.2, through: 0.8, by: 0.2) { out.append(("Shade \(Int(t * 100))%", c.mixed(with: black, t).clamped)) }
            return out
        }
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let lines = text.components(separatedBy: "\n").map { $0.trimmed() }.filter { !$0.isEmpty }
        if lines.count > 1 {
            var out: [String] = []
            var rows: [MetaRow] = []
            for l in lines {
                if let (c, _) = ColorParser.parse(l) { out.append("\(c.hex)  \(Self.formats(c)[1].1)  \(Self.formats(c)[3].1)"); rows.append(MetaRow(l, c.hex, style: .mono)) }
                else { out.append("?  \(l)") }
            }
            return ToolOutput(text: out.joined(separator: "\n"), metadata: rows)
        }
        guard let (color, source) = ColorParser.parse(text) else {
            throw ToolError("Could not parse \"\(text)\" as a colour", hint: "Try #3D7BFF, rgb(61 123 255), hsl(220 100% 62%), oklch(70% 0.15 250), a CSS name or a SwiftUI Color literal")
        }
        var rows = [MetaRow("Parsed as", source)]
        if !color.inGamut { rows.append(MetaRow("Gamut", "Outside sRGB — values clipped for sRGB outputs", style: .warning)) }
        let formats = Self.formats(color)
        rows += formats.map { MetaRow($0.0, $0.1, style: .mono) }
        let bg = ColorParser.parse(options.against)?.0 ?? RGBA(r: 1, g: 1, b: 1)
        rows += Self.contrastRows(color, against: bg)
        let pal = Self.palette(color, kind: options.paletteKind)
        rows.append(MetaRow("── Palette", options.paletteKind, style: .muted))
        rows += pal.map { MetaRow($0.0, $0.1.hex, style: .mono) }
        let facets = formats.map { OutputFacet($0.0, text: $0.1) } + [OutputFacet("Palette (CSS)", text: pal.map { "--\($0.0.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "%", with: "")): \($0.1.hex.lowercased());" }.joined(separator: "\n"), language: .css)]
        return ToolOutput(text: color.hex, facets: facets, metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isSingleLine(s), s.count < 120 else { return nil }
        if s.range(of: "^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$", options: .regularExpression) != nil { return DetectionScore(0.9, "Hex colour") }
        if s.range(of: "^(rgba?|hsla?|hsba?|hwb|oklch|oklab|lab|lch|cmyk|color)\\(", options: [.regularExpression, .caseInsensitive]) != nil, ColorParser.parse(s) != nil { return DetectionScore(0.92, "CSS colour") }
        if s.lowercased().hasPrefix("color(red:") || s.lowercased().hasPrefix("nscolor(") || s.lowercased().hasPrefix("uicolor(") { return DetectionScore(0.85, "Colour literal") }
        if ColorParser.named[s.lowercased()] != nil, s.count > 3 { return DetectionScore(0.5, "CSS colour name") }
        return nil
    }
}
