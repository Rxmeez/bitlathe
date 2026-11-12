import Foundation
import Vision
import BitlatheCore

public struct OCRTool: DevTool {
    public static let id = "ocr.text"
    public static let name = "OCR — Text from Image"
    public static let summary = "Extract text from screenshots and photos on-device with Vision, with per-line confidence"
    public static let category = ToolCategory.media
    public static let symbol = "text.viewfinder"
    public static let keywords = ["ocr", "text recognition", "screenshot", "image to text", "vision", "scan", "extract"]
    public static let io = ToolIO(input: .image, output: .text, acceptsFiles: true)
    public static let optionFields: [OptionField] = [
        .segmented("level", "Accuracy", [.init("accurate", "Accurate"), .init("fast", "Fast")], default: "accurate"),
        .text("languages", "Languages", placeholder: "en-US, de-DE (blank = auto)", help: "BCP-47 codes"),
        .toggle("correction", "Language correction", default: true),
        .segmented("layout", "Layout", [.init("lines", "Lines"), .init("paragraphs", "Paragraphs"), .init("json", "JSON with boxes")], default: "lines"),
    ]
    public struct Options: ToolOptions {
        public var level = "accurate"
        public var languages = ""
        public var correction = true
        public var layout = "lines"
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let data = input.data
        guard !data.isEmpty, let cg = ImageRender.cgImage(from: data) else { throw ToolError("Drop a screenshot or photo, or paste an image") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = options.level == "fast" ? .fast : .accurate
        request.usesLanguageCorrection = options.correction
        let langs = options.languages.split(separator: ",").map { $0.trimmed() }.filter { !$0.isEmpty }
        if !langs.isEmpty { request.recognitionLanguages = langs } else { request.automaticallyDetectsLanguage = true }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])
        let results = (request.results ?? []).sorted { a, b in
            let ay = a.boundingBox.midY, by = b.boundingBox.midY
            if abs(ay - by) > 0.01 { return ay > by }
            return a.boundingBox.minX < b.boundingBox.minX
        }
        guard !results.isEmpty else { throw ToolError("No text recognised", hint: "Try the Accurate level or a larger image") }
        var lines: [(String, Float, CGRect)] = []
        for r in results { if let c = r.topCandidates(1).first { lines.append((c.string, c.confidence, r.boundingBox)) } }
        let avg = lines.map(\.1).reduce(0, +) / Float(max(lines.count, 1))
        let text: String
        switch options.layout {
        case "paragraphs":
            var paras: [String] = []
            var current = ""
            var lastBox: CGRect?
            for (s, _, box) in lines {
                if let lb = lastBox, lb.minY - box.maxY > box.height * 0.8 { paras.append(current); current = "" }
                current += (current.isEmpty ? "" : " ") + s
                lastBox = box
            }
            if !current.isEmpty { paras.append(current) }
            text = paras.joined(separator: "\n\n")
        case "json":
            text = JSONSerializer.string(.array(lines.map { s, conf, box in
                .object([(key: "text", value: .string(s)), (key: "confidence", value: .number(Double(conf))),
                         (key: "box", value: .object([(key: "x", value: .number(Double(box.minX))), (key: "y", value: .number(Double(1 - box.maxY))), (key: "width", value: .number(Double(box.width))), (key: "height", value: .number(Double(box.height)))]))])
            }))
        default:
            text = lines.map(\.0).joined(separator: "\n")
        }
        var rows = [MetaRow("Lines", "\(lines.count)"), MetaRow("Words", "\(text.split { $0.isWhitespace || $0.isNewline }.count)"), MetaRow("Average confidence", String(format: "%.0f%%", avg * 100), style: avg > 0.8 ? .success : .warning),
                    MetaRow("Image", "\(cg.width) × \(cg.height) px")]
        let low = lines.filter { $0.1 < 0.5 }
        if !low.isEmpty { rows.append(MetaRow("Low confidence", low.prefix(5).map { "“\($0.0)”" }.joined(separator: ", "), style: .warning)) }
        return ToolOutput(text: text, language: options.layout == "json" ? .json : .plain, metadata: rows)
    }
}
