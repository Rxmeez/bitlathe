import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import BitlatheCore
@testable import BitlatheTools

final class ImageConvertTests: XCTestCase {
    // MARK: helpers

    /// Opaque image, left half red and right half blue (or fully transparent with a green square when `transparent`).
    private func makeImage(width: Int, height: Int, transparent: Bool = false) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if transparent {
            ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        } else {
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        return ctx.makeImage()!
    }

    private func encode(_ image: CGImage, type: UTType, properties: [CFString: Any] = [:]) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    private func decode(_ data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    /// RGBA of the pixel at (x, y) counted from the top-left of the image.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(px[0]), Int(px[1]), Int(px[2]), Int(px[3]))
    }

    private func convert(_ data: Data, _ options: OptionValues) async throws -> (out: ToolOutput, image: CGImage, bytes: Data) {
        let out = try await TT.tool("image.convert").run(ToolInput(.image(data, ImageFormat.sniff(data) ?? .png)), options: options)
        guard case .image(let bytes, _) = out.payload, let img = decode(bytes) else { throw ToolError("no image output") }
        return (out, img, bytes)
    }

    private func isRed(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    private func isBlue(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }

    // MARK: format conversion

    func testFormatConversionsProduceTheRequestedContainer() async throws {
        let png = encode(makeImage(width: 64, height: 32), type: .png)
        XCTAssertEqual(ImageFormat.sniff(png), .png)
        for (format, expected) in [("jpeg", ImageFormat.jpeg), ("gif", .gif), ("tiff", .tiff), ("bmp", .bmp), ("png", .png)] {
            let r = try await convert(png, ["format": .string(format)])
            XCTAssertEqual(ImageFormat.sniff(r.bytes), expected, format)
            XCTAssertEqual(r.image.width, 64, format); XCTAssertEqual(r.image.height, 32, format)
            XCTAssertTrue(isRed(pixel(r.image, 5, 16)) || format == "gif", "\(format) left is red")
            XCTAssertTrue(isBlue(pixel(r.image, 58, 16)) || format == "gif", "\(format) right is blue")
        }
        let same = try await convert(encode(makeImage(width: 20, height: 10), type: .jpeg), [:])
        XCTAssertEqual(ImageFormat.sniff(same.bytes), .jpeg, "\"same\" keeps the source format")
    }

    func testOutputNamingAndMetadataRows() async throws {
        let png = encode(makeImage(width: 64, height: 32), type: .png)
        let out = try await TT.tool("image.convert").run(ToolInput(.image(png, .png), fileName: "photo.png"), options: ["format": .string("jpeg")])
        XCTAssertEqual(out.suggestedFileName, "photo.jpg")
        XCTAssertTrue(TT.meta(out, "Input")?.contains("PNG · 64 × 32") == true)
        XCTAssertTrue(TT.meta(out, "Output")?.contains("JPEG · 64 × 32") == true)
    }

    func testJPEGQualityAffectsSize() async throws {
        // A noisy image so that quality visibly changes the byte count.
        var rng = TT.SplitMix64(seed: 3)
        let w = 128, h = 128
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { pixels[i * 4] = UInt8.random(in: 0...255, using: &rng); pixels[i * 4 + 1] = UInt8.random(in: 0...255, using: &rng); pixels[i * 4 + 2] = UInt8.random(in: 0...255, using: &rng) }
        let img = pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
        let src = encode(img, type: .png)
        let low = try await convert(src, ["format": .string("jpeg"), "quality": .double(0.2)])
        let high = try await convert(src, ["format": .string("jpeg"), "quality": .double(0.95)])
        XCTAssertLessThan(low.bytes.count, high.bytes.count)
    }

    func testTransparencyIsFlattenedForJPEGAndKeptForPNG() async throws {
        let src = encode(makeImage(width: 40, height: 40, transparent: true), type: .png)
        let jpeg = try await convert(src, ["format": .string("jpeg")])
        let corner = pixel(jpeg.image, 1, 1)
        XCTAssertTrue(corner.r > 240 && corner.g > 240 && corner.b > 240, "white background by default: \(corner)")
        let centre = pixel(jpeg.image, 20, 20)
        XCTAssertTrue(centre.g > 200 && centre.r < 60, "content preserved: \(centre)")
        let custom = try await convert(src, ["format": .string("jpeg"), "background": .string("#000000")])
        let darkCorner = pixel(custom.image, 1, 1)
        XCTAssertTrue(darkCorner.r < 15 && darkCorner.g < 15 && darkCorner.b < 15, "custom flatten colour: \(darkCorner)")
        let png = try await convert(src, ["format": .string("png")])
        XCTAssertEqual(pixel(png.image, 1, 1).a, 0, "PNG keeps its transparency")
    }

    // MARK: resizing

    func testResizeModesGiveExpectedDimensions() async throws {
        let src = encode(makeImage(width: 200, height: 100), type: .png)
        let cases: [(OptionValues, Int, Int)] = [
            (["resizeMode": .string("width"), "width": .int(100)], 100, 50),
            (["resizeMode": .string("width"), "width": .int(333)], 333, 166),
            (["resizeMode": .string("width"), "width": .int(400)], 400, 200),
            (["resizeMode": .string("height"), "height": .int(25)], 50, 25),
            (["resizeMode": .string("height"), "height": .int(150)], 300, 150),
            (["resizeMode": .string("percent"), "percent": .int(50)], 100, 50),
            (["resizeMode": .string("percent"), "percent": .int(150)], 300, 150),
            (["resizeMode": .string("percent"), "percent": .int(1)], 2, 1),
            (["resizeMode": .string("exact"), "width": .int(30), "height": .int(70)], 30, 70),
            (["resizeMode": .string("fit"), "width": .int(100), "height": .int(100)], 100, 50),
            (["resizeMode": .string("fit"), "width": .int(1000), "height": .int(20)], 40, 20),
            (["resizeMode": .string("fit"), "width": .int(4000), "height": .int(4000)], 200, 100),   // never upscales
            (["resizeMode": .string("none")], 200, 100),
        ]
        for (opts, w, h) in cases {
            let r = try await convert(src, opts)
            XCTAssertEqual(r.image.width, w, "\(opts)"); XCTAssertEqual(r.image.height, h, "\(opts)")
            XCTAssertTrue(TT.meta(r.out, "Output")?.contains("\(w) × \(h)") == true, "\(opts)")
        }
    }

    func testResizePreservesContent() async throws {
        let src = encode(makeImage(width: 200, height: 100), type: .png)
        let r = try await convert(src, ["resizeMode": .string("width"), "width": .int(50)])
        XCTAssertTrue(isRed(pixel(r.image, 5, 12))); XCTAssertTrue(isBlue(pixel(r.image, 44, 12)))
    }

    // MARK: orientation and metadata

    /// 40×20 image: top-left red, top-right green, bottom-left blue, bottom-right yellow.
    private func quadrantImage() -> CGImage {
        let w = 40, h = 20
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CoreGraphics origin is bottom-left, so the "top" quadrants have the larger y.
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h / 2))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2))
        return ctx.makeImage()!
    }

    private func letter(_ p: (r: Int, g: Int, b: Int, a: Int)) -> String {
        switch (p.r > 200, p.g > 200, p.b > 200) {
        case (true, false, false): "R"
        case (false, true, false): "G"
        case (false, false, true): "B"
        case (true, true, false): "Y"
        default: "?"
        }
    }

    private func quadrants(_ i: CGImage) -> [String] {
        let w = i.width, h = i.height
        return [pixel(i, w / 4, h / 4), pixel(i, 3 * w / 4, h / 4), pixel(i, w / 4, 3 * h / 4), pixel(i, 3 * w / 4, 3 * h / 4)].map(letter)
    }

    func testPixelHelperOrientationSanity() {
        XCTAssertEqual(quadrants(quadrantImage()), ["R", "G", "B", "Y"], "TL, TR, BL, BR")
    }

    func testEXIFOrientationIsApplied() async throws {
        // Expected quadrants [TL, TR, BL, BR] after applying each EXIF orientation to R G / B Y (see the EXIF spec table).
        let expected: [Int: [String]] = [1: ["R", "G", "B", "Y"], 2: ["G", "R", "Y", "B"], 3: ["Y", "B", "G", "R"], 4: ["B", "Y", "R", "G"],
                                         5: ["R", "B", "G", "Y"], 6: ["B", "R", "Y", "G"], 7: ["Y", "G", "B", "R"], 8: ["G", "Y", "R", "B"]]
        for orientation in 1...8 {
            let jpeg = encode(quadrantImage(), type: .png, properties: [kCGImagePropertyOrientation: orientation])
            let source = CGImageSourceCreateWithData(jpeg as CFData, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }
            XCTAssertEqual(source?[kCGImagePropertyOrientation as String] as? Int ?? 1, orientation, "fixture carries orientation \(orientation)")
            let r = try await convert(jpeg, ["format": .string("png")])
            XCTAssertEqual(r.image.width, orientation >= 5 ? 20 : 40, "orientation \(orientation) width")
            XCTAssertEqual(r.image.height, orientation >= 5 ? 40 : 20, "orientation \(orientation) height")
            XCTAssertEqual(quadrants(r.image), expected[orientation], "orientation \(orientation)")
        }
    }

    func testMetadataStrippedOrPreserved() async throws {
        let props: [CFString: Any] = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "BitlatheCam", kCGImagePropertyTIFFModel: "T-1"],
                                      kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret note"]]
        let src = encode(makeImage(width: 32, height: 32), type: .jpeg, properties: props)
        func make(_ data: Data) -> String? {
            let p = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }
            return (p?[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFMake as String] as? String
        }
        XCTAssertEqual(make(src), "BitlatheCam", "fixture really carries metadata")
        let stripped = try await convert(src, ["stripMetadata": .bool(true)])
        XCTAssertNil(make(stripped.bytes))
        XCTAssertEqual(TT.meta(stripped.out, "Metadata"), "Stripped")
        let kept = try await convert(src, ["stripMetadata": .bool(false)])
        XCTAssertEqual(make(kept.bytes), "BitlatheCam")
    }

    func testErrors() async {
        for payload in [Data(), Data("not an image".utf8)] {
            do { _ = try await TT.tool("image.convert").run(ToolInput(.data(payload)), options: [:]); XCTFail("expected error") } catch { XCTAssertTrue(error is ToolError) }
        }
    }
}
