import Foundation
import BitlatheCore

public struct TOMLFormatTool: DevTool {
    public static let id = "toml.format"
    public static let name = "TOML Formatter"
    public static let summary = "Format and validate TOML"
    public static let category = ToolCategory.format
    public static let symbol = "doc.plaintext"
    public static let keywords = ["toml", "cargo", "pyproject", "config", "format", "validate"]
    public static let io = ToolIO.text(.toml, .toml)
    public static let samples = [ToolSample("Cargo.toml", "[package]\nname=\"bitlathe\"\nversion = \"0.1.0\"\n[dependencies]\nserde = { version = \"1\", features = [\"derive\"] }")]
    public static let optionFields: [OptionField] = [
        .mode([.init("format", "Format"), .init("validate", "Validate")], default: "format"),
    ]
    public struct Options: ToolOptions {
        public var mode = "format"
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let v = try TOMLBridge.parse(text)
        let meta = [MetaRow("Top-level keys", "\(v.count)")]
        if options.mode == "validate" { return ToolOutput(text: text, language: .toml, metadata: meta, isValid: true) }
        return ToolOutput(text: try TOMLBridge.serialize(v).trimmed(), language: .toml, metadata: meta, isValid: true)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        guard s.range(of: "(?m)^\\s*\\[[A-Za-z0-9_.\"' -]+\\]\\s*$", options: .regularExpression) != nil,
              s.range(of: "(?m)^\\s*[A-Za-z0-9_.\"'-]+\\s*=\\s*\\S", options: .regularExpression) != nil else { return nil }
        return (try? TOMLBridge.parse(s)) != nil ? DetectionScore(0.85, "TOML tables") : DetectionScore(0.4, "Looks like TOML")
    }
}
