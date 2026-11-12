import Foundation
import BitlatheCore

public struct YAMLFormatTool: DevTool {
    public static let id = "yaml.format"
    public static let name = "YAML Formatter"
    public static let summary = "Format and validate YAML with precise error locations"
    public static let category = ToolCategory.format
    public static let symbol = "list.bullet.indent"
    public static let keywords = ["yaml", "yml", "format", "validate", "lint"]
    public static let io = ToolIO.text(.yaml, .yaml)
    public static let samples = [ToolSample("Compose file", "version: '3'\nservices:\n    web:\n        image:   nginx\n        ports: [\"80:80\", \"443:443\"]\n        environment: {DEBUG: 'false', LEVEL: 3}")]
    public static let optionFields: [OptionField] = [
        .mode([.init("format", "Format"), .init("validate", "Validate")], default: "format"),
        .picker("indent", "Indent", [.init("2", "2 spaces"), .init("4", "4 spaces")], default: "2", visibleWhen: ("mode", ["format"])),
        .toggle("sortKeys", "Sort keys", visibleWhen: ("mode", ["format"])),
        .stepper("width", "Line width", min: 0, max: 200, step: 10, default: 80, help: "0 = never fold", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var mode = "format"
        public var indent = "2"
        public var sortKeys = false
        public var width = 80
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let docs = try YAMLBridge.parse(text)
        var meta = [MetaRow("Documents", "\(docs.count)")]
        if let first = docs.first { meta.append(MetaRow("Root", first.typeName)) }
        if options.mode == "validate" { return ToolOutput(text: text, language: .yaml, metadata: meta, isValid: true) }
        let out = try docs.map { try YAMLBridge.serialize($0, indent: Int(options.indent) ?? 2, width: options.width, sortKeys: options.sortKeys) }
            .joined(separator: "\n---\n")
        return ToolOutput(text: docs.count > 1 ? "---\n" + out : out, language: .yaml, metadata: meta, isValid: true)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard s.contains("\n") || s.hasPrefix("---"), !s.hasPrefix("{"), !s.hasPrefix("["), !s.hasPrefix("<") else { return nil }
        let lines = s.split(separator: "\n").prefix(40)
        let kv = lines.filter { $0.range(of: "^\\s*(- )?[\\w.\"'\\-/ ]+:(\\s|$)", options: .regularExpression) != nil }.count
        if s.hasPrefix("---") || (kv >= 2 && kv * 2 >= lines.count) {
            if s.contains("=") && !s.contains(": ") { return nil }
            return (try? YAMLBridge.parse(s)) != nil ? DetectionScore(0.75, "YAML mapping") : DetectionScore(0.4, "Looks like YAML")
        }
        return nil
    }
}
