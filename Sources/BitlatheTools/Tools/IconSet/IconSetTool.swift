import Foundation
import CoreGraphics
import BitlatheCore

public struct IconSetTool: DevTool {
    public static let id = "icon.set"
    public static let name = "App Icon & Favicon Set"
    public static let summary = "Turn one square image into .icns, .ico, favicons, or an iOS/macOS asset catalogue"
    public static let category = ToolCategory.generate
    public static let symbol = "app.badge"
    public static let keywords = ["icon", "icns", "ico", "favicon", "app icon", "asset catalog", "appiconset", "ios", "macos", "pwa", "generate"]
    public static let io = ToolIO(input: .image, output: .binary, acceptsFiles: true)
    public static let optionFields: [OptionField] = [
        .picker("target", "Target", [.init("icns", "macOS .icns"), .init("ico", "Windows .ico"), .init("favicon", "Favicon bundle (zip)"), .init("ios", "iOS AppIcon.appiconset (zip)"), .init("macos", "macOS AppIcon.appiconset (zip)"), .init("android", "Android mipmaps (zip)"), .init("pwa", "PWA icons (zip)")], default: "icns"),
        .toggle("padding", "Add macOS-style padding", help: "Shrinks the artwork to ~82% inside the canvas, as Apple's macOS icon grid expects", visibleWhen: ("target", ["icns", "macos"])),
        .text("background", "Background", placeholder: "transparent or #FFFFFF", help: "Fill behind transparent artwork (required for iOS)", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var target = "icns"
        public var padding = false
        public var background = ""
        public init() {}
    }
    public init() {}

    static func render(_ src: CGImage, size: Int, padding: Bool, background: RGBA?) -> Data? {
        guard let ctx = ImageRender.context(width: size, height: size) else { return nil }
        if let background { ctx.setFillColor(ImageRender.cgColor(background)); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size)) }
        ctx.interpolationQuality = .high
        let inset = padding ? Double(size) * 0.09 : 0
        ctx.draw(src, in: CGRect(x: inset, y: inset, width: Double(size) - 2 * inset, height: Double(size) - 2 * inset))
        return ctx.makeImage().flatMap { ImageRender.encode($0, format: .png) }
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let data = input.data
        guard !data.isEmpty, let src = ImageRender.cgImage(from: data) else { throw ToolError("Drop a square PNG (1024×1024 recommended)") }
        var warnings: [String] = []
        if src.width != src.height { warnings.append("Image is \(src.width)×\(src.height); it will be stretched to a square. Use a square source for best results.") }
        if src.width < 1024 { warnings.append("Source is \(src.width) px wide; 1024 px is recommended for crisp large sizes.") }
        let bg = options.background.isEmpty || options.background.lowercased() == "transparent" ? nil : ColorParser.parse(options.background)?.0
        func png(_ s: Int) throws -> Data {
            guard let d = Self.render(src, size: s, padding: options.padding, background: bg) else { throw ToolError("Render failure at \(s) px") }
            return d
        }
        var rows: [MetaRow] = [MetaRow("Source", "\(src.width) × \(src.height) px")]
        let out: Data
        let name: String
        switch options.target {
        case "ico":
            let sizes = [16, 24, 32, 48, 64, 128, 256]
            out = ArchiveWriters.ico(try sizes.map { ($0, try png($0)) })
            name = "icon.ico"
            rows.append(MetaRow("Sizes", sizes.map(String.init).joined(separator: ", ")))
        case "favicon":
            var entries: [(String, Data)] = [("favicon.ico", ArchiveWriters.ico(try [16, 32, 48].map { ($0, try png($0)) }))]
            for s in [16, 32, 48, 96, 180, 192, 512] { entries.append(("favicon-\(s)x\(s).png", try png(s))) }
            entries.append(("apple-touch-icon.png", try png(180)))
            entries.append(("site.webmanifest", Data("""
            {
              "name": "App",
              "short_name": "App",
              "icons": [
                { "src": "/favicon-192x192.png", "sizes": "192x192", "type": "image/png" },
                { "src": "/favicon-512x512.png", "sizes": "512x512", "type": "image/png" }
              ],
              "theme_color": "#ffffff",
              "background_color": "#ffffff",
              "display": "standalone"
            }
            """.utf8)))
            entries.append(("snippet.html", Data("""
            <link rel="icon" href="/favicon.ico" sizes="48x48">
            <link rel="icon" href="/favicon-32x32.png" type="image/png" sizes="32x32">
            <link rel="apple-touch-icon" href="/apple-touch-icon.png">
            <link rel="manifest" href="/site.webmanifest">
            """.utf8)))
            out = ArchiveWriters.zip(entries)
            name = "favicons.zip"
            rows.append(MetaRow("Files", entries.map(\.0).joined(separator: ", ")))
        case "ios":
            let sizes: [(Double, Int, String)] = [(20, 2, "iphone"), (20, 3, "iphone"), (29, 2, "iphone"), (29, 3, "iphone"), (40, 2, "iphone"), (40, 3, "iphone"), (60, 2, "iphone"), (60, 3, "iphone"),
                                                 (20, 1, "ipad"), (20, 2, "ipad"), (29, 1, "ipad"), (29, 2, "ipad"), (40, 1, "ipad"), (40, 2, "ipad"), (76, 1, "ipad"), (76, 2, "ipad"), (83.5, 2, "ipad"), (1024, 1, "ios-marketing")]
            var entries: [(String, Data)] = []
            var images: [JSONValue] = []
            for (pt, scale, idiom) in sizes {
                let px = Int(pt * Double(scale))
                let file = "icon-\(pt == pt.rounded() ? String(Int(pt)) : String(pt))@\(scale)x.png"
                if !entries.contains(where: { $0.0 == "AppIcon.appiconset/\(file)" }) { entries.append(("AppIcon.appiconset/\(file)", try png(px))) }
                images.append(.object([(key: "filename", value: .string(file)), (key: "idiom", value: .string(idiom)), (key: "scale", value: .string("\(scale)x")), (key: "size", value: .string("\(pt == pt.rounded() ? String(Int(pt)) : String(pt))x\(pt == pt.rounded() ? String(Int(pt)) : String(pt))"))]))
            }
            let contents = JSONSerializer.string(.object([(key: "images", value: .array(images)), (key: "info", value: .object([(key: "author", value: .string("xcode")), (key: "version", value: .number(1))]))]))
            entries.append(("AppIcon.appiconset/Contents.json", Data(contents.utf8)))
            out = ArchiveWriters.zip(entries)
            name = "AppIcon.appiconset.zip"
            if bg == nil { warnings.append("iOS icons must be opaque — set a background colour in the advanced options if the artwork has transparency.") }
            rows.append(MetaRow("Images", "\(entries.count - 1)"))
        case "macos":
            let sizes = [16, 32, 128, 256, 512]
            var entries: [(String, Data)] = []
            var images: [JSONValue] = []
            for s in sizes {
                for scale in [1, 2] {
                    let file = "icon_\(s)x\(s)@\(scale)x.png"
                    entries.append(("AppIcon.appiconset/\(file)", try png(s * scale)))
                    images.append(.object([(key: "filename", value: .string(file)), (key: "idiom", value: .string("mac")), (key: "scale", value: .string("\(scale)x")), (key: "size", value: .string("\(s)x\(s)"))]))
                }
            }
            entries.append(("AppIcon.appiconset/Contents.json", Data(JSONSerializer.string(.object([(key: "images", value: .array(images)), (key: "info", value: .object([(key: "author", value: .string("xcode")), (key: "version", value: .number(1))]))])).utf8)))
            out = ArchiveWriters.zip(entries)
            name = "AppIcon.appiconset.zip"
            rows.append(MetaRow("Images", "\(entries.count - 1)"))
        case "android":
            let densities: [(String, Int)] = [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]
            var entries: [(String, Data)] = []
            for (d, s) in densities {
                entries.append(("res/mipmap-\(d)/ic_launcher.png", try png(s)))
                entries.append(("res/mipmap-\(d)/ic_launcher_round.png", try png(s)))
            }
            entries.append(("playstore-icon-512.png", try png(512)))
            out = ArchiveWriters.zip(entries)
            name = "android-icons.zip"
            rows.append(MetaRow("Densities", densities.map(\.0).joined(separator: ", ")))
        case "pwa":
            let sizes = [72, 96, 128, 144, 152, 192, 384, 512]
            var entries: [(String, Data)] = try sizes.map { ("icons/icon-\($0)x\($0).png", try png($0)) }
            entries.append(("icons/maskable-512x512.png", try { guard let d = Self.render(src, size: 512, padding: true, background: bg ?? RGBA(r: 1, g: 1, b: 1)) else { throw ToolError("Render failure") }; return d }()))
            entries.append(("manifest.webmanifest", Data(JSONSerializer.string(.object([(key: "icons", value: .array(sizes.map { .object([(key: "src", value: .string("icons/icon-\($0)x\($0).png")), (key: "sizes", value: .string("\($0)x\($0)")), (key: "type", value: .string("image/png"))]) } + [.object([(key: "src", value: .string("icons/maskable-512x512.png")), (key: "sizes", value: .string("512x512")), (key: "type", value: .string("image/png")), (key: "purpose", value: .string("maskable"))])]))])).utf8)))
            out = ArchiveWriters.zip(entries)
            name = "pwa-icons.zip"
            rows.append(MetaRow("Sizes", sizes.map(String.init).joined(separator: ", ")))
        default:
            var pngs: [Int: Data] = [:]
            for s in [16, 32, 64, 128, 256, 512, 1024] { pngs[s] = try png(s) }
            out = ArchiveWriters.icns(pngs)
            name = "AppIcon.icns"
            rows.append(MetaRow("Sizes", "16–1024 px including @2x variants"))
        }
        rows.append(MetaRow("Output", "\(name) · \(ByteFormatter.string(out.count))"))
        return ToolOutput(.data(out), metadata: rows, warnings: warnings, suggestedFileName: name)
    }
}
