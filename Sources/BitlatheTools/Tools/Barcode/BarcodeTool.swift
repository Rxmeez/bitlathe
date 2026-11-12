import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import BitlatheCore

public struct BarcodeTool: DevTool {
    public static let id = "barcode"
    public static let name = "Barcode"
    public static let summary = "Generate Code 128, Code 39, EAN-13, EAN-8, UPC-A, PDF417 and Aztec barcodes, or read any barcode from an image"
    public static let category = ToolCategory.generate
    public static let symbol = "barcode"
    public static let keywords = ["barcode", "code128", "code39", "ean", "ean13", "upc", "pdf417", "aztec", "generate", "scan", "read"]
    public static let io = ToolIO(input: .text, output: .image, acceptsFiles: true)
    public static let samples = [ToolSample("Code 128", "BITLATHE-2026"), ToolSample("EAN-13", "5901234123457", options: ["symbology": .string("ean13")]), ToolSample("PDF417", "Hello from a PDF417 barcode", options: ["symbology": .string("pdf417")])]
    public static let optionFields: [OptionField] = [
        .mode([.init("generate", "Generate"), .init("read", "Read")], default: "generate"),
        .picker("symbology", "Symbology", [.init("code128", "Code 128"), .init("code39", "Code 39"), .init("ean13", "EAN-13"), .init("ean8", "EAN-8"), .init("upca", "UPC-A"), .init("pdf417", "PDF417"), .init("aztec", "Aztec")], default: "code128", visibleWhen: ("mode", ["generate"])),
        .stepper("height", "Height px", min: 40, max: 600, step: 10, default: 160, visibleWhen: ("mode", ["generate"])),
        .stepper("scale", "Module px", min: 1, max: 12, default: 4, visibleWhen: ("mode", ["generate"])),
        .toggle("showText", "Human-readable text", default: true, visibleWhen: ("symbology", ["code128", "code39", "ean13", "ean8", "upca"])),
        .segmented("format", "Format", [.init("png", "PNG"), .init("svg", "SVG")], default: "png", visibleWhen: ("mode", ["generate"])),
    ]
    public struct Options: ToolOptions {
        public var mode = "generate"
        public var symbology = "code128"
        public var height = 160
        public var scale = 4
        public var showText = true
        public var format = "png"
        public init() {}
    }
    public init() {}

    // MARK: 1D encoders → module bit arrays

    static let code128Patterns: [String] = [
        "11011001100", "11001101100", "11001100110", "10010011000", "10010001100", "10001001100", "10011001000", "10011000100", "10001100100", "11001001000", "11001000100", "11000100100", "10110011100", "10011011100", "10011001110", "10111001100", "10011101100", "10011100110", "11001110010", "11001011100",
        "11001001110", "11011100100", "11001110100", "11101101110", "11101001100", "11100101100", "11100100110", "11101100100", "11100110100", "11100110010", "11011011000", "11011000110", "11000110110", "10100011000", "10001011000", "10001000110", "10110001000", "10001101000", "10001100010", "11010001000",
        "11000101000", "11000100010", "10110111000", "10110001110", "10001101110", "10111011000", "10111000110", "10001110110", "11101110110", "11010001110", "11000101110", "11011101000", "11011100010", "11011101110", "11101011000", "11101000110", "11100010110", "11101101000", "11101100010", "11100011010",
        "11101111010", "11001000010", "11110001010", "10100110000", "10100001100", "10010110000", "10010000110", "10000101100", "10000100110", "10110010000", "10110000100", "10011010000", "10011000010", "10000110100", "10000110010", "11000010010", "11001010000", "11110111010", "11000010100", "10001111010",
        "10100111100", "10010111100", "10010011110", "10111100100", "10011110100", "10011110010", "11110100100", "11110010100", "11110010010", "11011011110", "11011110110", "11110110110", "10101111000", "10100011110", "10001011110", "10111101000", "10111100010", "11110101000", "11110100010", "10111011110",
        "10111101110", "11101011110", "11110101110", "11010000100", "11010010000", "11010011100", "1100011101011",
    ]

