import Foundation
import CoreGraphics
import BitlatheCore

public struct PlaceholderImageTool: DevTool {
    public static let id = "image.placeholder"
    public static let name = "Placeholder Image"
    public static let summary = "Generate placeholder images of any size with colours and a label — PNG, JPEG or SVG"
    public static let category = ToolCategory.generate
    public static let symbol = "photo.artframe"
    public static let keywords = ["placeholder", "image", "dummy", "mock", "thumbnail", "png", "svg", "generate", "size"]
    public static let io = ToolIO(input: .text, output: .image, acceptsFiles: false)
    public static let samples = [ToolSample("Hero", "1200x630"), ToolSample("Avatar", "256x256 Ada"), ToolSample("Batch", "320x240\n640x480\n1920x1080")]
    public static let optionFields: [OptionField] = [
        .text("background", "Background", placeholder: "#E5E7EB or random", default: "#E5E7EB"),
        .text("foreground", "Text colour", placeholder: "#6B7280", default: "#6B7280"),
        .text("label", "Label", placeholder: "defaults to WIDTH×HEIGHT"),
        .segmented("format", "Format", [.init("png", "PNG"), .init("jpeg", "JPEG"), .init("svg", "SVG")], default: "png"),
        .toggle("gradient", "Gradient", help: "Subtle diagonal gradient from the background colour"),
        .toggle("grid", "Grid"),
        .stepper("scale", "Scale", min: 1, max: 3, default: 1, help: "@2x / @3x"),
    ]
    public struct Options: ToolOptions {
        public var background = "#E5E7EB"
        public var foreground = "#6B7280"
        public var label = ""
        public var format = "png"
        public var gradient = false
        public var grid = false
        public var scale = 1
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let spec = input.text.trimmed().isEmpty ? "600x400" : input.text.trimmed()
        let first = spec.components(separatedBy: "\n")[0]
        guard let m = first.captures("^(\\d{1,5})\\s*[x×*]\\s*(\\d{1,5})(?:\\s+(.*))?$"), let w = Int(m[1]), let h = Int(m[2]), w > 0, h > 0, w * h <= 50_000_000 else {
            throw ToolError("Enter a size like 1200x630, optionally followed by a label", hint: "Each line can be a separate size; the first one is rendered")
        }
        let label = options.label.isEmpty ? (m[3].isEmpty ? "\(w) × \(h)" : m[3]) : options.label
        var bg = ColorParser.parse(options.background)?.0 ?? RGBA(r: 0.9, g: 0.91, b: 0.92)
        if options.background.lowercased() == "random" { bg = RGBA.fromHSL(h: Double.random(in: 0..<360), s: 0.55, l: 0.6) }
        let fg = ColorParser.parse(options.foreground)?.0 ?? (bg.luminance > 0.5 ? RGBA(r: 0.42, g: 0.45, b: 0.5) : RGBA(r: 1, g: 1, b: 1))
        let fontSize = max(10, min(Double(w), Double(h)) / 6)
        if options.format == "svg" {
            var defs = ""
            var fill = bg.hex
            if options.gradient {
                let bg2 = bg.mixed(with: RGBA(r: 0, g: 0, b: 0), 0.2)
                defs = "<defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(bg.hex)\"/><stop offset=\"1\" stop-color=\"\(bg2.hex)\"/></linearGradient></defs>"
                fill = "url(#g)"
            }
            var grid = ""
            if options.grid {
                defs += "<defs><pattern id=\"p\" width=\"40\" height=\"40\" patternUnits=\"userSpaceOnUse\"><path d=\"M40 0H0V40\" fill=\"none\" stroke=\"\(fg.hex)\" stroke-opacity=\"0.15\"/></pattern></defs>"
                grid = "<rect width=\"\(w)\" height=\"\(h)\" fill=\"url(#p)\"/>"
            }
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\" viewBox=\"0 0 \(w) \(h)\">\(defs)<rect width=\"\(w)\" height=\"\(h)\" fill=\"\(fill)\"/>\(grid)<text x=\"50%\" y=\"50%\" dominant-baseline=\"central\" text-anchor=\"middle\" font-family=\"-apple-system, Helvetica, Arial, sans-serif\" font-weight=\"600\" font-size=\"\(Int(fontSize))\" fill=\"\(fg.hex)\">\(XMLJSON.escape(label))</text></svg>"
            return ToolOutput(.image(Data(svg.utf8), .svg), facets: [OutputFacet("SVG source", text: svg, language: .xml)], metadata: [MetaRow("Size", "\(w) × \(h)"), MetaRow("Format", "SVG")], suggestedFileName: "placeholder-\(w)x\(h).svg")
        }
        let s = options.scale
        guard let ctx = ImageRender.context(width: w * s, height: h * s) else { throw ToolError("Render failure") }
        ctx.scaleBy(x: CGFloat(s), y: CGFloat(s))
        if options.gradient {
            let bg2 = bg.mixed(with: RGBA(r: 0, g: 0, b: 0), 0.2)
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [ImageRender.cgColor(bg), ImageRender.cgColor(bg2)] as CFArray, locations: [0, 1])!   // swiftlint:disable:this force_unwrapping
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: CGFloat(w), y: 0), options: [])
        } else {
            ctx.setFillColor(ImageRender.cgColor(bg))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        if options.grid {
            ctx.setStrokeColor(ImageRender.cgColor(RGBA(r: fg.r, g: fg.g, b: fg.b, a: 0.15)))
            ctx.setLineWidth(1)
            var x = 0
            while x <= w { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: h)); x += 40 }
            var y = 0
            while y <= h { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: w, y: y)); y += 40 }
            ctx.strokePath()
        }
        ImageRender.drawText(label, in: CGRect(x: 0, y: 0, width: w, height: h), context: ctx, fontSize: fontSize, color: ImageRender.cgColor(fg))
        guard let img = ctx.makeImage(), let data = ImageRender.encode(img, format: options.format == "jpeg" ? .jpeg : .png, quality: 0.9) else { throw ToolError("Encoding failed") }
        let meta = [MetaRow("Size", "\(w) × \(h)" + (s > 1 ? " @\(s)x (\(w * s) × \(h * s) px)" : "")), MetaRow("Format", options.format.uppercased()), MetaRow("File size", ByteFormatter.string(data.count))]
        return ToolOutput(.image(data, options.format == "jpeg" ? .jpeg : .png), metadata: meta, suggestedFileName: "placeholder-\(w)x\(h).\(options.format == "jpeg" ? "jpg" : "png")")
    }

    public static func detect(_ s: String) -> DetectionScore? {
        s.range(of: "^\\d{2,5}\\s*[x×]\\s*\\d{2,5}$", options: .regularExpression) != nil ? DetectionScore(0.5, "Image size") : nil
    }
}
