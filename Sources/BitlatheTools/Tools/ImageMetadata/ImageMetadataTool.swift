import Foundation
import ImageIO
import BitlatheCore

public struct ImageMetadataTool: DevTool {
    public static let id = "image.exif"
    public static let name = "Image Metadata"
    public static let summary = "EXIF, GPS, TIFF, IPTC and colour profile data from any image — and a stripped copy"
    public static let category = ToolCategory.inspect
    public static let symbol = "camera.metering.matrix"
    public static let keywords = ["exif", "metadata", "image", "photo", "gps", "camera", "iptc", "strip", "privacy", "dimensions", "dpi"]
    public static let io = ToolIO(input: .image, output: .text, acceptsFiles: true, outputLanguage: .json)
    public static let optionFields: [OptionField] = [
        .segmented("output", "Output", [.init("json", "Metadata JSON"), .init("strip", "Stripped image")], default: "json"),
    ]
    public struct Options: ToolOptions {
        public var output = "json"
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let data = input.data
        guard !data.isEmpty else { throw ToolError("Drop an image or paste one", hint: "PNG, JPEG, HEIC, TIFF, WebP, GIF…") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { throw ToolError("Not a readable image") }
        let props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        let typeID = CGImageSourceGetType(source) as String? ?? "?"
        var rows: [MetaRow] = []
        if let name = input.fileName { rows.append(MetaRow("File", name)) }
        rows.append(MetaRow("Type", typeID))
        rows.append(MetaRow("Size", ByteFormatter.string(data.count)))
        if let w = props[kCGImagePropertyPixelWidth as String] as? Int, let h = props[kCGImagePropertyPixelHeight as String] as? Int {
            rows.append(MetaRow("Dimensions", "\(w) × \(h) px (\(Self.aspect(w, h)))"))
            if let dpi = props[kCGImagePropertyDPIWidth as String] as? Double, dpi > 0 { rows.append(MetaRow("Resolution", String(format: "%.0f dpi · %.2f × %.2f in", dpi, Double(w) / dpi, Double(h) / dpi))) }
        }
        if let depth = props[kCGImagePropertyDepth as String] as? Int { rows.append(MetaRow("Bit depth", "\(depth)")) }
        if let model = props[kCGImagePropertyColorModel as String] as? String { rows.append(MetaRow("Colour model", model)) }
        if let profile = props[kCGImagePropertyProfileName as String] as? String { rows.append(MetaRow("Colour profile", profile)) }
        if let alpha = props[kCGImagePropertyHasAlpha as String] as? Bool { rows.append(MetaRow("Alpha", alpha ? "Yes" : "No")) }
        if let o = props[kCGImagePropertyOrientation as String] as? Int { rows.append(MetaRow("Orientation", "\(o) — \(Self.orientation(o))")) }
        let count = CGImageSourceGetCount(source)
        if count > 1 { rows.append(MetaRow("Frames", "\(count)")) }
        var warnings: [String] = []
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            rows.append(MetaRow("── EXIF", "", style: .muted))
            let keys: [(String, String)] = [(kCGImagePropertyExifDateTimeOriginal as String, "Taken"), (kCGImagePropertyExifLensModel as String, "Lens"), (kCGImagePropertyExifFocalLength as String, "Focal length"),
                                            (kCGImagePropertyExifFocalLenIn35mmFilm as String, "Focal (35mm eq.)"), (kCGImagePropertyExifFNumber as String, "Aperture ƒ/"), (kCGImagePropertyExifExposureTime as String, "Exposure"),
                                            (kCGImagePropertyExifISOSpeedRatings as String, "ISO"), (kCGImagePropertyExifExposureBiasValue as String, "Exposure bias"), (kCGImagePropertyExifFlash as String, "Flash"),
                                            (kCGImagePropertyExifWhiteBalance as String, "White balance"), (kCGImagePropertyExifMeteringMode as String, "Metering"), (kCGImagePropertyExifExposureProgram as String, "Program"),
                                            (kCGImagePropertyExifUserComment as String, "Comment"), (kCGImagePropertyExifBodySerialNumber as String, "Body serial"), (kCGImagePropertyExifLensSerialNumber as String, "Lens serial"),
                                            (kCGImagePropertyExifSubjectDistance as String, "Subject distance"), (kCGImagePropertyExifColorSpace as String, "EXIF colour space"), (kCGImagePropertyExifOffsetTimeOriginal as String, "Time zone")]
            for (k, label) in keys {
                if let v = exif[k] {
                    var s = Self.describe(v)
                    if k == kCGImagePropertyExifExposureTime as String, let d = v as? Double, d < 1, d > 0 { s = "1/\(Int((1 / d).rounded())) s" }
                    rows.append(MetaRow(label, s))
                }
            }
            if exif[kCGImagePropertyExifBodySerialNumber as String] != nil { warnings.append("Contains camera serial number") }
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            rows.append(MetaRow("── TIFF", "", style: .muted))
            for (k, label) in [(kCGImagePropertyTIFFMake as String, "Make"), (kCGImagePropertyTIFFModel as String, "Camera"), (kCGImagePropertyTIFFSoftware as String, "Software"), (kCGImagePropertyTIFFDateTime as String, "Modified"),
                               (kCGImagePropertyTIFFArtist as String, "Artist"), (kCGImagePropertyTIFFCopyright as String, "Copyright"), (kCGImagePropertyTIFFImageDescription as String, "Description")] {
                if let v = tiff[k] { rows.append(MetaRow(label, Self.describe(v))) }
            }
        }
        if let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            rows.append(MetaRow("── GPS", "", style: .muted))
            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double, let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double {
                let latRef = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String) == "S" ? -1.0 : 1.0
                let lonRef = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String) == "W" ? -1.0 : 1.0
                let la = lat * latRef, lo = lon * lonRef
                rows.append(MetaRow("Coordinates", String(format: "%.6f, %.6f", la, lo), style: .danger))
                rows.append(MetaRow("Map", "https://maps.apple.com/?ll=\(la),\(lo)&q=Photo", style: .mono))
                warnings.append("Contains GPS location — strip before sharing")
            }
            if let alt = gps[kCGImagePropertyGPSAltitude as String] as? Double { rows.append(MetaRow("Altitude", String(format: "%.1f m", alt))) }
            if let d = gps[kCGImagePropertyGPSDateStamp as String] as? String { rows.append(MetaRow("GPS date", d + " " + ((gps[kCGImagePropertyGPSTimeStamp as String] as? String) ?? ""))) }
            if let sp = gps[kCGImagePropertyGPSSpeed as String] as? Double { rows.append(MetaRow("Speed", String(format: "%.1f %@", sp, (gps[kCGImagePropertyGPSSpeedRef as String] as? String) ?? ""))) }
        }
        if let iptc = props[kCGImagePropertyIPTCDictionary as String] as? [String: Any], !iptc.isEmpty {
            rows.append(MetaRow("── IPTC", "", style: .muted))
            for (k, v) in iptc.sorted(by: { $0.key < $1.key }) { rows.append(MetaRow(k, Self.describe(v))) }
        }
        if let png = props[kCGImagePropertyPNGDictionary as String] as? [String: Any], !png.isEmpty {
            rows.append(MetaRow("── PNG", "", style: .muted))
            for (k, v) in png.sorted(by: { $0.key < $1.key }) { rows.append(MetaRow(k, Self.describe(v))) }
        }
        if let gif = props[kCGImagePropertyGIFDictionary as String] as? [String: Any], !gif.isEmpty {
            rows.append(MetaRow("── GIF", "", style: .muted))
            for (k, v) in gif.sorted(by: { $0.key < $1.key }) { rows.append(MetaRow(k, Self.describe(v))) }
        }
        if let maker = props[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any], !maker.isEmpty { rows.append(MetaRow("Apple maker note", "\(maker.count) entries")) }
        if options.output == "strip" {
            let format = ImageFormat.sniff(data) ?? .png
            let uti = (format == .jpeg ? "public.jpeg" : (format == .heic ? "public.heic" : "public.png")) as CFString
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, uti, 1, nil), let img = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ToolError("Could not re-encode image") }
            let orientation = props[kCGImagePropertyOrientation as String] as? Int ?? 1
            CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.92, kCGImagePropertyOrientation: orientation] as CFDictionary)
            CGImageDestinationFinalize(dest)
            let stripped = out as Data
            rows.insert(MetaRow("Stripped", "\(ByteFormatter.string(data.count)) → \(ByteFormatter.string(stripped.count)), metadata removed", style: .success), at: 0)
            return ToolOutput(.image(stripped, format == .jpeg ? .jpeg : (format == .heic ? .heic : .png)), metadata: rows, warnings: [], suggestedFileName: ((input.fileName ?? "image") as NSString).deletingPathExtension + "-stripped." + (format == .jpeg ? "jpg" : (format == .heic ? "heic" : "png")))
        }
        let json = JSONValue(foundation: Self.sanitize(props))
        return ToolOutput(text: JSONSerializer.string(json), language: .json, metadata: rows, warnings: warnings)
    }

    static func sanitize(_ any: Any) -> Any {
        switch any {
        case let d as [String: Any]: return d.mapValues(sanitize)
        case let a as [Any]: return a.map(sanitize)
        case let data as Data: return "<\(data.count) bytes>"
        case let n as NSNumber: return n
        case let s as String: return s
        case let date as Date: return ISO8601DateFormatter().string(from: date)
        default: return String(describing: any)
        }
    }

    static func describe(_ v: Any) -> String {
        switch v {
        case let d as Double: return d == d.rounded() ? String(Int(d)) : String(format: "%.3g", d)
        case let a as [Any]: return a.map(describe).joined(separator: ", ")
        case let n as NSNumber: return n.stringValue
        default: return String(describing: v)
        }
    }

    static func aspect(_ w: Int, _ h: Int) -> String {
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let g = max(gcd(w, h), 1)
        let rw = w / g, rh = h / g
        if rw > 50 || rh > 50 { return String(format: "%.2f:1", Double(w) / Double(h)) }
        return "\(rw):\(rh)"
    }

    static func orientation(_ o: Int) -> String {
        ["", "Normal", "Mirrored horizontal", "Rotated 180°", "Mirrored vertical", "Mirrored + rotated 90° CCW", "Rotated 90° CW", "Mirrored + rotated 90° CW", "Rotated 90° CCW"][min(max(o, 0), 8)]
    }
}
