import Foundation
import BitlatheCore

/// sRGB-centred colour model with conversions to HSL, HSB, CMYK, OKLab/OKLCH, CIELAB and Display P3.
public struct RGBA: Sendable, Equatable {
    public var r: Double, g: Double, b: Double, a: Double   // 0…1, sRGB (may exceed gamut)
    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    public var clamped: RGBA { RGBA(r: min(max(r, 0), 1), g: min(max(g, 0), 1), b: min(max(b, 0), 1), a: min(max(a, 0), 1)) }
    public var inGamut: Bool { (-0.0005...1.0005).contains(r) && (-0.0005...1.0005).contains(g) && (-0.0005...1.0005).contains(b) }

    public var hex: String {
        let c = clamped
        let base = String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
        return a < 1 ? base + String(format: "%02X", Int((c.a * 255).rounded())) : base
    }
    public var r255: Int { Int((clamped.r * 255).rounded()) }
    public var g255: Int { Int((clamped.g * 255).rounded()) }
    public var b255: Int { Int((clamped.b * 255).rounded()) }

    // MARK: HSL / HSB
    public var hsl: (h: Double, s: Double, l: Double) {
        let c = clamped
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        return (hue(c, mx, d), s, l)
    }
    public var hsb: (h: Double, s: Double, b: Double) {
        let c = clamped
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let d = mx - mn
        return (d == 0 ? 0 : hue(c, mx, d), mx == 0 ? 0 : d / mx, mx)
    }
    private func hue(_ c: RGBA, _ mx: Double, _ d: Double) -> Double {
        var h: Double
        if mx == c.r { h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0) }
        else if mx == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }
    public static func fromHSL(h: Double, s: Double, l: Double, a: Double = 1) -> RGBA {
        let hh = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360
        func f(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        if s == 0 { return RGBA(r: l, g: l, b: l, a: a) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return RGBA(r: f(p, q, hh + 1 / 3), g: f(p, q, hh), b: f(p, q, hh - 1 / 3), a: a)
    }
    public static func fromHSB(h: Double, s: Double, b: Double, a: Double = 1) -> RGBA {
        let hh = (((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)) / 60
        let i = Int(floor(hh)) % 6
        let f = hh - floor(hh)
        let p = b * (1 - s), q = b * (1 - f * s), t = b * (1 - (1 - f) * s)
        switch i {
        case 0: return RGBA(r: b, g: t, b: p, a: a)
        case 1: return RGBA(r: q, g: b, b: p, a: a)
        case 2: return RGBA(r: p, g: b, b: t, a: a)
        case 3: return RGBA(r: p, g: q, b: b, a: a)
        case 4: return RGBA(r: t, g: p, b: b, a: a)
        default: return RGBA(r: b, g: p, b: q, a: a)
        }
    }

    // MARK: CMYK
    public var cmyk: (c: Double, m: Double, y: Double, k: Double) {
        let c = clamped
        let k = 1 - max(c.r, c.g, c.b)
        if k >= 1 { return (0, 0, 0, 1) }
        return ((1 - c.r - k) / (1 - k), (1 - c.g - k) / (1 - k), (1 - c.b - k) / (1 - k), k)
    }
    public static func fromCMYK(c: Double, m: Double, y: Double, k: Double, a: Double = 1) -> RGBA {
        RGBA(r: (1 - c) * (1 - k), g: (1 - m) * (1 - k), b: (1 - y) * (1 - k), a: a)
    }

    // MARK: Linear / XYZ / OKLab / Lab
    static func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func fromLinear(_ c: Double) -> Double { c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }
    public var linear: (r: Double, g: Double, b: Double) { (Self.toLinear(r), Self.toLinear(g), Self.toLinear(b)) }
    public var luminance: Double { let l = clamped.linear; return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b }

    public var xyz: (x: Double, y: Double, z: Double) {
        let l = linear
        return (0.4124564 * l.r + 0.3575761 * l.g + 0.1804375 * l.b, 0.2126729 * l.r + 0.7151522 * l.g + 0.0721750 * l.b, 0.0193339 * l.r + 0.1191920 * l.g + 0.9503041 * l.b)
    }
    public static func fromXYZ(_ x: Double, _ y: Double, _ z: Double, a: Double = 1) -> RGBA {
        let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        return RGBA(r: fromLinear(r), g: fromLinear(g), b: fromLinear(b), a: a)
    }

    public var oklab: (l: Double, a: Double, b: Double) {
        let c = linear
        let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
        let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
        let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_, 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_, 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }
    public static func fromOKLab(l: Double, a: Double, b: Double, alpha: Double = 1) -> RGBA {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bb = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        return RGBA(r: fromLinear(r), g: fromLinear(g), b: fromLinear(bb), a: alpha)
    }
    public var oklch: (l: Double, c: Double, h: Double) {
        let lab = oklab
        let c = sqrt(lab.a * lab.a + lab.b * lab.b)
        var h = atan2(lab.b, lab.a) * 180 / .pi
        if h < 0 { h += 360 }
        return (lab.l, c, c < 0.0001 ? 0 : h)
    }
    public static func fromOKLCH(l: Double, c: Double, h: Double, alpha: Double = 1) -> RGBA {
        fromOKLab(l: l, a: c * cos(h * .pi / 180), b: c * sin(h * .pi / 180), alpha: alpha)
    }

    public var lab: (l: Double, a: Double, b: Double) {
        let w = (0.95047, 1.0, 1.08883)
        let p = xyz
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        let fx = f(p.x / w.0), fy = f(p.y / w.1), fz = f(p.z / w.2)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
    public static func fromLab(l: Double, a: Double, b: Double, alpha: Double = 1) -> RGBA {
        let fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
        func inv(_ t: Double) -> Double { let t3 = t * t * t; return t3 > 0.008856 ? t3 : (t - 16 / 116) / 7.787 }
        return fromXYZ(0.95047 * inv(fx), 1.0 * inv(fy), 1.08883 * inv(fz), a: alpha)
    }

    // MARK: Display P3
    public var displayP3: (r: Double, g: Double, b: Double) {
        let p = xyz
        let r = 2.4934969 * p.x - 0.9313836 * p.y - 0.4027108 * p.z
        let g = -0.8294890 * p.x + 1.7626641 * p.y + 0.0236247 * p.z
        let b = 0.0358458 * p.x - 0.0761724 * p.y + 0.9568845 * p.z
        return (Self.fromLinear(r), Self.fromLinear(g), Self.fromLinear(b))
    }
    public static func fromDisplayP3(r: Double, g: Double, b: Double, a: Double = 1) -> RGBA {
        let lr = toLinear(r), lg = toLinear(g), lb = toLinear(b)
        let x = 0.4865709 * lr + 0.2656677 * lg + 0.1982173 * lb
        let y = 0.2289746 * lr + 0.6917385 * lg + 0.0792869 * lb
        let z = 0.0000000 * lr + 0.0451134 * lg + 1.0439444 * lb
        return fromXYZ(x, y, z, a: a)
    }

    // MARK: Contrast
    public func contrast(with other: RGBA) -> Double {
        let l1 = luminance, l2 = other.luminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    public func blended(over bg: RGBA) -> RGBA {
        RGBA(r: r * a + bg.r * (1 - a), g: g * a + bg.g * (1 - a), b: b * a + bg.b * (1 - a), a: 1)
    }

    public func mixed(with o: RGBA, _ t: Double) -> RGBA {
        let a1 = oklab, a2 = o.oklab
        return RGBA.fromOKLab(l: a1.l + (a2.l - a1.l) * t, a: a1.a + (a2.a - a1.a) * t, b: a1.b + (a2.b - a1.b) * t, alpha: a + (o.a - a) * t)
    }
}

public enum ColorParser {
    public static let named: [String: String] = [
        "aliceblue": "#F0F8FF", "antiquewhite": "#FAEBD7", "aqua": "#00FFFF", "aquamarine": "#7FFFD4", "azure": "#F0FFFF", "beige": "#F5F5DC", "bisque": "#FFE4C4", "black": "#000000", "blanchedalmond": "#FFEBCD", "blue": "#0000FF",
        "blueviolet": "#8A2BE2", "brown": "#A52A2A", "burlywood": "#DEB887", "cadetblue": "#5F9EA0", "chartreuse": "#7FFF00", "chocolate": "#D2691E", "coral": "#FF7F50", "cornflowerblue": "#6495ED", "cornsilk": "#FFF8DC", "crimson": "#DC143C",
        "cyan": "#00FFFF", "darkblue": "#00008B", "darkcyan": "#008B8B", "darkgoldenrod": "#B8860B", "darkgray": "#A9A9A9", "darkgreen": "#006400", "darkgrey": "#A9A9A9", "darkkhaki": "#BDB76B", "darkmagenta": "#8B008B", "darkolivegreen": "#556B2F",
        "darkorange": "#FF8C00", "darkorchid": "#9932CC", "darkred": "#8B0000", "darksalmon": "#E9967A", "darkseagreen": "#8FBC8F", "darkslateblue": "#483D8B", "darkslategray": "#2F4F4F", "darkslategrey": "#2F4F4F", "darkturquoise": "#00CED1", "darkviolet": "#9400D3",
        "deeppink": "#FF1493", "deepskyblue": "#00BFFF", "dimgray": "#696969", "dimgrey": "#696969", "dodgerblue": "#1E90FF", "firebrick": "#B22222", "floralwhite": "#FFFAF0", "forestgreen": "#228B22", "fuchsia": "#FF00FF", "gainsboro": "#DCDCDC",
        "ghostwhite": "#F8F8FF", "gold": "#FFD700", "goldenrod": "#DAA520", "gray": "#808080", "green": "#008000", "greenyellow": "#ADFF2F", "grey": "#808080", "honeydew": "#F0FFF0", "hotpink": "#FF69B4", "indianred": "#CD5C5C", "indigo": "#4B0082",
        "ivory": "#FFFFF0", "khaki": "#F0E68C", "lavender": "#E6E6FA", "lavenderblush": "#FFF0F5", "lawngreen": "#7CFC00", "lemonchiffon": "#FFFACD", "lightblue": "#ADD8E6", "lightcoral": "#F08080", "lightcyan": "#E0FFFF", "lightgoldenrodyellow": "#FAFAD2",
        "lightgray": "#D3D3D3", "lightgreen": "#90EE90", "lightgrey": "#D3D3D3", "lightpink": "#FFB6C1", "lightsalmon": "#FFA07A", "lightseagreen": "#20B2AA", "lightskyblue": "#87CEFA", "lightslategray": "#778899", "lightslategrey": "#778899", "lightsteelblue": "#B0C4DE",
        "lightyellow": "#FFFFE0", "lime": "#00FF00", "limegreen": "#32CD32", "linen": "#FAF0E6", "magenta": "#FF00FF", "maroon": "#800000", "mediumaquamarine": "#66CDAA", "mediumblue": "#0000CD", "mediumorchid": "#BA55D3", "mediumpurple": "#9370DB",
        "mediumseagreen": "#3CB371", "mediumslateblue": "#7B68EE", "mediumspringgreen": "#00FA9A", "mediumturquoise": "#48D1CC", "mediumvioletred": "#C71585", "midnightblue": "#191970", "mintcream": "#F5FFFA", "mistyrose": "#FFE4E1", "moccasin": "#FFE4B5", "navajowhite": "#FFDEAD",
        "navy": "#000080", "oldlace": "#FDF5E6", "olive": "#808000", "olivedrab": "#6B8E23", "orange": "#FFA500", "orangered": "#FF4500", "orchid": "#DA70D6", "palegoldenrod": "#EEE8AA", "palegreen": "#98FB98", "paleturquoise": "#AFEEEE",
        "palevioletred": "#DB7093", "papayawhip": "#FFEFD5", "peachpuff": "#FFDAB9", "peru": "#CD853F", "pink": "#FFC0CB", "plum": "#DDA0DD", "powderblue": "#B0E0E6", "purple": "#800080", "rebeccapurple": "#663399", "red": "#FF0000",
        "rosybrown": "#BC8F8F", "royalblue": "#4169E1", "saddlebrown": "#8B4513", "salmon": "#FA8072", "sandybrown": "#F4A460", "seagreen": "#2E8B57", "seashell": "#FFF5EE", "sienna": "#A0522D", "silver": "#C0C0C0", "skyblue": "#87CEEB",
        "slateblue": "#6A5ACD", "slategray": "#708090", "slategrey": "#708090", "snow": "#FFFAFA", "springgreen": "#00FF7F", "steelblue": "#4682B4", "tan": "#D2B48C", "teal": "#008080", "thistle": "#D8BFD8", "tomato": "#FF6347",
        "turquoise": "#40E0D0", "violet": "#EE82EE", "wheat": "#F5DEB3", "white": "#FFFFFF", "whitesmoke": "#F5F5F5", "yellow": "#FFFF00", "yellowgreen": "#9ACD32", "transparent": "#00000000",
    ]

    public static func parse(_ raw: String) -> (RGBA, String)? {
        var s = raw.trimmed()
        let lower = s.lowercased()
        if let hex = named[lower] { return parseHex(hex).map { ($0, "Named colour \(lower)") } }
        if s.hasPrefix("#") || lower.hasPrefix("0x") { return parseHex(s).map { ($0, "Hex") } }
        if lower.range(of: "^[0-9a-f]{3,8}$", options: .regularExpression) != nil, [3, 4, 6, 8].contains(s.count) { return parseHex("#" + s).map { ($0, "Hex (no #)") } }
        // Swift / UIKit / AppKit literals
        if let m = lower.captures("color\\s*\\(\\s*(?:\\.srgb|\\.displayp3)?\\s*,?\\s*red:\\s*([0-9.]+)\\s*,\\s*green:\\s*([0-9.]+)\\s*,\\s*blue:\\s*([0-9.]+)(?:\\s*,\\s*opacity:\\s*([0-9.]+))?") {
            let p3 = lower.contains("displayp3")
            let r = Double(m[1]) ?? 0, g = Double(m[2]) ?? 0, b = Double(m[3]) ?? 0, a = Double(m[4]) ?? 1
            return (p3 ? RGBA.fromDisplayP3(r: r, g: g, b: b, a: a) : RGBA(r: r, g: g, b: b, a: a), p3 ? "SwiftUI Color (Display P3)" : "SwiftUI Color")
        }
        if let m = lower.captures("(?:ns|ui)color\\s*\\(\\s*(?:srgb|displayp3|calibrated)?red:\\s*([0-9.]+)\\s*,\\s*green:\\s*([0-9.]+)\\s*,\\s*blue:\\s*([0-9.]+)\\s*,\\s*alpha:\\s*([0-9.]+)") {
            let r = Double(m[1]) ?? 0, g = Double(m[2]) ?? 0, b = Double(m[3]) ?? 0, a = Double(m[4]) ?? 1
            return (RGBA(r: r, g: g, b: b, a: a), "NSColor / UIColor")
        }
        if let m = lower.captures("^(rgba?|hsla?|hsba?|hsva?|hwb|cmyk|oklch|oklab|lab|lch|color)\\s*\\((.*)\\)$") {
            let fn = m[1]
            var inner = m[2].replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: ",", with: " ")
            var space = ""
            if fn == "color" {
                let parts = inner.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                space = parts.first ?? ""
                inner = parts.dropFirst().joined(separator: " ")
            }
            let comps = inner.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            func num(_ i: Int, scale: Double = 1, percentScale: Double = 1, fallback: Double = 0) -> Double {
                guard i < comps.count else { return fallback }
                var t = comps[i]
                if t == "none" { return 0 }
                if t.hasSuffix("%") { t.removeLast(); return (Double(t) ?? 0) / 100 * percentScale }
                if t.hasSuffix("deg") { t.removeLast(3) }
                if t.hasSuffix("turn") { t.removeLast(4); return (Double(t) ?? 0) * 360 }
                if t.hasSuffix("rad") { t.removeLast(3); return (Double(t) ?? 0) * 180 / .pi }
                return (Double(t) ?? fallback) * scale
            }
            func alpha(_ i: Int) -> Double { i < comps.count ? (comps[i].hasSuffix("%") ? num(i, percentScale: 1) : min(1, Double(comps[i]) ?? 1)) : 1 }
            switch fn {
            case "rgb", "rgba":
                let pct = comps.first?.hasSuffix("%") == true
                return (RGBA(r: pct ? num(0) : num(0) / 255, g: pct ? num(1) : num(1) / 255, b: pct ? num(2) : num(2) / 255, a: alpha(3)), "rgb()")
            case "hsl", "hsla": return (RGBA.fromHSL(h: num(0), s: num(1, percentScale: 1) * (comps[safe: 1]?.hasSuffix("%") == true ? 1 : (num(1) > 1 ? 0.01 : 1)), l: num(2, percentScale: 1) * (comps[safe: 2]?.hasSuffix("%") == true ? 1 : (num(2) > 1 ? 0.01 : 1)), a: alpha(3)), "hsl()")
            case "hsb", "hsba", "hsv", "hsva": return (RGBA.fromHSB(h: num(0), s: num(1) > 1 ? num(1) / 100 : num(1), b: num(2) > 1 ? num(2) / 100 : num(2), a: alpha(3)), "hsb()")
            case "hwb":
                let w = num(1), bl = num(2)
                let base = RGBA.fromHSB(h: num(0), s: 1, b: 1)
                let sum = w + bl
                let ww = sum > 1 ? w / sum : w, bb = sum > 1 ? bl / sum : bl
                return (RGBA(r: base.r * (1 - ww - bb) + ww, g: base.g * (1 - ww - bb) + ww, b: base.b * (1 - ww - bb) + ww, a: alpha(3)), "hwb()")
            case "cmyk": return (RGBA.fromCMYK(c: num(0) > 1 ? num(0) / 100 : num(0), m: num(1) > 1 ? num(1) / 100 : num(1), y: num(2) > 1 ? num(2) / 100 : num(2), k: num(3) > 1 ? num(3) / 100 : num(3), a: alpha(4)), "cmyk()")
            case "oklch": return (RGBA.fromOKLCH(l: comps[safe: 0]?.hasSuffix("%") == true ? num(0) : (num(0) > 1 ? num(0) / 100 : num(0)), c: comps[safe: 1]?.hasSuffix("%") == true ? num(1) * 0.4 : num(1), h: num(2), alpha: alpha(3)), "oklch()")
            case "oklab": return (RGBA.fromOKLab(l: comps[safe: 0]?.hasSuffix("%") == true ? num(0) : (num(0) > 1 ? num(0) / 100 : num(0)), a: comps[safe: 1]?.hasSuffix("%") == true ? num(1) * 0.4 : num(1), b: comps[safe: 2]?.hasSuffix("%") == true ? num(2) * 0.4 : num(2), alpha: alpha(3)), "oklab()")
            case "lab": return (RGBA.fromLab(l: comps[safe: 0]?.hasSuffix("%") == true ? num(0) * 100 : num(0), a: num(1), b: num(2), alpha: alpha(3)), "lab()")
            case "lch":
                let l = comps[safe: 0]?.hasSuffix("%") == true ? num(0) * 100 : num(0), c = num(1), h = num(2)
                return (RGBA.fromLab(l: l, a: c * cos(h * .pi / 180), b: c * sin(h * .pi / 180), alpha: alpha(3)), "lch()")
            case "color":
                switch space {
                case "display-p3": return (RGBA.fromDisplayP3(r: num(0), g: num(1), b: num(2), a: alpha(3)), "color(display-p3)")
                case "srgb": return (RGBA(r: num(0), g: num(1), b: num(2), a: alpha(3)), "color(srgb)")
                case "srgb-linear": return (RGBA(r: RGBA.fromLinear(num(0)), g: RGBA.fromLinear(num(1)), b: RGBA.fromLinear(num(2)), a: alpha(3)), "color(srgb-linear)")
                case "xyz", "xyz-d65": return (RGBA.fromXYZ(num(0), num(1), num(2), a: alpha(3)), "color(xyz)")
                default: return nil
                }
            default: return nil
            }
        }
        // bare "r, g, b" or "r g b"
        let nums = s.replacingOccurrences(of: ",", with: " ").split(separator: " ").compactMap { Double($0) }
        if nums.count == 3 || nums.count == 4 {
            if nums.allSatisfy({ $0 <= 1 }) { return (RGBA(r: nums[0], g: nums[1], b: nums[2], a: nums.count == 4 ? nums[3] : 1), "Normalised RGB") }
            if nums.allSatisfy({ $0 <= 255 }) { return (RGBA(r: nums[0] / 255, g: nums[1] / 255, b: nums[2] / 255, a: nums.count == 4 ? (nums[3] > 1 ? nums[3] / 255 : nums[3]) : 1), "RGB 0–255") }
        }
        s = ""
        return nil
    }

    public static func parseHex(_ raw: String) -> RGBA? {
        var h = raw.trimmed().removingPrefix("#").removingPrefix("0x").removingPrefix("0X")
        guard h.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil else { return nil }
        if h.count == 3 || h.count == 4 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6 || h.count == 8, let v = UInt32(h, radix: 16) else { return nil }
        if h.count == 8 {
            return RGBA(r: Double((v >> 24) & 0xFF) / 255, g: Double((v >> 16) & 0xFF) / 255, b: Double((v >> 8) & 0xFF) / 255, a: Double(v & 0xFF) / 255)
        }
        return RGBA(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    public static func nearestName(_ c: RGBA) -> (String, Double) {
        var best = ("", Double.greatestFiniteMagnitude)
        let lab = c.oklab
        for (name, hex) in named where name != "transparent" {
            guard let n = parseHex(hex) else { continue }
            let l = n.oklab
            let d = pow(lab.l - l.l, 2) + pow(lab.a - l.a, 2) + pow(lab.b - l.b, 2)
            if d < best.1 { best = (name, d) }
        }
        return (best.0, sqrt(best.1))
    }

    /// Tailwind CSS v3 default palette (500 shades plus key tones) for "nearest Tailwind colour".
    public static let tailwind: [(String, String)] = [
        ("slate-50", "#f8fafc"), ("slate-100", "#f1f5f9"), ("slate-200", "#e2e8f0"), ("slate-300", "#cbd5e1"), ("slate-400", "#94a3b8"), ("slate-500", "#64748b"), ("slate-600", "#475569"), ("slate-700", "#334155"), ("slate-800", "#1e293b"), ("slate-900", "#0f172a"), ("slate-950", "#020617"),
        ("gray-50", "#f9fafb"), ("gray-100", "#f3f4f6"), ("gray-200", "#e5e7eb"), ("gray-300", "#d1d5db"), ("gray-400", "#9ca3af"), ("gray-500", "#6b7280"), ("gray-600", "#4b5563"), ("gray-700", "#374151"), ("gray-800", "#1f2937"), ("gray-900", "#111827"), ("gray-950", "#030712"),
        ("zinc-100", "#f4f4f5"), ("zinc-300", "#d4d4d8"), ("zinc-500", "#71717a"), ("zinc-700", "#3f3f46"), ("zinc-900", "#18181b"), ("neutral-100", "#f5f5f5"), ("neutral-300", "#d4d4d4"), ("neutral-500", "#737373"), ("neutral-700", "#404040"), ("neutral-900", "#171717"),
        ("stone-100", "#f5f5f4"), ("stone-300", "#d6d3d1"), ("stone-500", "#78716c"), ("stone-700", "#44403c"), ("stone-900", "#1c1917"),
        ("red-50", "#fef2f2"), ("red-100", "#fee2e2"), ("red-200", "#fecaca"), ("red-300", "#fca5a5"), ("red-400", "#f87171"), ("red-500", "#ef4444"), ("red-600", "#dc2626"), ("red-700", "#b91c1c"), ("red-800", "#991b1b"), ("red-900", "#7f1d1d"),
        ("orange-100", "#ffedd5"), ("orange-200", "#fed7aa"), ("orange-300", "#fdba74"), ("orange-400", "#fb923c"), ("orange-500", "#f97316"), ("orange-600", "#ea580c"), ("orange-700", "#c2410c"), ("orange-800", "#9a3412"), ("orange-900", "#7c2d12"),
        ("amber-100", "#fef3c7"), ("amber-200", "#fde68a"), ("amber-300", "#fcd34d"), ("amber-400", "#fbbf24"), ("amber-500", "#f59e0b"), ("amber-600", "#d97706"), ("amber-700", "#b45309"), ("amber-800", "#92400e"), ("amber-900", "#78350f"),
        ("yellow-100", "#fef9c3"), ("yellow-200", "#fef08a"), ("yellow-300", "#fde047"), ("yellow-400", "#facc15"), ("yellow-500", "#eab308"), ("yellow-600", "#ca8a04"), ("yellow-700", "#a16207"), ("yellow-800", "#854d0e"), ("yellow-900", "#713f12"),
        ("lime-100", "#ecfccb"), ("lime-300", "#bef264"), ("lime-400", "#a3e635"), ("lime-500", "#84cc16"), ("lime-600", "#65a30d"), ("lime-700", "#4d7c0f"), ("lime-900", "#365314"),
        ("green-50", "#f0fdf4"), ("green-100", "#dcfce7"), ("green-200", "#bbf7d0"), ("green-300", "#86efac"), ("green-400", "#4ade80"), ("green-500", "#22c55e"), ("green-600", "#16a34a"), ("green-700", "#15803d"), ("green-800", "#166534"), ("green-900", "#14532d"),
        ("emerald-100", "#d1fae5"), ("emerald-300", "#6ee7b7"), ("emerald-400", "#34d399"), ("emerald-500", "#10b981"), ("emerald-600", "#059669"), ("emerald-700", "#047857"), ("emerald-900", "#064e3b"),
        ("teal-100", "#ccfbf1"), ("teal-300", "#5eead4"), ("teal-400", "#2dd4bf"), ("teal-500", "#14b8a6"), ("teal-600", "#0d9488"), ("teal-700", "#0f766e"), ("teal-900", "#134e4a"),
        ("cyan-100", "#cffafe"), ("cyan-300", "#67e8f9"), ("cyan-400", "#22d3ee"), ("cyan-500", "#06b6d4"), ("cyan-600", "#0891b2"), ("cyan-700", "#0e7490"), ("cyan-900", "#164e63"),
        ("sky-100", "#e0f2fe"), ("sky-300", "#7dd3fc"), ("sky-400", "#38bdf8"), ("sky-500", "#0ea5e9"), ("sky-600", "#0284c7"), ("sky-700", "#0369a1"), ("sky-900", "#0c4a6e"),
        ("blue-50", "#eff6ff"), ("blue-100", "#dbeafe"), ("blue-200", "#bfdbfe"), ("blue-300", "#93c5fd"), ("blue-400", "#60a5fa"), ("blue-500", "#3b82f6"), ("blue-600", "#2563eb"), ("blue-700", "#1d4ed8"), ("blue-800", "#1e40af"), ("blue-900", "#1e3a8a"),
        ("indigo-100", "#e0e7ff"), ("indigo-300", "#a5b4fc"), ("indigo-400", "#818cf8"), ("indigo-500", "#6366f1"), ("indigo-600", "#4f46e5"), ("indigo-700", "#4338ca"), ("indigo-900", "#312e81"),
        ("violet-100", "#ede9fe"), ("violet-300", "#c4b5fd"), ("violet-400", "#a78bfa"), ("violet-500", "#8b5cf6"), ("violet-600", "#7c3aed"), ("violet-700", "#6d28d9"), ("violet-900", "#4c1d95"),
        ("purple-100", "#f3e8ff"), ("purple-300", "#d8b4fe"), ("purple-400", "#c084fc"), ("purple-500", "#a855f7"), ("purple-600", "#9333ea"), ("purple-700", "#7e22ce"), ("purple-900", "#581c87"),
        ("fuchsia-100", "#fae8ff"), ("fuchsia-300", "#f0abfc"), ("fuchsia-400", "#e879f9"), ("fuchsia-500", "#d946ef"), ("fuchsia-600", "#c026d3"), ("fuchsia-700", "#a21caf"), ("fuchsia-900", "#701a75"),
        ("pink-100", "#fce7f3"), ("pink-300", "#f9a8d4"), ("pink-400", "#f472b6"), ("pink-500", "#ec4899"), ("pink-600", "#db2777"), ("pink-700", "#be185d"), ("pink-900", "#831843"),
        ("rose-100", "#ffe4e6"), ("rose-300", "#fda4af"), ("rose-400", "#fb7185"), ("rose-500", "#f43f5e"), ("rose-600", "#e11d48"), ("rose-700", "#be123c"), ("rose-900", "#881337"),
        ("white", "#ffffff"), ("black", "#000000"),
    ]

    public static func nearestTailwind(_ c: RGBA) -> String {
        var best = ("", Double.greatestFiniteMagnitude)
        let lab = c.oklab
        for (name, hex) in tailwind {
            guard let n = parseHex(hex) else { continue }
            let l = n.oklab
            let d = pow(lab.l - l.l, 2) + pow(lab.a - l.a, 2) + pow(lab.b - l.b, 2)
            if d < best.1 { best = (name, d) }
        }
        return best.0
    }
}
