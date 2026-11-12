import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import BitlatheCore

public struct QRCodeTool: DevTool {
    public static let id = "qr.code"
    public static let name = "QR Code"
    public static let summary = "Generate QR codes with colours, a centre logo and error correction — PNG or SVG — and read QR codes from images"
    public static let category = ToolCategory.generate
    public static let symbol = "qrcode"
    public static let keywords = ["qr", "qr code", "barcode", "scan", "read", "generate", "svg", "wifi", "vcard", "url"]
    public static let io = ToolIO(input: .text, output: .image, acceptsFiles: true)
    public static let samples = [ToolSample("URL", "https://bitlathe.app"), ToolSample("Wi-Fi", "WIFI:T:WPA;S:MyNetwork;P:secretpass;;"), ToolSample("vCard", "BEGIN:VCARD\nVERSION:3.0\nN:Lovelace;Ada\nTEL:+441234567890\nEMAIL:ada@example.com\nEND:VCARD")]
    public static let optionFields: [OptionField] = [
        .mode([.init("generate", "Generate"), .init("read", "Read")], default: "generate"),
        .segmented("correction", "Error correction", [.init("L", "L 7%"), .init("M", "M 15%"), .init("Q", "Q 25%"), .init("H", "H 30%")], default: "M", visibleWhen: ("mode", ["generate"])),
        .stepper("size", "Size px", min: 64, max: 4096, step: 64, default: 512, visibleWhen: ("mode", ["generate"])),
        .segmented("format", "Format", [.init("png", "PNG"), .init("svg", "SVG")], default: "png", visibleWhen: ("mode", ["generate"])),
        .text("foreground", "Foreground", placeholder: "#000000", default: "#000000", visibleWhen: ("mode", ["generate"])),
        .text("background", "Background", placeholder: "#FFFFFF or transparent", default: "#FFFFFF", visibleWhen: ("mode", ["generate"])),
        .stepper("quietZone", "Quiet zone", min: 0, max: 8, default: 2, help: "Modules of margin", visibleWhen: ("mode", ["generate"]), advanced: true),
        .toggle("rounded", "Rounded modules", visibleWhen: ("format", ["svg"])),
        .text("logo", "Logo (file path or data URI)", placeholder: "/path/to/logo.png", help: "Drawn in the centre; use error correction H", visibleWhen: ("mode", ["generate"]), advanced: true),
    ]
    public struct Options: ToolOptions {
        public var mode = "generate"
        public var correction = "M"
        public var size = 512
        public var format = "png"
        public var foreground = "#000000"
        public var background = "#FFFFFF"
        public var quietZone = 2
        public var rounded = false
        public var logo = ""
        public init() {}
    }
    public init() {}

