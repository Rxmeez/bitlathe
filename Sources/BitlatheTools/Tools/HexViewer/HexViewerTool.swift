import Foundation
import BitlatheCore

public struct HexViewerTool: DevTool {
    public static let id = "hex.viewer"
    public static let name = "Hex Viewer"
    public static let summary = "Inspect any file or text as a hex dump with offsets, ASCII column and file-type detection"
    public static let category = ToolCategory.inspect
    public static let symbol = "rectangle.grid.3x2"
    public static let keywords = ["hex", "dump", "binary", "bytes", "xxd", "hexdump", "file", "magic", "offset"]
    public static let io = ToolIO(input: .binary, output: .text, acceptsFiles: true, inputLanguage: .plain, outputLanguage: .hex)
    public static let samples = [ToolSample("Text", "Bitlathe: bits in, shape out.\n👋 UTF-8 bytes!")]
    public static let optionFields: [OptionField] = [
        .picker("width", "Bytes per line", [.init("8", "8"), .init("16", "16"), .init("32", "32")], default: "16"),
        .toggle("uppercase", "Uppercase"),
        .toggle("decimalOffsets", "Decimal offsets"),
        .stepper("limitKB", "Limit (KB)", min: 1, max: 4096, step: 16, default: 256, help: "Only the first N KB are rendered", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var width = "16"
        public var uppercase = false
        public var decimalOffsets = false
        public var limitKB = 256
        public init() {}
    }
    public init() {}

    public static func fileType(_ d: Data) -> String? {
        if let img = ImageFormat.sniff(d) { return "\(img.rawValue.uppercased()) image" }
        if let c = Compressor.sniff(d) { return "\(c.title) compressed data" }
        let b = [UInt8](d.prefix(16))
        guard b.count >= 4 else { return nil }
        if b.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "PDF document" }
        if b.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return "ZIP archive (or docx/xlsx/jar/apk)" }
        if b.starts(with: [0x7F, 0x45, 0x4C, 0x46]) { return "ELF executable" }
        if b.starts(with: [0xCF, 0xFA, 0xED, 0xFE]) || b.starts(with: [0xCE, 0xFA, 0xED, 0xFE]) { return "Mach-O executable" }
        if b.starts(with: [0xCA, 0xFE, 0xBA, 0xBE]) { return "Mach-O universal binary / Java class" }
        if b.starts(with: [0x4D, 0x5A]) { return "Windows executable (PE)" }
        if b.starts(with: [0x53, 0x51, 0x4C, 0x69, 0x74, 0x65]) { return "SQLite database" }
        if b.starts(with: [0x62, 0x70, 0x6C, 0x69, 0x73, 0x74]) { return "Binary property list" }
        if b.starts(with: [0x00, 0x61, 0x73, 0x6D]) { return "WebAssembly module" }
        if b.starts(with: [0x4F, 0x67, 0x67, 0x53]) { return "Ogg container" }
        if b.starts(with: [0x49, 0x44, 0x33]) || (b[0] == 0xFF && b[1] & 0xE0 == 0xE0) { return "MP3 audio" }
        if b.starts(with: [0x52, 0x49, 0x46, 0x46]) { return "RIFF container (WAV/AVI)" }
        if b.count >= 12, Array(b[4..<8]) == [0x66, 0x74, 0x79, 0x70] { return "ISO media (MP4/MOV/HEIF)" }
        if b.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) { return "Matroska / WebM" }
        if b.starts(with: [0x77, 0x4F, 0x46, 0x46]) || b.starts(with: [0x77, 0x4F, 0x46, 0x32]) { return "WOFF font" }
        if b.starts(with: [0x00, 0x01, 0x00, 0x00]) || b.starts(with: [0x4F, 0x54, 0x54, 0x4F]) { return "TrueType / OpenType font" }
        if b.starts(with: [0x30, 0x82]) { return "DER-encoded ASN.1 (certificate / key)" }
        if b.starts(with: [0xEF, 0xBB, 0xBF]) { return "UTF-8 text with BOM" }
        if b.starts(with: [0xFF, 0xFE]) || b.starts(with: [0xFE, 0xFF]) { return "UTF-16 text with BOM" }
        if b.starts(with: Array("#!".utf8)) { return "Script with shebang" }
        if b.starts(with: Array("%!PS".utf8)) { return "PostScript" }
        if b.starts(with: Array("-----BEGIN".utf8)) { return "PEM" }
        return nil
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let data = input.data
        guard !data.isEmpty else { throw ToolError.emptyInput }
        let width = Int(options.width) ?? 16
        let limit = min(data.count, options.limitKB * 1024)
        let slice = data.prefix(limit)
        var out = ""
        out.reserveCapacity(limit * 4)
        let bytes = [UInt8](slice)
        var offset = 0
        let fmt = options.uppercase ? "%02X " : "%02x "
        while offset < bytes.count {
            let chunk = bytes[offset..<min(offset + width, bytes.count)]
            out += options.decimalOffsets ? String(format: "%10d  ", offset) : String(format: options.uppercase ? "%08X  " : "%08x  ", offset)
            var hex = ""
            for (i, b) in chunk.enumerated() {
                hex += String(format: fmt, b)
                if (i + 1) % 8 == 0, i + 1 < width { hex += " " }
            }
            out += hex.padding(toLength: width * 3 + (width / 8 - 1) + 1, withPad: " ", startingAt: 0)
            out += "|" + String(chunk.map { $0 >= 32 && $0 < 127 ? Character(UnicodeScalar($0)) : "." }) + "|\n"
            offset += width
            if offset % (width * 512) == 0 { try Task.checkpoint() }
        }
        if limit < data.count { out += "… \(ByteFormatter.string(data.count - limit)) more (raise the limit in options)\n" }
        var counts = [Int](repeating: 0, count: 256)
        for b in slice { counts[Int(b)] += 1 }
        let entropy = counts.reduce(0.0) { acc, c in
            guard c > 0 else { return acc }
            let p = Double(c) / Double(limit)
            return acc - p * log2(p)
        }
        let printable = counts[32..<127].reduce(0, +) + counts[9] + counts[10] + counts[13]
        var rows = [MetaRow("Size", "\(ByteFormatter.string(data.count)) (\(data.count) bytes)"), MetaRow("Entropy", String(format: "%.2f bits/byte%@", entropy, entropy > 7.5 ? " (compressed or encrypted)" : (entropy < 4.5 ? " (text-like)" : ""))),
                    MetaRow("Printable", String(format: "%.0f%%", Double(printable) / Double(max(limit, 1)) * 100)), MetaRow("Null bytes", "\(counts[0])")]
        if let t = Self.fileType(data) { rows.insert(MetaRow("Detected type", t), at: 0) }
        if let name = input.fileName { rows.insert(MetaRow("File", name), at: 0) }
        return ToolOutput(text: out, language: .hex, metadata: rows)
    }
}
