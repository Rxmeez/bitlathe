import Foundation

/// Type-erased tool. Everything outside a tool's own folder works with this.
public struct AnyTool: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, Codable { case native, script, pipeline }

    public let id: String
    public let name: String
    public let summary: String
    public let category: ToolCategory
    public let symbol: String
    public let keywords: [String]
    public let samples: [ToolSample]
    public let io: ToolIO
    public let optionFields: [OptionField]
    public let sideEffects: Bool
    public let historyEnabledByDefault: Bool
    public let kind: Kind
    public let requiredEntitlement: Entitlement

    private let runner: @Sendable (ToolInput, OptionValues) async throws -> ToolOutput
    private let detector: @Sendable (String) -> DetectionScore?

    public init<T: DevTool>(_ type: T.Type, kind: Kind = .native) {
        id = T.id
        name = T.name
        summary = T.summary
        category = T.category
        symbol = T.symbol
        keywords = T.keywords
        samples = T.samples
        io = T.io
        optionFields = T.optionFields
        sideEffects = T.sideEffects
        historyEnabledByDefault = T.historyEnabledByDefault
        self.kind = kind
        requiredEntitlement = .free
        let fields = T.optionFields
        runner = { input, values in
            let options = try OptionDecoder.decode(T.Options.self, from: values, fields: fields)
            return try await T().run(input, options: options)
        }
        detector = { T.detect($0) }
    }

    /// Build an erased tool from closures (scripts, pipelines).
    public init(id: String, name: String, summary: String, category: ToolCategory, symbol: String,
                keywords: [String] = [], samples: [ToolSample] = [], io: ToolIO = .text,
                optionFields: [OptionField] = [], sideEffects: Bool = false, kind: Kind,
                detect: @escaping @Sendable (String) -> DetectionScore? = { _ in nil },
                run: @escaping @Sendable (ToolInput, OptionValues) async throws -> ToolOutput) {
        self.id = id
        self.name = name
        self.summary = summary
        self.category = category
        self.symbol = symbol
        self.keywords = keywords
        self.samples = samples
        self.io = io
        self.optionFields = optionFields
        self.sideEffects = sideEffects
        self.historyEnabledByDefault = true
        self.kind = kind
        self.requiredEntitlement = .free
        self.runner = run
        self.detector = detect
    }

    public func run(_ input: ToolInput, options: OptionValues = [:]) async throws -> ToolOutput {
        try await runner(input, options)
    }

    public func run(text: String, options: OptionValues = [:]) async throws -> ToolOutput {
        try await runner(ToolInput(text: text), options)
    }

    public func detect(_ sample: String) -> DetectionScore? { detector(sample) }

    public var searchText: String {
        ([name, summary, id, category.title] + keywords).joined(separator: " ").lowercased()
    }

    public static func == (lhs: AnyTool, rhs: AnyTool) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
