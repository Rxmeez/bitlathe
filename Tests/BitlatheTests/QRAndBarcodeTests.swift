import XCTest
import CoreGraphics
import ImageIO
import BitlatheCore
@testable import BitlatheTools

final class QRAndBarcodeTests: XCTestCase {
    private func read(_ out: ToolOutput) async throws -> [String] {
        let result = try await TT.tool("qr.code").run(ToolInput(out.payload), options: [:])
        return result.text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private func imageSize(_ data: Data) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return (img.width, img.height)
    }

    // MARK: QR

    func testQRGenerateThenReadRoundTrip() async throws {
        let payloads = ["https://bitlathe.app", "WIFI:T:WPA;S:MyNetwork;P:secretpass;;", "héllo wörld ✓ 日本語", String(repeating: "lorem ipsum ", count: 20),
                        "BEGIN:VCARD\nVERSION:3.0\nN:Lovelace;Ada\nEND:VCARD"]
        for text in payloads {
            for level in ["L", "M", "Q", "H"] {
                let out = try await TT.run("qr.code", text, ["correction": .string(level), "size": .int(512)])
                guard case .image(let data, .png) = out.payload else { XCTFail("expected a PNG"); continue }
                XCTAssertEqual(imageSize(data)?.0, imageSize(data)?.1, "square")
                let decoded = try await read(out)
                XCTAssertEqual(decoded.joined(separator: "\n"), text, "level \(level)")
            }
        }
    }

    func testQRModuleCountsFollowTheSpecCapacityTable() throws {
        // 20 bytes of payload. Byte-mode capacities: v1 L17/M14/Q11/H7, v2 L32/M26/Q20/H14, v3 L53/M42/Q32/H24.
        let text = "https://bitlathe.app"
        XCTAssertEqual(text.utf8.count, 20)
        XCTAssertEqual(try QRCodeTool.matrix(for: text, correction: "L").count, 25)
        XCTAssertEqual(try QRCodeTool.matrix(for: text, correction: "M").count, 25)
        XCTAssertEqual(try QRCodeTool.matrix(for: text, correction: "Q").count, 25)
        XCTAssertEqual(try QRCodeTool.matrix(for: text, correction: "H").count, 29)
        XCTAssertEqual(try QRCodeTool.matrix(for: "HELLO", correction: "L").count, 21)
    }

    func testQRMatrixOrientation() throws {
        // Finder patterns must sit top-left, top-right and bottom-left (a vertically mirrored code is not scannable by every reader).
        let m = try QRCodeTool.matrix(for: "https://bitlathe.app", correction: "M")
        let n = m.count
        func finder(_ r0: Int, _ c0: Int) -> Bool {
            for r in 0..<7 { for c in 0..<7 {
                let expected = r == 0 || r == 6 || c == 0 || c == 6 || (2...4).contains(r) && (2...4).contains(c)
                if m[r0 + r][c0 + c] != expected { return false }
            } }
            return true
        }
        XCTAssertTrue(finder(0, 0), "top-left"); XCTAssertTrue(finder(0, n - 7), "top-right"); XCTAssertTrue(finder(n - 7, 0), "bottom-left")
        XCTAssertFalse(finder(n - 7, n - 7), "no finder at bottom-right")
        // Timing pattern alternates along row 6 and column 6 between the finders, starting dark.
        for c in 8..<(n - 8) { XCTAssertEqual(m[6][c], c % 2 == 0, "row timing col \(c)"); XCTAssertEqual(m[c][6], c % 2 == 0, "column timing row \(c)") }
        // Dark module at (4*version + 9, 8).
        XCTAssertTrue(m[4 * ((n - 17) / 4) + 9][8])
    }