    static func code128(_ text: String) throws -> [Bool] {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) else { throw ToolError("Code 128 (set B) supports printable ASCII only") }
        var values: [Int] = []
        // Use Code Set C for runs of 4+ digits for compactness, else set B.
        let chars = Array(text)
        var i = 0
        var setC = false
        var first = true
        while i < chars.count {
            var digitRun = 0
            while i + digitRun < chars.count, chars[i + digitRun].isNumber { digitRun += 1 }
            if digitRun >= 4 || (digitRun >= 2 && i + digitRun == chars.count && setC) {
                if first { values.append(105); first = false; setC = true } else if !setC { values.append(99); setC = true }
                let even = digitRun - digitRun % 2
                for k in stride(from: 0, to: even, by: 2) { values.append(Int(String(chars[i + k...i + k + 1]))!) }   // swiftlint:disable:this force_unwrapping
                i += even
                continue
            }
            if first { values.append(104); first = false; setC = false } else if setC { values.append(100); setC = false }
            values.append(Int(chars[i].asciiValue!) - 32)   // swiftlint:disable:this force_unwrapping
            i += 1
        }
        var checksum = values[0]
        for (idx, v) in values.dropFirst().enumerated() { checksum += v * (idx + 1) }
        values.append(checksum % 103)
        values.append(106)
        return values.flatMap { code128Patterns[$0].map { $0 == "1" } }
    }

    static let code39: [Character: String] = [
        "0": "nnnwwnwnn", "1": "wnnwnnnnw", "2": "nnwwnnnnw", "3": "wnwwnnnnn", "4": "nnnwwnnnw", "5": "wnnwwnnnn", "6": "nnwwwnnnn", "7": "nnnwnnwnw", "8": "wnnwnnwnn", "9": "nnwwnnwnn",
        "A": "wnnnnwnnw", "B": "nnwnnwnnw", "C": "wnwnnwnnn", "D": "nnnnwwnnw", "E": "wnnnwwnnn", "F": "nnwnwwnnn", "G": "nnnnnwwnw", "H": "wnnnnwwnn", "I": "nnwnnwwnn", "J": "nnnnwwwnn",
        "K": "wnnnnnnww", "L": "nnwnnnnww", "M": "wnwnnnnwn", "N": "nnnnwnnww", "O": "wnnnwnnwn", "P": "nnwnwnnwn", "Q": "nnnnnnwww", "R": "wnnnnnwwn", "S": "nnwnnnwwn", "T": "nnnnwnwwn",
        "U": "wwnnnnnnw", "V": "nwwnnnnnw", "W": "wwwnnnnnn", "X": "nwnnwnnnw", "Y": "wwnnwnnnn", "Z": "nwwnwnnnn", "-": "nwnnnnwnw", ".": "wwnnnnwnn", " ": "nwwnnnwnn", "$": "nwnwnwnnn", "/": "nwnwnnnwn", "+": "nwnnnwnwn", "%": "nnnwnwnwn", "*": "nwnnwnwnn",
    ]

    static func code39Bits(_ text: String) throws -> [Bool] {
        let t = "*" + text.uppercased() + "*"
        var bits: [Bool] = []
        for (i, c) in t.enumerated() {
            guard let p = code39[c] else { throw ToolError("Code 39 cannot encode '\(c)'", hint: "Allowed: A-Z 0-9 - . space $ / + %") }
            for (k, w) in p.enumerated() {
                let width = w == "w" ? 3 : 1
                bits += [Bool](repeating: k % 2 == 0, count: width)
            }
            if i < t.count - 1 { bits.append(false) }
        }
        return bits
    }

    static let eanL = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
    static let eanG = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
    static let eanR = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]
    static let eanParity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    static func eanChecksum(_ digits: [Int]) -> Int {
        var sum = 0
        for (i, d) in digits.reversed().enumerated() { sum += d * (i % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10
    }

    static func ean(_ text: String, length: Int) throws -> ([Bool], String) {
        var digits = text.compactMap(\.wholeNumberValue)
        guard digits.count == text.count else { throw ToolError("Only digits are allowed") }
        if digits.count == length - 1 { digits.append(eanChecksum(digits)) }
        guard digits.count == length else { throw ToolError("Expected \(length - 1) or \(length) digits, got \(digits.count)") }
        guard eanChecksum(Array(digits.dropLast())) == digits.last else { throw ToolError("Invalid check digit; expected \(eanChecksum(Array(digits.dropLast())))") }
        var bits = "101"
        if length == 13 {
            let parity = eanParity[digits[0]]
            for (i, d) in digits[1...6].enumerated() { bits += parity[parity.index(parity.startIndex, offsetBy: i)] == "L" ? eanL[d] : eanG[d] }
            bits += "01010"
            for d in digits[7...12] { bits += eanR[d] }
        } else {
            for d in digits[0...3] { bits += eanL[d] }
            bits += "01010"
            for d in digits[4...7] { bits += eanR[d] }
        }
        bits += "101"
        return (bits.map { $0 == "1" }, digits.map(String.init).joined())
    }

    static func svg(bits: [Bool], scale: Int, height: Int, text: String?) -> String {
        let quiet = 10
        let w = (bits.count + quiet * 2) * scale
        let textH = text == nil ? 0 : scale * 6 + 8
        var s = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(height + textH)\" viewBox=\"0 0 \(w) \(height + textH)\" shape-rendering=\"crispEdges\">\n  <rect width=\"\(w)\" height=\"\(height + textH)\" fill=\"#fff\"/>\n  <path fill=\"#000\" d=\""
        var x = quiet * scale
        var i = 0
        while i < bits.count {
            if bits[i] {
                var run = 0
                while i + run < bits.count, bits[i + run] { run += 1 }
                s += "M\(x) 0h\(run * scale)v\(height)h-\(run * scale)z"
                x += run * scale
                i += run
            } else { x += scale; i += 1 }
        }
        s += "\"/>\n"
        if let text { s += "  <text x=\"\(w / 2)\" y=\"\(height + textH - 6)\" font-family=\"ui-monospace, Menlo, monospace\" font-size=\"\(scale * 5)\" text-anchor=\"middle\">\(XMLJSON.escape(text))</text>\n" }
        return s + "</svg>"
    }

    static func png(bits: [Bool], scale: Int, height: Int, text: String?) throws -> Data {
        let quiet = 10
        let w = (bits.count + quiet * 2) * scale
        let textH = text == nil ? 0 : scale * 6 + 8
        guard let ctx = ImageRender.context(width: w, height: height + textH) else { throw ToolError("Render failure") }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: height + textH))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        for (i, b) in bits.enumerated() where b { ctx.fill(CGRect(x: (i + quiet) * scale, y: textH, width: scale, height: height)) }
        if let text { ImageRender.drawText(text, in: CGRect(x: 0, y: 0, width: w, height: textH), context: ctx, fontSize: CGFloat(scale * 5), color: CGColor(gray: 0, alpha: 1), fontName: "Menlo") }
        guard let img = ctx.makeImage(), let data = ImageRender.encode(img, format: .png) else { throw ToolError("PNG encoding failed") }
        return data
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        if options.mode == "read" || input.payload.kindName.hasPrefix("image") {
            let data = input.data
            guard !data.isEmpty else { throw ToolError("Drop or paste an image containing a barcode") }
            return try await QRCodeTool.read(data)
        }
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        switch options.symbology {
        case "pdf417", "aztec":
            let image: CIImage?
            if options.symbology == "pdf417" {
                let f = CIFilter.pdf417BarcodeGenerator(); f.message = Data(text.utf8); image = f.outputImage
            } else {
                let f = CIFilter.aztecCodeGenerator(); f.message = Data(text.utf8); f.correctionLevel = 23; image = f.outputImage
            }
            guard let img = image?.transformed(by: CGAffineTransform(scaleX: CGFloat(options.scale), y: CGFloat(options.scale))), let cg = ImageRender.render(ciImage: img), let png = ImageRender.encode(cg, format: .png) else {
                throw ToolError("Could not generate the barcode", hint: "The payload may be too long")
            }
            return ToolOutput(.image(png, .png), metadata: [MetaRow("Symbology", options.symbology.uppercased()), MetaRow("Size", "\(cg.width) × \(cg.height) px"), MetaRow("Payload", "\(text.utf8.count) bytes")], suggestedFileName: "barcode.png")
        default:
            let bits: [Bool]
            var label: String? = options.showText ? text : nil
            switch options.symbology {
            case "code39": bits = try Self.code39Bits(text); label = options.showText ? "*\(text.uppercased())*" : nil
            case "ean13": let (b, t) = try Self.ean(text, length: 13); bits = b; label = options.showText ? t : nil
            case "ean8": let (b, t) = try Self.ean(text, length: 8); bits = b; label = options.showText ? t : nil
            case "upca":
                let (b, t) = try Self.ean(text.count == 11 || text.count == 12 ? "0" + text : text, length: 13); bits = b; label = options.showText ? String(t.dropFirst()) : nil
            default: bits = try Self.code128(text)
            }
            let rows = [MetaRow("Symbology", options.symbology.uppercased()), MetaRow("Modules", "\(bits.count)"), MetaRow("Encoded", label ?? text, style: .mono)]
            if options.format == "svg" {
                let svg = Self.svg(bits: bits, scale: options.scale, height: options.height, text: label)
                return ToolOutput(.image(Data(svg.utf8), .svg), facets: [OutputFacet("SVG source", text: svg, language: .xml)], metadata: rows, suggestedFileName: "barcode.svg")
            }
            return ToolOutput(.image(try Self.png(bits: bits, scale: options.scale, height: options.height, text: label), .png), metadata: rows, suggestedFileName: "barcode.png")
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.range(of: "^\\d{13}$", options: .regularExpression) != nil, let d = Optional(s.compactMap(\.wholeNumberValue)), eanChecksum(Array(d.dropLast())) == d.last { return DetectionScore(0.6, "EAN-13 with valid check digit", options: ["symbology": .string("ean13")]) }
        return nil
    }
}
