import Foundation
import BitlatheCore

public struct CompressTool: DevTool {
    public static let id = "compress.text"
    public static let name = "Compress / Decompress"
    public static let summary = "Gzip, Deflate, Zlib, Brotli, LZFSE, LZ4 and LZMA with Base64 or hex wrapping"
    public static let category = ToolCategory.encode
    public static let symbol = "archivebox"
    public static let keywords = ["gzip", "gunzip", "deflate", "inflate", "zlib", "brotli", "lzfse", "lz4", "lzma", "compress", "decompress", "base64"]
    public static let samples = [ToolSample("Compress", String(repeating: "Bitlathe compresses repeated text very well. ", count: 8)),
                                 ToolSample("Decompress gzip", "H4sIAAAAAAAAA3NKLEnMyUxRyC9KSS1SKMrMS1cAAHUMb8sRAAAA", options: ["mode": .string("decompress")])]
    public static let optionFields: [OptionField] = [
        .mode([.init("compress", "Compress"), .init("decompress", "Decompress")], default: "compress"),
        .picker("algorithm", "Algorithm", [.init("auto", "Auto-detect")] + Compressor.Algorithm.allCases.map { OptionChoice($0.rawValue, $0.title) }, default: "gzip"),
        .segmented("wrap", "Bytes as", [.init("base64", "Base64"), .init("hex", "Hex"), .init("raw", "Raw")], default: "base64"),
        .stepper("level", "Level", min: 1, max: 9, default: 6, visibleWhen: ("mode", ["compress"]), advanced: true),
    ]
    public struct Options: ToolOptions {
        public var mode = "compress"
        public var algorithm = "gzip"
        public var wrap = "base64"
        public var level = 6
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        if options.mode == "compress" {
            let data = input.data
            guard !data.isEmpty else { throw ToolError.emptyInput }
            let algo = Compressor.Algorithm(rawValue: options.algorithm) ?? .gzip
            let out = try Compressor.compress(data, algorithm: algo, level: options.level)
            let ratio = data.isEmpty ? 0 : Double(out.count) / Double(data.count) * 100
            let meta = [MetaRow("Algorithm", algo.title), MetaRow("Input", ByteFormatter.string(data.count)), MetaRow("Output", ByteFormatter.string(out.count)),
                        MetaRow("Ratio", String(format: "%.1f%% of original", ratio))]
            switch options.wrap {
            case "hex": return ToolOutput(text: out.hexString, language: .hex, metadata: meta)
            case "raw": return ToolOutput(.data(out), metadata: meta, suggestedFileName: "output.\(algo == .gzip ? "gz" : algo.rawValue)")
            default: return ToolOutput(text: out.base64EncodedString(), metadata: meta)
            }
        }
        // decompress
        var data: Data
        switch input.payload {
        case .text(let t):
            let s = t.trimmed()
            guard !s.isEmpty else { throw ToolError.emptyInput }
            if let d = Data(hex: s), Compressor.sniff(d) != nil || options.wrap == "hex" { data = d }
            else if let d = try? Base64TextTool.decode(s) { data = d }
            else { data = Data(t.utf8) }
        default:
            data = input.data
        }
        guard !data.isEmpty else { throw ToolError.emptyInput }
        var algo = Compressor.Algorithm(rawValue: options.algorithm)
        if options.algorithm == "auto" || algo == nil {
            algo = Compressor.sniff(data)
            if algo == nil {
                // Try deflate, then brotli (no magic bytes).
                if let d = try? Compressor.decompress(data, algorithm: .deflate), !d.isEmpty { algo = .deflate }
                else if let d = try? Compressor.decompress(data, algorithm: .brotli), !d.isEmpty { algo = .brotli }
                else { throw ToolError("Could not detect the compression format", hint: "Choose the algorithm explicitly") }
            }
        }
        let out = try Compressor.decompress(data, algorithm: algo!)   // swiftlint:disable:this force_unwrapping
        let meta = [MetaRow("Algorithm", algo!.title), MetaRow("Compressed", ByteFormatter.string(data.count)), MetaRow("Decompressed", ByteFormatter.string(out.count))]   // swiftlint:disable:this force_unwrapping
        if let s = String(data: out, encoding: .utf8) {
            let lang: CodeLanguage = JSONFormatTool.detect(s.trimmed()) != nil ? .json : .plain
            return ToolOutput(text: s, language: lang, metadata: meta)
        }
        if let f = ImageFormat.sniff(out) { return ToolOutput(.image(out, f), metadata: meta) }
        return ToolOutput(.data(out), metadata: meta, warnings: ["Decompressed data is binary"])
    }

    public static func detect(_ s: String) -> DetectionScore? {
        let t = s.filter { !$0.isWhitespace }
        if t.hasPrefix("H4sI") { return DetectionScore(0.95, "Base64 gzip stream", options: ["mode": .string("decompress"), "algorithm": .string("auto")]) }
        if t.hasPrefix("eJ") || t.hasPrefix("eN") || t.hasPrefix("eF"), t.count > 16, Detect.isBase64(t) { return DetectionScore(0.6, "Base64 zlib stream", options: ["mode": .string("decompress"), "algorithm": .string("auto")]) }
        if t.lowercased().hasPrefix("1f8b08") { return DetectionScore(0.9, "Hex gzip stream", options: ["mode": .string("decompress"), "algorithm": .string("auto"), "wrap": .string("hex")]) }
        if t.lowercased().hasPrefix("789c") || t.lowercased().hasPrefix("78da"), Detect.isHex(t) { return DetectionScore(0.7, "Hex zlib stream", options: ["mode": .string("decompress"), "algorithm": .string("auto"), "wrap": .string("hex")]) }
        return nil
    }
}
