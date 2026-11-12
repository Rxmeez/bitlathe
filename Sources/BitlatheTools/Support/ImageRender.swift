import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import BitlatheCore

/// CoreGraphics / CoreImage helpers shared by the image tools (no AppKit so engines stay UI-free).
enum ImageRender {
    static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    static func encode(_ image: CGImage, format: ImageFormat, quality: Double = 0.9, properties: [CFString: Any] = [:]) -> Data? {
        let uti: CFString
        switch format {
        case .png: uti = UTType.png.identifier as CFString
        case .jpeg: uti = UTType.jpeg.identifier as CFString
        case .gif: uti = UTType.gif.identifier as CFString
        case .tiff: uti = UTType.tiff.identifier as CFString
        case .bmp: uti = UTType.bmp.identifier as CFString
        case .heic: uti = UTType.heic.identifier as CFString
        case .webp: uti = UTType.webP.identifier as CFString
        case .avif: uti = "public.avif" as CFString
        default: uti = UTType.png.identifier as CFString
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, uti, 1, nil) else { return nil }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        for (k, v) in properties { props[k] = v }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    static var writableFormats: Set<ImageFormat> {
        let ids = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        var out: Set<ImageFormat> = [.png, .jpeg, .gif, .tiff, .bmp]
        if ids.contains(UTType.heic.identifier) { out.insert(.heic) }
        if ids.contains(UTType.webP.identifier) { out.insert(.webp) }
        if ids.contains("public.avif") { out.insert(.avif) }
        return out
    }

    static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)   // swiftlint:disable:this force_unwrapping
    }

    static func resized(_ image: CGImage, to size: CGSize, interpolation: CGInterpolationQuality = .high) -> CGImage? {
        guard let ctx = context(width: Int(size.width), height: Int(size.height)) else { return nil }
        ctx.interpolationQuality = interpolation
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    static func cgColor(_ c: RGBA) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [c.clamped.r, c.clamped.g, c.clamped.b, c.a])!   // swiftlint:disable:this force_unwrapping
    }

    static func render(ciImage: CIImage) -> CGImage? {
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(ciImage, from: ciImage.extent)
    }

    /// Draws text centred in a context using CoreText.
    static func drawText(_ text: String, in rect: CGRect, context: CGContext, fontSize: CGFloat, color: CGColor, fontName: String = "Helvetica-Bold") {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: rect.midX - bounds.width / 2 - bounds.minX, y: rect.midY - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