    /// Module matrix from CoreImage's generator (rendered 1 px per module).
    public static func matrix(for text: String, correction: String) throws -> [[Bool]] {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction
        guard let img = filter.outputImage, let cg = ImageRender.render(ciImage: img) else { throw ToolError("Could not generate the QR code", hint: "Input may be too long (max ~2950 bytes at level L)") }
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw ToolError("Render failure") }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let ptr = ctx.data?.assumingMemoryBound(to: UInt8.self) else { throw ToolError("Render failure") }
        // CoreImage adds a 1-module quiet zone; strip it.
        var rows: [[Bool]] = []
        for y in 1..<(h - 1) {
            var row: [Bool] = []
            for x in 1..<(w - 1) { row.append(ptr[(h - 1 - y) * w + x] < 128) }
            rows.append(row)
        }
        return rows
    }

    public static func svg(_ m: [[Bool]], foreground: String, background: String?, quiet: Int, rounded: Bool, size: Int) -> String {
        let n = m.count + quiet * 2
        var s = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(n) \(n)\" width=\"\(size)\" height=\"\(size)\" shape-rendering=\"crispEdges\">\n"
        if let bg = background { s += "  <rect width=\"\(n)\" height=\"\(n)\" fill=\"\(bg)\"/>\n" }
        var path = ""
        for (y, row) in m.enumerated() {
            for (x, on) in row.enumerated() where on {
                if rounded { path += "M\(Double(x + quiet) + 0.5) \(y + quiet)a0.5 0.5 0 1 0 0.001 0z" }
                else { path += "M\(x + quiet) \(y + quiet)h1v1h-1z" }
            }
        }
        s += "  <path fill=\"\(foreground)\" d=\"\(path)\"/>\n</svg>"
        return s
    }

    public static func png(_ m: [[Bool]], foreground: RGBA, background: RGBA?, quiet: Int, size: Int, logo: CGImage?) throws -> Data {
        let n = m.count + quiet * 2
        let scale = max(1, size / n)
        let px = n * scale
        guard let ctx = ImageRender.context(width: px, height: px) else { throw ToolError("Render failure") }
        if let bg = background { ctx.setFillColor(ImageRender.cgColor(bg)); ctx.fill(CGRect(x: 0, y: 0, width: px, height: px)) }
        ctx.setFillColor(ImageRender.cgColor(foreground))
        for (y, row) in m.enumerated() {
            for (x, on) in row.enumerated() where on {
                ctx.fill(CGRect(x: (x + quiet) * scale, y: px - (y + quiet + 1) * scale, width: scale, height: scale))
            }
        }
        if let logo {
            let logoSize = CGFloat(px) * 0.22
            let rect = CGRect(x: (CGFloat(px) - logoSize) / 2, y: (CGFloat(px) - logoSize) / 2, width: logoSize, height: logoSize)
            ctx.setFillColor(ImageRender.cgColor(background ?? RGBA(r: 1, g: 1, b: 1)))
            ctx.fill(rect.insetBy(dx: -logoSize * 0.08, dy: -logoSize * 0.08))
            ctx.draw(logo, in: rect)
        }
        guard let img = ctx.makeImage(), let data = ImageRender.encode(img, format: .png) else { throw ToolError("PNG encoding failed") }
        return data
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        if options.mode == "read" || input.payload.kindName.hasPrefix("image") {
            let data = input.data
            guard !data.isEmpty else { throw ToolError("Drop or paste an image containing a QR code") }
            return try await Self.read(data)
        }
        let text = input.text
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let m = try Self.matrix(for: text, correction: options.correction)
        let fg = ColorParser.parse(options.foreground)?.0 ?? RGBA(r: 0, g: 0, b: 0)
        let bgRaw = options.background.trimmed().lowercased()
        let bg: RGBA? = bgRaw == "transparent" || bgRaw == "none" || bgRaw.isEmpty ? nil : ColorParser.parse(options.background)?.0
        var rows = [MetaRow("Modules", "\(m.count) × \(m.count) (version \((m.count - 17) / 4))"), MetaRow("Error correction", options.correction), MetaRow("Payload", "\(text.utf8.count) bytes")]
        if let bg, fg.contrast(with: bg) < 3 { rows.append(MetaRow("Warning", "Low contrast between foreground and background — scanners may fail", style: .warning)) }
        if options.format == "svg" {
            let svg = Self.svg(m, foreground: fg.hex, background: bg?.hex, quiet: options.quietZone, rounded: options.rounded, size: options.size)
            return ToolOutput(.image(Data(svg.utf8), .svg), facets: [OutputFacet("SVG source", text: svg, language: .xml)], metadata: rows, suggestedFileName: "qrcode.svg")
        }
        var logo: CGImage?
        if !options.logo.isEmpty {
            let l = options.logo.trimmed()
            if l.hasPrefix("data:"), let comma = l.firstIndex(of: ","), let d = Data(base64Encoded: String(l[l.index(after: comma)...])) { logo = ImageRender.cgImage(from: d) }
            else if let d = try? Data(contentsOf: URL(fileURLWithPath: (l as NSString).expandingTildeInPath)) { logo = ImageRender.cgImage(from: d) }
            if logo == nil { rows.append(MetaRow("Logo", "Could not load \(l)", style: .warning)) }
            else if options.correction != "H" { rows.append(MetaRow("Logo", "Use error correction H for reliable scanning with a logo", style: .warning)) }
        }
        let png = try Self.png(m, foreground: fg, background: bg, quiet: options.quietZone, size: options.size, logo: logo)
        rows.append(MetaRow("Image", "\(ByteFormatter.string(png.count)) PNG"))
        return ToolOutput(.image(png, .png), metadata: rows, suggestedFileName: "qrcode.png")
    }

    public static func read(_ data: Data, symbologies: [VNBarcodeSymbology]? = nil) async throws -> ToolOutput {
        guard let cg = ImageRender.cgImage(from: data) else { throw ToolError("Not a readable image") }
        let request = VNDetectBarcodesRequest()
        if let symbologies { request.symbologies = symbologies }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])
        let results = request.results ?? []
        guard !results.isEmpty else { throw ToolError("No barcode found in the image", hint: "Try a sharper or larger image") }
        var rows: [MetaRow] = []
        var texts: [String] = []
        for r in results {
            let payload = r.payloadStringValue ?? r.barcodeDescriptor.map { String(describing: $0) } ?? "(binary payload)"
            texts.append(payload)
            rows.append(MetaRow(r.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: ""), payload, style: .mono))
            rows.append(MetaRow("  Confidence", String(format: "%.0f%%", r.confidence * 100)))
            if let kind = classify(payload) { rows.append(MetaRow("  Content", kind)) }
        }
        return ToolOutput(text: texts.joined(separator: "\n"), metadata: rows)
    }

    static func classify(_ s: String) -> String? {
        if s.hasPrefix("WIFI:") { return "Wi-Fi network" + (s.captures("S:([^;]*)").map { " “\($0[1])”" } ?? "") }
        if s.hasPrefix("BEGIN:VCARD") { return "vCard contact" }
        if s.hasPrefix("BEGIN:VEVENT") || s.hasPrefix("BEGIN:VCALENDAR") { return "Calendar event" }
        if s.hasPrefix("mailto:") { return "Email address" }
        if s.hasPrefix("tel:") { return "Phone number" }
        if s.hasPrefix("sms:") || s.hasPrefix("SMSTO:") { return "SMS" }
        if s.hasPrefix("geo:") { return "Geo location" }
        if s.hasPrefix("otpauth://") { return "TOTP/HOTP secret (authenticator)" }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return "URL" }
        if s.hasPrefix("bitcoin:") || s.hasPrefix("ethereum:") { return "Crypto payment URI" }
        return nil
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.hasPrefix("WIFI:T:") || s.hasPrefix("otpauth://") { return DetectionScore(0.8, "QR payload") }
        return nil
    }
}
