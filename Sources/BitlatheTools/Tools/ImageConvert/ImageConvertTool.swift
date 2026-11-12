import Foundation
import CoreGraphics
import ImageIO
import BitlatheCore

public struct ImageConvertTool: DevTool {
    public static let id = "image.convert"
    public static let name = "Image Convert & Resize"
    public static let summary = "Convert between PNG, JPEG, HEIC, WebP, TIFF, GIF and BMP, resize, compress and strip metadata"
    public static let category = ToolCategory.media
    public static let symbol = "photo.on.rectangle.angled"
    public static let keywords = ["image", "convert", "resize", "compress", "png", "jpeg", "heic", "webp", "avif", "tiff", "optimise", "scale", "thumbnail"]
    public static let io = ToolIO(input: .image, output: .image, acceptsFiles: true)
    public static let optionFields: [OptionField] = [
        .picker("format", "Format", [.init("same", "Keep")] + ImageRender.writableFormats.sorted { $0.rawValue < $1.rawValue }.map { OptionChoice($0.rawValue, $0.rawValue.uppercased()) }, default: "same"),
        .slider("quality", "Quality", min: 0.1, max: 1.0, default: 0.85),
        .picker("resizeMode", "Resize", [.init("none", "No resize"), .init("width", "Width"), .init("height", "Height"), .init("fit", "Fit in box"), .init("percent", "Percent"), .init("exact", "Exact")], default: "none"),
        .stepper("width", "Width", min: 1, max: 16384, step: 10, default: 1024, visibleWhen: ("resizeMode", ["width", "fit", "exact"])),
        .stepper("height", "Height", min: 1, max: 16384, step: 10, default: 1024, visibleWhen: ("resizeMode", ["height", "fit", "exact"])),
        .stepper("percent", "Percent", min: 1, max: 400, default: 50, visibleWhen: ("resizeMode", ["percent"])),
        .toggle("stripMetadata", "Strip metadata", default: true),
        .text("background", "Flatten alpha onto", placeholder: "#FFFFFF (for JPEG)", default: "#FFFFFF", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var format = "same"
        public var quality = 0.85
        public var resizeMode = "none"
        public var width = 1024
        public var height = 1024
        public var percent = 50
        public var stripMetadata = true
        public var background = "#FFFFFF"
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let data = input.data
        guard !data.isEmpty else { throw ToolError("Drop an image or paste one") }
        guard var image = ImageRender.cgImage(from: data) else { throw ToolError("Not a readable image") }
        let sourceFormat = ImageFormat.sniff(data) ?? .png
        let props = (CGImageSourceCreateWithData(data as CFData, nil)).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
        let orientation = props[kCGImagePropertyOrientation as String] as? Int ?? 1
        if orientation != 1 { image = Self.applyOrientation(image, orientation) ?? image }
        let target = options.format == "same" ? (sourceFormat == .svg ? .png : sourceFormat) : (ImageFormat(rawValue: options.format) ?? .png)
        guard ImageRender.writableFormats.contains(target) else { throw ToolError.unsupported("Encoding \(target.rawValue.uppercased())") }
        let ow = image.width, oh = image.height
        var nw = ow, nh = oh
        switch options.resizeMode {
        case "width": nw = options.width; nh = max(1, Int(Double(oh) * Double(options.width) / Double(ow)))
        case "height": nh = options.height; nw = max(1, Int(Double(ow) * Double(options.height) / Double(oh)))
        case "fit":
            let s = min(Double(options.width) / Double(ow), Double(options.height) / Double(oh), 1)
            nw = max(1, Int(Double(ow) * s)); nh = max(1, Int(Double(oh) * s))
        case "percent": nw = max(1, ow * options.percent / 100); nh = max(1, oh * options.percent / 100)
        case "exact": nw = options.width; nh = options.height
        default: break
        }
        try Task.checkpoint()
        if nw != ow || nh != oh { guard let r = ImageRender.resized(image, to: CGSize(width: nw, height: nh)) else { throw ToolError("Resize failed") }; image = r }
        let needsFlatten = (target == .jpeg || target == .bmp) && (image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst)
        if needsFlatten, let ctx = ImageRender.context(width: image.width, height: image.height) {
            ctx.setFillColor(ImageRender.cgColor(ColorParser.parse(options.background)?.0 ?? RGBA(r: 1, g: 1, b: 1)))
            ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            image = ctx.makeImage() ?? image
        }
        var extra: [CFString: Any] = [:]
        if !options.stripMetadata, let exif = props[kCGImagePropertyExifDictionary as String] { extra[kCGImagePropertyExifDictionary] = exif }
        if !options.stripMetadata, let tiff = props[kCGImagePropertyTIFFDictionary as String] { extra[kCGImagePropertyTIFFDictionary] = tiff }
        if !options.stripMetadata, let gps = props[kCGImagePropertyGPSDictionary as String] { extra[kCGImagePropertyGPSDictionary] = gps }
        guard let out = ImageRender.encode(image, format: target, quality: options.quality, properties: extra) else { throw ToolError("Encoding to \(target.rawValue.uppercased()) failed") }
        let change = Double(out.count - data.count) / Double(max(data.count, 1)) * 100
        let rows = [
            MetaRow("Input", "\(sourceFormat.rawValue.uppercased()) · \(ow) × \(oh) · \(ByteFormatter.string(data.count))"),
            MetaRow("Output", "\(target.rawValue.uppercased()) · \(image.width) × \(image.height) · \(ByteFormatter.string(out.count))"),
            MetaRow("Size change", String(format: "%+.1f%%", change), style: change < 0 ? .success : .plain),
            MetaRow("Metadata", options.stripMetadata ? "Stripped" : "Preserved (EXIF/TIFF/GPS)"),
        ]
        let base = ((input.fileName ?? "image") as NSString).deletingPathExtension
        return ToolOutput(.image(out, target), metadata: rows, suggestedFileName: "\(base).\(target.fileExtension)")
    }

    static func applyOrientation(_ image: CGImage, _ orientation: Int) -> CGImage? {
        let w = image.width, h = image.height
        let swap = orientation >= 5
        guard let ctx = ImageRender.context(width: swap ? h : w, height: swap ? w : h) else { return nil }
        var t = CGAffineTransform.identity
        switch orientation {
        case 2: t = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -CGFloat(w), y: 0)
        case 3: t = CGAffineTransform(translationX: CGFloat(w), y: CGFloat(h)).rotated(by: .pi)
        case 4: t = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(h))
        case 5: t = CGAffineTransform(translationX: CGFloat(h), y: CGFloat(w)).rotated(by: .pi / 2).scaledBy(x: 1, y: -1).translatedBy(x: 0, y: -CGFloat(h))
        case 6: t = CGAffineTransform(translationX: CGFloat(h), y: 0).rotated(by: .pi / 2)
        case 7: t = CGAffineTransform(translationX: 0, y: CGFloat(w)).rotated(by: -.pi / 2).scaledBy(x: 1, y: -1).translatedBy(x: 0, y: -CGFloat(h))
        case 8: t = CGAffineTransform(translationX: 0, y: CGFloat(w)).rotated(by: -.pi / 2)
        default: break
        }
        ctx.concatenate(t)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
