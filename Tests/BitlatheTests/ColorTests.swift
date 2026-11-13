import XCTest
import BitlatheCore
@testable import BitlatheTools

final class ColorTests: XCTestCase {
    private func rgb(_ hex: String) -> RGBA { ColorParser.parseHex(hex)! }

    private func assertClose(_ a: RGBA, _ b: RGBA, tolerance: Double = 1.0 / 255, _ msg: String = "", line: UInt = #line) {
        XCTAssertEqual(a.r, b.r, accuracy: tolerance, "r \(msg)", line: line)
        XCTAssertEqual(a.g, b.g, accuracy: tolerance, "g \(msg)", line: line)
        XCTAssertEqual(a.b, b.b, accuracy: tolerance, "b \(msg)", line: line)
    }

    private let samples = ["#000000", "#FFFFFF", "#FF0000", "#00FF00", "#0000FF", "#3D7BFF", "#663399", "#808080", "#FFA500", "#123456", "#FEDCBA", "#7F3F1F", "#01FE80"]

    func testHexParsing() {
        XCTAssertEqual(ColorParser.parse("#fff")?.0.hex, "#FFFFFF")
        XCTAssertEqual(ColorParser.parse("#f008")?.0.hex, "#FF000088")
        XCTAssertEqual(ColorParser.parse("3d7bff")?.0.hex, "#3D7BFF")
        XCTAssertEqual(ColorParser.parse("0x3D7BFF")?.0.hex, "#3D7BFF")
        XCTAssertEqual(ColorParser.parse("#3D7BFF80")?.0.a ?? 0, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(ColorParser.parse("rebeccapurple")?.0.hex, "#663399")
        XCTAssertNil(ColorParser.parse("#12"))
        XCTAssertNil(ColorParser.parse("#GGGGGG"))
    }

    func testFunctionalNotations() {
        XCTAssertEqual(ColorParser.parse("rgb(255, 0, 0)")?.0.hex, "#FF0000")
        XCTAssertEqual(ColorParser.parse("rgb(61 123 255)")?.0.hex, "#3D7BFF")
        XCTAssertEqual(ColorParser.parse("rgb(100% 0% 0%)")?.0.hex, "#FF0000")
        XCTAssertEqual(ColorParser.parse("hsl(120 100% 50%)")?.0.hex, "#00FF00")
        XCTAssertEqual(ColorParser.parse("hsl(270, 50%, 40%)")?.0.hex, "#663399")
        XCTAssertEqual(ColorParser.parse("cmyk(0%, 100%, 100%, 0%)")?.0.hex, "#FF0000")
        XCTAssertEqual(ColorParser.parse("oklch(62.8% 0.2577 29.23)")?.0.hex, "#FF0000")
        XCTAssertEqual(ColorParser.parse("color(srgb 1 0 0)")?.0.hex, "#FF0000")
        XCTAssertEqual(ColorParser.parse("Color(red: 1, green: 0, blue: 0)")?.0.hex, "#FF0000")
        XCTAssertEqual(ColorParser.parse("rgba(255, 0, 0, 0.5)")?.0.a ?? 0, 0.5, accuracy: 1e-9)
    }

    func testPrimaryHSLValues() {
        let red = rgb("#FF0000").hsl
        XCTAssertEqual(red.h, 0, accuracy: 1e-9); XCTAssertEqual(red.s, 1, accuracy: 1e-9); XCTAssertEqual(red.l, 0.5, accuracy: 1e-9)
        let purple = rgb("#663399").hsl    // CSS rebeccapurple = hsl(270 50% 40%)
        XCTAssertEqual(purple.h, 270, accuracy: 1e-6); XCTAssertEqual(purple.s, 0.5, accuracy: 1e-6); XCTAssertEqual(purple.l, 0.4, accuracy: 1e-6)
        let cmyk = rgb("#FF0000").cmyk
        XCTAssertEqual([cmyk.c, cmyk.m, cmyk.y, cmyk.k], [0, 1, 1, 0])
    }

    func testOKLCHPublishedValues() {
        // CSS Color Module 4 reference conversions of sRGB primaries.
        let red = rgb("#FF0000").oklch
        XCTAssertEqual(red.l, 0.628, accuracy: 0.001); XCTAssertEqual(red.c, 0.2577, accuracy: 0.001); XCTAssertEqual(red.h, 29.23, accuracy: 0.1)
        let green = rgb("#00FF00").oklch
        XCTAssertEqual(green.l, 0.8664, accuracy: 0.001); XCTAssertEqual(green.c, 0.2948, accuracy: 0.001); XCTAssertEqual(green.h, 142.5, accuracy: 0.1)
        let blue = rgb("#0000FF").oklch
        XCTAssertEqual(blue.l, 0.452, accuracy: 0.001); XCTAssertEqual(blue.c, 0.313, accuracy: 0.001); XCTAssertEqual(blue.h, 264.05, accuracy: 0.1)
        let white = rgb("#FFFFFF").oklch
        XCTAssertEqual(white.l, 1, accuracy: 0.001); XCTAssertEqual(white.c, 0, accuracy: 0.001)
        XCTAssertEqual(rgb("#FFFFFF").lab.l, 100, accuracy: 0.05)
        XCTAssertEqual(rgb("#000000").lab.l, 0, accuracy: 0.05)
    }

    func testRoundTripsThroughEveryModel() {
        for hex in samples {
            let c = rgb(hex)
            let hsl = c.hsl; assertClose(RGBA.fromHSL(h: hsl.h, s: hsl.s, l: hsl.l), c, tolerance: 1e-9, "HSL \(hex)")
            let hsb = c.hsb; assertClose(RGBA.fromHSB(h: hsb.h, s: hsb.s, b: hsb.b), c, tolerance: 1e-9, "HSB \(hex)")
            let k = c.cmyk; assertClose(RGBA.fromCMYK(c: k.c, m: k.m, y: k.y, k: k.k), c, tolerance: 1e-9, "CMYK \(hex)")
            let ok = c.oklch; assertClose(RGBA.fromOKLCH(l: ok.l, c: ok.c, h: ok.h), c, tolerance: 0.002, "OKLCH \(hex)")
            let lab = c.lab; assertClose(RGBA.fromLab(l: lab.l, a: lab.a, b: lab.b), c, tolerance: 0.002, "Lab \(hex)")
            let p3 = c.displayP3; assertClose(RGBA.fromDisplayP3(r: p3.r, g: p3.g, b: p3.b), c, tolerance: 0.002, "P3 \(hex)")
            let x = c.xyz; assertClose(RGBA.fromXYZ(x.x, x.y, x.z), c, tolerance: 0.002, "XYZ \(hex)")
            // And through the textual formats the tool emits.
            for (name, text) in ColorTool.formats(c) where ["HEX", "RGB", "RGB (modern)", "HSL", "OKLCH"].contains(name) {
                guard let back = ColorParser.parse(text)?.0 else { XCTFail("\(name) \(text) did not reparse"); continue }
                assertClose(back, c, tolerance: name == "HSL" || name == "OKLCH" ? 0.01 : 1e-9, "\(name) text \(hex)")
            }
        }
    }

    func testWCAGContrast() {
        let white = rgb("#FFFFFF"), black = rgb("#000000")
        XCTAssertEqual(black.contrast(with: white), 21, accuracy: 1e-9)
        XCTAssertEqual(white.contrast(with: white), 1, accuracy: 1e-9)
        XCTAssertEqual(rgb("#777777").contrast(with: white), 4.48, accuracy: 0.005)
        XCTAssertEqual(rgb("#767676").contrast(with: white), 4.54, accuracy: 0.005)
        XCTAssertEqual(rgb("#595959").contrast(with: white), 7.0, accuracy: 0.01)
        XCTAssertEqual(white.contrast(with: rgb("#777777")), rgb("#777777").contrast(with: white), accuracy: 1e-12, "symmetric")
    }

    func testToolOutputAndContrastGrades() async throws {
        let out = try await TT.run("color.convert", "#777")
        XCTAssertEqual(TT.meta(out, "Contrast vs #FFFFFF"), "4.48 : 1")
        XCTAssertEqual(TT.meta(out, "Normal text (AA 4.5, AAA 7)"), "Fail")
        XCTAssertEqual(TT.meta(out, "Large text (AA 3, AAA 4.5)"), "AA")
        XCTAssertEqual(TT.meta(out, "HEX"), "#777777")
        let dark = try await TT.run("color.convert", "#595959", ["against": .string("#FFFFFF")])
        XCTAssertEqual(TT.meta(dark, "Normal text (AA 4.5, AAA 7)"), "AAA")
        let onBlack = try await TT.run("color.convert", "#FFFFFF", ["against": .string("#000")])
        XCTAssertEqual(TT.meta(onBlack, "Contrast vs #000000"), "21.00 : 1")
        let r = try await TT.run("color.convert", "rgb(255 0 0)")
        XCTAssertEqual(TT.meta(r, "HEX"), "#FF0000")
        let g = try await TT.run("color.convert", "hsl(120 100% 50%)")
        XCTAssertEqual(TT.meta(g, "RGB"), "rgb(0, 255, 0)")
    }

    func testPaletteHasExpectedStops() async throws {
        let tints = ColorTool.palette(rgb("#3D7BFF"), kind: "tints")
        XCTAssertEqual(tints.count, 9)
        XCTAssertEqual(tints[4].1.hex, "#3D7BFF")
        XCTAssertEqual(ColorTool.palette(rgb("#3D7BFF"), kind: "scale").count, 11)   // 50…950
        XCTAssertEqual(ColorTool.palette(rgb("#3D7BFF"), kind: "harmony").count, 10)
    }

    func testMultiLineAndErrors() async throws {
        let out = try await TT.run("color.convert", "#fff\nred\nnotacolor")
        XCTAssertTrue(out.text.contains("#FFFFFF") && out.text.contains("#FF0000") && out.text.contains("?"))
        do { _ = try await TT.run("color.convert", "banana-colour"); XCTFail("expected error") } catch { XCTAssertTrue(error is ToolError) }
    }

    func testDetect() {
        XCTAssertNotNil(ColorTool.detect("#3D7BFF")); XCTAssertNotNil(ColorTool.detect("oklch(70% 0.15 250)")); XCTAssertNotNil(ColorTool.detect("rgb(1, 2, 3)"))
        XCTAssertNil(ColorTool.detect("hello"))
    }
}
