import Foundation
import BitlatheCore

public struct Base64TextTool: DevTool {
    public static let id = "base64.text"
    public static let name = "Base64 String"
    public static let summary = "Encode and decode Base64, including URL-safe and unpadded variants"
    public static let category = ToolCategory.encode
    public static let symbol = "b.square"
    public static let keywords = ["base64", "encode", "decode", "url-safe", "b64"]
    public static let samples = [ToolSample("Encode", "Hello, Bitlathe! 👋"), ToolSample("Decode", "SGVsbG8sIEJpdGxhdGhlISDwn5GL", options: ["mode": .string("decode")])]
    public static let optionFields: [OptionField] = [
        .encodeDecode,
        .segmented("variant", "Alphabet", [.init("standard", "Standard"), .init("url", "URL-safe")], default: "standard"),
        .toggle("padding", "Padding", default: true, visibleWhen: ("mode", ["encode"])),
        .toggle("wrap", "Wrap at 76", visibleWhen: ("mode", ["encode"])),
        .picker("encoding", "Text encoding", [.init("utf8", "UTF-8"), .init("utf16", "UTF-16 BE"), .init("utf16le", "UTF-16 LE"), .init("latin1", "Latin-1")], default: "utf8", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var mode = "encode"
        public var variant = "standard"
        public var padding = true
        public var wrap = false
        public var encoding = "utf8"
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let enc = HexTextTool.encoding(options.encoding)
        if options.mode == "encode" {
            let data: Data
            if case .text(let t) = input.payload {
                guard !t.isEmpty else { throw ToolError.emptyInput }
                guard let d = t.data(using: enc) else { throw ToolError("Text cannot be encoded as \(options.encoding)") }
                data = d
            } else {
                data = input.data
            }
            guard !data.isEmpty else { throw ToolError.emptyInput }
            var s = data.base64EncodedString(options: options.wrap ? [.lineLength76Characters, .endLineWithLineFeed] : [])
            if options.variant == "url" { s = s.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") }
            if !options.padding { s = s.replacingOccurrences(of: "=", with: "") }
            return ToolOutput(text: s, metadata: [MetaRow("Input", ByteFormatter.string(data.count)), MetaRow("Output", "\(s.count) chars")])
        }
        let text = input.text.filter { !$0.isWhitespace }
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let data = try Self.decode(text)
        if let s = String(data: data, encoding: enc), !s.contains("\u{0}") || enc != .utf8 {
            return ToolOutput(text: s, metadata: [MetaRow("Decoded", ByteFormatter.string(data.count))])
        }
        if let f = ImageFormat.sniff(data) {
            return ToolOutput(.image(data, f), metadata: [MetaRow("Decoded", "\(f.rawValue.uppercased()) image, \(ByteFormatter.string(data.count))")])
        }
        return ToolOutput(.data(data), metadata: [MetaRow("Decoded", "\(ByteFormatter.string(data.count)) of binary data")], warnings: ["Decoded bytes are not valid \(options.encoding.uppercased()) text; showing a hex dump"])
    }

    public static func decode(_ text: String) throws -> Data {
        var t = text
        if let r = t.range(of: "^data:[^,]*,", options: .regularExpression) { t.removeSubrange(r) }
        t = t.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        t = Detect.padBase64(t)
        guard let d = Data(base64Encoded: t, options: .ignoreUnknownCharacters), !d.isEmpty || t.isEmpty else {
            if let bad = t.unicodeScalars.first(where: { !Detect.base64Chars.contains($0) }) {
                throw ToolError("Invalid Base64 character '\(Character(bad))'")
            }
            throw ToolError("Invalid Base64", hint: "Check for missing characters; length must be a multiple of 4 after padding")
        }
        return d
    }

    public static func detect(_ s: String) -> DetectionScore? {
        let t = s.filter { !$0.isWhitespace }
        guard t.count >= 12, !t.contains("."), !t.hasPrefix("0x") else { return nil }
        let isURL = t.contains("-") || t.contains("_")
        guard t.unicodeScalars.allSatisfy({ Detect.base64Chars.contains($0) || Detect.base64URLChars.contains($0) }) else { return nil }
        guard (t.count % 4 != 1), let d = Data(base64Encoded: Detect.padBase64(t.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"))) else { return nil }
        if s.range(of: "^[0-9]+$", options: .regularExpression) != nil { return nil }
        if s.range(of: "^[a-z]+$", options: .regularExpression) != nil || s.range(of: "^[A-Z]+$", options: .regularExpression) != nil { return nil }
        if let str = String(data: d, encoding: .utf8), !str.isEmpty, str.unicodeScalars.filter({ $0.value < 0x20 && $0 != "\n" && $0 != "\t" && $0 != "\r" }).isEmpty {
            return DetectionScore(isURL ? 0.75 : 0.8, "Base64 text", options: ["mode": .string("decode"), "variant": .string(isURL ? "url" : "standard")])
        }
        if ImageFormat.sniff(d) != nil { return DetectionScore(0.5, "Base64 image data", options: ["mode": .string("decode")]) }
        return t.count >= 24 && (t.hasSuffix("=") || t.count % 4 == 0) && (t.first { $0.isUppercase } != nil) && (t.first { $0.isLowercase } != nil) && (t.first { $0.isNumber } != nil)
            ? DetectionScore(0.4, "Possibly Base64", options: ["mode": .string("decode")]) : nil
    }
}

public struct Base64ImageTool: DevTool {
    public static let id = "base64.image"
    public static let name = "Base64 Image"
    public static let summary = "Encode an image to Base64 / data URI, or decode Base64 into an image preview"
    public static let category = ToolCategory.encode
    public static let symbol = "photo.badge.arrow.down"
    public static let keywords = ["base64", "image", "data uri", "png", "jpeg", "img src", "encode", "decode"]
    public static let io = ToolIO(input: .image, output: .text, acceptsFiles: true, inputLanguage: .plain, outputLanguage: .plain)
    public static let samples = [ToolSample("Tiny PNG (decode)", "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")]
    public static let optionFields: [OptionField] = [
        .segmented("output", "Output", [.init("datauri", "Data URI"), .init("raw", "Base64 only"), .init("img", "<img> tag"), .init("css", "CSS url()")], default: "datauri"),
    ]
    public struct Options: ToolOptions {
        public var output = "datauri"
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        switch input.payload {
        case .image(let data, let format):
            let b64 = data.base64EncodedString()
            let uri = "data:\(format.mimeType);base64,\(b64)"
            let text: String = switch options.output {
            case "raw": b64
            case "img": "<img src=\"\(uri)\" alt=\"\">"
            case "css": "background-image: url(\"\(uri)\");"
            default: uri
            }
            let meta = [MetaRow("Format", format.rawValue.uppercased()), MetaRow("Image size", ByteFormatter.string(data.count)), MetaRow("Encoded size", ByteFormatter.string(text.utf8.count))]
            return ToolOutput(text: text, facets: [OutputFacet("Data URI", text: uri), OutputFacet("Base64", text: b64)], metadata: meta)
        case .text(let t):
            guard !t.trimmed().isEmpty else { throw ToolError.emptyInput }
            var raw = t.trimmed()
            var declared: ImageFormat?
            if let m = raw.captures("^data:(image/[a-z+.-]+);base64,") { declared = ImageFormat(mimeType: m[1]); raw = String(raw.dropFirst(m[0].count)) }
            if let m = raw.captures("src=[\"'](data:[^\"']+)[\"']") { raw = m[1]; if let mm = raw.captures("^data:(image/[a-z+.-]+);base64,") { declared = ImageFormat(mimeType: mm[1]); raw = String(raw.dropFirst(mm[0].count)) } }
            let data = try Base64TextTool.decode(raw)
            guard let format = ImageFormat.sniff(data) ?? declared else { throw ToolError("Decoded data is not a recognised image", hint: "Supported: PNG, JPEG, GIF, TIFF, BMP, WebP, HEIC, SVG") }
            return ToolOutput(.image(data, format), metadata: [MetaRow("Format", format.rawValue.uppercased()), MetaRow("Size", ByteFormatter.string(data.count))], suggestedFileName: "decoded.\(format.fileExtension)")
        case .data(let data):
            guard let f = ImageFormat.sniff(data) else { throw ToolError("Not an image") }
            return try await run(ToolInput(.image(data, f)), options: options)
        case .file(let url):
            let data = try Data(contentsOf: url)
            guard let f = ImageFormat.sniff(data) else { throw ToolError("Not an image file") }
            return try await run(ToolInput(.image(data, f)), options: options)
        case .none:
            throw ToolError.emptyInput
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.hasPrefix("data:image/") { return DetectionScore(0.95, "Image data URI") }
        let t = s.filter { !$0.isWhitespace }
        if t.count > 40, t.hasPrefix("iVBORw0KGgo") || t.hasPrefix("/9j/") || t.hasPrefix("R0lGOD") || t.hasPrefix("UklGR") || t.hasPrefix("PHN2Zy") { return DetectionScore(0.9, "Base64 image") }
        return nil
    }
}