    func testQRPNGPixelOrientation() async throws {
        let out = try await TT.run("qr.code", "https://bitlathe.app", ["size": .int(500), "quietZone": .int(4)])
        guard case .image(let data, _) = out.payload, let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return XCTFail() }
        let w = img.width, h = img.height
        var gray = [UInt8](repeating: 0, count: w * h)
        let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))   // memory row 0 is the top of the image
        let m = try QRCodeTool.matrix(for: "https://bitlathe.app", correction: "M")
        let n = m.count + 8
        let scale = 500 / n, offset = (max(500, n * scale) - m.count * scale) / 2
        var mismatches = 0
        for r in 0..<m.count { for c in 0..<m.count {
            let dark = gray[(offset + r * scale + scale / 2) * w + offset + c * scale + scale / 2] < 128
            if dark != m[r][c] { mismatches += 1 }
        } }
        XCTAssertEqual(mismatches, 0, "PNG pixels must reproduce the module matrix top-to-bottom")
    }

    func testQRSVGOutput() async throws {
        let out = try await TT.run("qr.code", "hello", ["format": .string("svg"), "foreground": .string("#112233"), "background": .string("transparent"), "quietZone": .int(4)])
        guard case .image(let data, .svg) = out.payload, let svg = String(data: data, encoding: .utf8) else { return XCTFail("expected SVG") }
        XCTAssertTrue(svg.contains("viewBox=\"0 0 29 29\""), "21 modules + 2×4 quiet zone")
        XCTAssertTrue(svg.contains("fill=\"#112233\""))
        XCTAssertFalse(svg.contains("<rect"), "transparent background draws no rect")
        let m = try QRCodeTool.matrix(for: "hello", correction: "M")
        XCTAssertEqual(svg.components(separatedBy: "h1v1h-1z").count - 1, m.flatMap { $0 }.filter { $0 }.count)
        XCTAssertNotNil(try? XMLDocument(data: data), "well-formed XML")
        XCTAssertEqual(out.suggestedFileName, "qrcode.svg")
    }

    func testQRSizeAndWarnings() async throws {
        let out = try await TT.run("qr.code", "size test", ["size": .int(256)])
        guard case .image(let data, _) = out.payload, let (w, h) = imageSize(data) else { return XCTFail() }
        XCTAssertGreaterThanOrEqual(w, 256); XCTAssertEqual(w, h)
        let low = try await TT.run("qr.code", "x", ["foreground": .string("#EEEEEE"), "background": .string("#FFFFFF")])
        XCTAssertEqual(TT.meta(low, "Warning")?.contains("Low contrast"), true)
        do { _ = try await TT.run("qr.code", ""); XCTFail("expected error") } catch { XCTAssertTrue(error is ToolError) }
        do { _ = try await TT.run("qr.code", String(repeating: "x", count: 4000)); XCTFail("expected error") } catch { XCTAssertTrue(error is ToolError) }
    }

    func testQRReadErrors() async {
        let blank = Data([0x89, 0x50, 0x4E, 0x47])
        do { _ = try await TT.tool("qr.code").run(ToolInput(.data(blank)), options: ["mode": .string("read")]); XCTFail("expected error") } catch { XCTAssertTrue(error is ToolError) }
    }

    func testQRContentClassification() {
        XCTAssertEqual(QRCodeTool.classify("WIFI:T:WPA;S:Cafe;P:x;;"), "Wi-Fi network “Cafe”")
        XCTAssertEqual(QRCodeTool.classify("BEGIN:VCARD\nEND:VCARD"), "vCard contact")
        XCTAssertEqual(QRCodeTool.classify("mailto:a@b.c"), "Email address")
        XCTAssertNil(QRCodeTool.classify("just text"))
    }

    // MARK: Barcode check digits and structure

    func testEANCheckDigits() throws {
        // Published examples: Wikipedia EAN-13 5901234123457, EAN-8 73513537, UPC-A 036000291452.
        XCTAssertEqual(BarcodeTool.eanChecksum("590123412345".compactMap(\.wholeNumberValue)), 7)
        XCTAssertEqual(BarcodeTool.eanChecksum("4006381333931".dropLast().compactMap(\.wholeNumberValue)), 1)
        XCTAssertEqual(BarcodeTool.eanChecksum("7351353".compactMap(\.wholeNumberValue)), 7)
        XCTAssertEqual(BarcodeTool.eanChecksum("03600029145".compactMap(\.wholeNumberValue)), 2)
        XCTAssertEqual(BarcodeTool.eanChecksum("000000000000".compactMap(\.wholeNumberValue)), 0)
        // A 12-digit input gets its check digit appended, a 13-digit one is validated.
        XCTAssertEqual(try BarcodeTool.ean("590123412345", length: 13).1, "5901234123457")
        XCTAssertEqual(try BarcodeTool.ean("5901234123457", length: 13).1, "5901234123457")
        XCTAssertEqual(try BarcodeTool.ean("7351353", length: 8).1, "73513537")
        XCTAssertThrowsError(try BarcodeTool.ean("5901234123458", length: 13))
        XCTAssertThrowsError(try BarcodeTool.ean("59012341234", length: 13))
        XCTAssertThrowsError(try BarcodeTool.ean("59012341234x", length: 13))
    }

    func testEANModuleStructure() throws {
        let (b13, _) = try BarcodeTool.ean("5901234123457", length: 13)
        XCTAssertEqual(b13.count, 95)
        let (b8, _) = try BarcodeTool.ean("73513537", length: 8)
        XCTAssertEqual(b8.count, 67)
        for bits in [b13, b8] {
            XCTAssertEqual(Array(bits.prefix(3)), [true, false, true]); XCTAssertEqual(Array(bits.suffix(3)), [true, false, true])
        }
        // Centre guard 01010 sits at modules 45…49 of EAN-13.
        XCTAssertEqual(Array(b13[45..<50]), [false, true, false, true, false])
        // Left-hand digit 5 uses parity LGGLLG; the first digit after the guard is "9" in L code: 0001011.
        XCTAssertEqual(b13[3..<10].map { $0 ? "1" : "0" }.joined(), BarcodeTool.eanL[9])
        XCTAssertEqual(b13[10..<17].map { $0 ? "1" : "0" }.joined(), BarcodeTool.eanG[0])
    }

    func testEAN13ThroughTool() async throws {
        let out = try await TT.run("barcode", "590123412345", ["symbology": .string("ean13")])
        XCTAssertEqual(TT.meta(out, "Encoded"), "5901234123457")
        XCTAssertEqual(TT.meta(out, "Modules"), "95")
        let upc = try await TT.run("barcode", "03600029145", ["symbology": .string("upca")])
        XCTAssertEqual(TT.meta(upc, "Encoded"), "036000291452")
        do { _ = try await TT.run("barcode", "5901234123450", ["symbology": .string("ean13")]); XCTFail("expected bad check digit") }
        catch let e as ToolError { XCTAssertTrue(e.message.contains("expected 7"), e.message) }
    }

    func testCode128Checksum() throws {
        // PJJ123C in code set B: (104 + 48*1 + 42*2 + 42*3 + 17*4 + 18*5 + 19*6 + 35*7) mod 103 = 879 mod 103 = 55.
        // (Wikipedia's worked example gives 54 because it starts in code set A, start value 103.)
        let bits = try BarcodeTool.code128("PJJ123C")
        let patterns = BarcodeTool.code128Patterns
        func symbols(_ b: [Bool]) -> [Int] {
            var out: [Int] = [], i = 0
            while i < b.count {
                let take = (b.count - i) == 13 ? 13 : 11
                let s = b[i..<(i + take)].map { $0 ? "1" : "0" }.joined()
                out.append(patterns.firstIndex(of: s)!)
                i += take
            }
            return out
        }
        let v = symbols(bits)
        XCTAssertEqual(v.first, 104)
        XCTAssertEqual(v.last, 106)
        XCTAssertEqual(v.dropFirst().dropLast().dropLast().map { $0 + 32 }.map { Character(UnicodeScalar($0)!) }.map(String.init).joined(), "PJJ123C")
        XCTAssertEqual(v[v.count - 2], 55)
        XCTAssertEqual(bits.count, 11 * 10 + 2, "start + 7 data + checksum + stop(13)")
        // Digit runs switch to code set C.
        let digits = symbols(try BarcodeTool.code128("123456"))
        XCTAssertEqual(digits, [105, 12, 34, 56, (105 + 12 * 1 + 34 * 2 + 56 * 3) % 103, 106])
        XCTAssertThrowsError(try BarcodeTool.code128("héllo"))
        XCTAssertThrowsError(try BarcodeTool.code128(""))
    }

    func testCode39Structure() throws {
        let bits = try BarcodeTool.code39Bits("A")
        // 3 characters (* A *), each 9 elements with three wide: 6 narrow + 3 wide(3) = 15 modules, plus 2 inter-character gaps.
        XCTAssertEqual(bits.count, 3 * 15 + 2)
        XCTAssertEqual(try BarcodeTool.code39Bits("a"), bits, "lower case is upper-cased")
        XCTAssertThrowsError(try BarcodeTool.code39Bits("a_b"))
    }

    // MARK: Barcode generate -> Vision read

    func testGeneratedBarcodesAreReadableByVision() async throws {
        let cases: [(symbology: String, input: String, expected: String)] = [
            ("ean13", "5901234123457", "5901234123457"),
            ("ean13", "4006381333931", "4006381333931"),
            ("ean8", "73513537", "73513537"),
            ("code128", "BITLATHE-2026", "BITLATHE-2026"),
            ("code128", "1234567890", "1234567890"),
            ("code128", "ab12345cd", "ab12345cd"),
            ("code39", "HELLO-123", "HELLO-123"),
            ("pdf417", "Hello from a PDF417 barcode", "Hello from a PDF417 barcode"),
            ("aztec", "Hello Aztec", "Hello Aztec"),
        ]
        for c in cases {
            let out = try await TT.run("barcode", c.input, ["symbology": .string(c.symbology), "scale": .int(4), "height": .int(160)])
            guard case .image(let data, .png) = out.payload else { XCTFail("PNG expected for \(c.symbology)"); continue }
            XCTAssertNotNil(imageSize(data))
            let decoded = try await TT.tool("barcode").run(ToolInput(out.payload), options: [:])
            XCTAssertEqual(decoded.text, c.expected, "\(c.symbology) \(c.input)")
        }
    }

    func testUPCAReadsBackAsEAN13WithLeadingZero() async throws {
        let out = try await TT.run("barcode", "03600029145", ["symbology": .string("upca"), "scale": .int(4)])
        let decoded = try await TT.tool("barcode").run(ToolInput(out.payload), options: [:])
        XCTAssertTrue(["036000291452", "0036000291452"].contains(decoded.text), decoded.text)
    }

    func testBarcodeSVGAndSizing() async throws {
        let out = try await TT.run("barcode", "5901234123457", ["symbology": .string("ean13"), "format": .string("svg"), "scale": .int(2), "height": .int(80), "showText": .bool(false)])
        guard case .image(let data, .svg) = out.payload, let svg = String(data: data, encoding: .utf8) else { return XCTFail() }
        XCTAssertTrue(svg.contains("width=\"\((95 + 20) * 2)\""), svg.prefix(200).description)
        XCTAssertNotNil(try? XMLDocument(data: data))
        XCTAssertFalse(svg.contains("<text"))
        let png = try await TT.run("barcode", "5901234123457", ["symbology": .string("ean13"), "scale": .int(3), "height": .int(100), "showText": .bool(false)])
        guard case .image(let pd, _) = png.payload else { return XCTFail() }
        XCTAssertEqual(imageSize(pd)?.0, (95 + 20) * 3); XCTAssertEqual(imageSize(pd)?.1, 100)
    }

    func testBarcodeDetect() {
        XCTAssertNotNil(BarcodeTool.detect("5901234123457"))
        XCTAssertNil(BarcodeTool.detect("5901234123458"))
    }
}
