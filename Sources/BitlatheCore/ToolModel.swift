import Foundation

// MARK: - Categories

public enum ToolCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case format, convert, encode, inspect, generate, media, scripting

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .format: "Format & Validate"
        case .convert: "Converters"
        case .encode: "Encoders & Decoders"
        case .inspect: "Inspect & Debug"
        case .generate: "Generators"
        case .media: "Images & Media"
        case .scripting: "Scripts & Pipelines"
        }
    }

    public var symbol: String {
        switch self {
        case .format: "text.alignleft"
        case .convert: "arrow.left.arrow.right"
        case .encode: "lock.rotation"
        case .inspect: "magnifyingglass"
        case .generate: "sparkles"
        case .media: "photo"
        case .scripting: "terminal"
        }
    }
}

// MARK: - Languages (for highlighting)

public enum CodeLanguage: String, Codable, Sendable, CaseIterable {
    case plain, json, yaml, xml, html, css, javascript, typescript, sql, swift, markdown, toml, graphql
    case shell, python, go, rust, kotlin, java, csharp, php, ruby, csv, diff, hex, dotenv, regex, properties

    public var displayName: String {
        switch self {
        case .plain: "Plain text"
        case .json: "JSON"
        case .yaml: "YAML"
        case .xml: "XML"
        case .html: "HTML"
        case .css: "CSS"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .sql: "SQL"
        case .swift: "Swift"
        case .markdown: "Markdown"
        case .toml: "TOML"
        case .graphql: "GraphQL"
        case .shell: "Shell"
        case .python: "Python"
        case .go: "Go"
        case .rust: "Rust"
        case .kotlin: "Kotlin"
        case .java: "Java"
        case .csharp: "C#"
        case .php: "PHP"
        case .ruby: "Ruby"
        case .csv: "CSV"
        case .diff: "Diff"
        case .hex: "Hex"
        case .dotenv: ".env"
        case .regex: "Regex"
        case .properties: "Properties"
        }
    }
}

// MARK: - Payloads

public enum ImageFormat: String, Codable, Sendable, CaseIterable {
    case png, jpeg, gif, tiff, heic, webp, bmp, svg, avif, ico, icns

    public var mimeType: String {
        switch self {
        case .png: "image/png"
        case .jpeg: "image/jpeg"
        case .gif: "image/gif"
        case .tiff: "image/tiff"
        case .heic: "image/heic"
        case .webp: "image/webp"
        case .bmp: "image/bmp"
        case .svg: "image/svg+xml"
        case .avif: "image/avif"
        case .ico: "image/x-icon"
        case .icns: "image/icns"
        }
    }

    public var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }

    public init?(mimeType: String) {
        let m = mimeType.lowercased()
        if m.contains("jpeg") || m.contains("jpg") { self = .jpeg; return }
        guard let f = ImageFormat.allCases.first(where: { $0.mimeType == m }) else { return nil }
        self = f
    }

    /// Sniff the format from magic bytes.
    public static func sniff(_ data: Data) -> ImageFormat? {
        guard data.count >= 12 else { return nil }
        let b = [UInt8](data.prefix(12))
        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return .png }
        if b[0] == 0xFF, b[1] == 0xD8 { return .jpeg }
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return .gif }
        if b[0] == 0x42, b[1] == 0x4D { return .bmp }
        if (b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A) || (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A) { return .tiff }
        if b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46, b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return .webp }
        if b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 {
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            if brand.hasPrefix("avi") { return .avif }
            if brand.hasPrefix("hei") || brand.hasPrefix("mif") { return .heic }
        }
        if b[0] == 0x00, b[1] == 0x00, b[2] == 0x01, b[3] == 0x00 { return .ico }
        if b[0] == 0x69, b[1] == 0x63, b[2] == 0x6E, b[3] == 0x73 { return .icns }
        if let s = String(data: data.prefix(512), encoding: .utf8), s.contains("<svg") { return .svg }
        return nil
    }
}

public enum ToolPayload: Sendable, Equatable {
    case none
    case text(String)
    case data(Data)
    case image(Data, ImageFormat)
    case file(URL)

    public var text: String? {
        switch self {
        case .text(let s): s
        case .data(let d): String(data: d, encoding: .utf8)
        case .file(let url): try? String(contentsOf: url, encoding: .utf8)
        case .image(let d, .svg): String(data: d, encoding: .utf8)
        default: nil
        }
    }

    public var data: Data? {
        switch self {
        case .text(let s): Data(s.utf8)
        case .data(let d), .image(let d, _): d
        case .file(let url): try? Data(contentsOf: url)
        case .none: nil
        }
    }

    public var isEmpty: Bool {
        switch self {
        case .none: true
        case .text(let s): s.isEmpty
        case .data(let d), .image(let d, _): d.isEmpty
        case .file: false
        }
    }

    public var byteCount: Int {
        switch self {
        case .none: 0
        case .text(let s): s.utf8.count
        case .data(let d), .image(let d, _): d.count
        case .file(let url): (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
    }

    public var kindName: String {
        switch self {
        case .none: "empty"
        case .text: "text"
        case .data: "binary"
        case .image(_, let f): "image/\(f.rawValue)"
        case .file: "file"
        }
    }
}

public struct ToolInput: Sendable {
    public var payload: ToolPayload
    /// Second input for tools that compare two things (diff).
    public var secondary: ToolPayload?
    public var fileName: String?
    /// Selection inside the primary text (used by Scratchpad and scripts).
    public var selection: Range<Int>?

    public init(_ payload: ToolPayload, secondary: ToolPayload? = nil, fileName: String? = nil, selection: Range<Int>? = nil) {
        self.payload = payload
        self.secondary = secondary
        self.fileName = fileName
        self.selection = selection
    }

    public init(text: String) { self.init(.text(text)) }

    public var text: String { payload.text ?? "" }
    public var data: Data { payload.data ?? Data() }
    public var isEmpty: Bool { payload.isEmpty }
}

public struct OutputFacet: Sendable, Equatable, Identifiable {
    public var id: String { title }
    public var title: String
    public var payload: ToolPayload
    public var language: CodeLanguage
    public init(_ title: String, _ payload: ToolPayload, language: CodeLanguage = .plain) {
        self.title = title
        self.payload = payload
        self.language = language
    }
    public init(_ title: String, text: String, language: CodeLanguage = .plain) {
        self.init(title, .text(text), language: language)
    }
}

public struct MetaRow: Sendable, Equatable, Identifiable {
    public enum Style: Sendable { case plain, mono, success, warning, danger, muted }
    public var id: String { label + "|" + value }
    public var label: String
    public var value: String
    public var style: Style
    public init(_ label: String, _ value: String, style: Style = .plain) {
        self.label = label
        self.value = value
        self.style = style
    }
}

public struct Annotation: Sendable, Equatable {
    public enum Target: Sendable { case input, output }
    public enum Style: Sendable { case match, group, error, warning, added, removed, info }
    public var target: Target
    public var range: Range<Int>    // UTF-16 offsets
    public var style: Style
    public var tooltip: String?
    public init(_ target: Target, range: Range<Int>, style: Style, tooltip: String? = nil) {
        self.target = target
        self.range = range
        self.style = style
        self.tooltip = tooltip
    }
}

public struct ToolOutput: Sendable, Equatable {
    public var payload: ToolPayload
    public var language: CodeLanguage
    public var facets: [OutputFacet]
    public var metadata: [MetaRow]
    public var annotations: [Annotation]
    public var warnings: [String]
    /// For validators: nil = not applicable.
    public var isValid: Bool?
    public var suggestedFileName: String?

    public init(_ payload: ToolPayload, language: CodeLanguage = .plain, facets: [OutputFacet] = [],
                metadata: [MetaRow] = [], annotations: [Annotation] = [], warnings: [String] = [],
                isValid: Bool? = nil, suggestedFileName: String? = nil) {
        self.payload = payload
        self.language = language
        self.facets = facets
        self.metadata = metadata
        self.annotations = annotations
        self.warnings = warnings
        self.isValid = isValid
        self.suggestedFileName = suggestedFileName
    }

    public init(text: String, language: CodeLanguage = .plain, facets: [OutputFacet] = [],
                metadata: [MetaRow] = [], annotations: [Annotation] = [], warnings: [String] = [],
                isValid: Bool? = nil) {
        self.init(.text(text), language: language, facets: facets, metadata: metadata,
                  annotations: annotations, warnings: warnings, isValid: isValid)
    }

    public static let empty = ToolOutput(.none)
    public var text: String { payload.text ?? "" }
}

// MARK: - Errors

public struct ToolError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    public var message: String
    public var line: Int?
    public var column: Int?
    public var hint: String?
    /// UTF-16 offset range in the input, when known.
    public var range: Range<Int>?

    public init(_ message: String, line: Int? = nil, column: Int? = nil, hint: String? = nil, range: Range<Int>? = nil) {
        self.message = message
        self.line = line
        self.column = column
        self.hint = hint
        self.range = range
    }

    public static func invalid(_ what: String) -> ToolError { ToolError("Invalid \(what)") }
    public static let emptyInput = ToolError("Nothing to process")
    public static func unsupported(_ what: String) -> ToolError { ToolError("\(what) is not supported on this system") }

    public var description: String {
        var s = message
        if let line { s += " (line \(line)" + (column.map { ", column \($0)" } ?? "") + ")" }
        return s
    }
    public var errorDescription: String? { description }
    public var location: String? {
        guard let line else { return nil }
        return column.map { "Ln \(line), Col \($0)" } ?? "Ln \(line)"
    }
}

// MARK: - Detection

public struct DetectionScore: Sendable, Equatable, Comparable {
    /// 0…1
    public var confidence: Double
    public var reason: String
    /// Option overrides to apply when opened via detection (e.g. mode = decode).
    public var options: OptionValues

    public init(_ confidence: Double, _ reason: String, options: OptionValues = [:]) {
        self.confidence = min(max(confidence, 0), 1)
        self.reason = reason
        self.options = options
    }

    public static func < (lhs: DetectionScore, rhs: DetectionScore) -> Bool { lhs.confidence < rhs.confidence }
}

// MARK: - Samples & IO

public struct ToolSample: Sendable, Identifiable, Equatable {
    public var id: String { title }
    public var title: String
    public var input: String
    public var options: OptionValues
    public init(_ title: String, _ input: String, options: OptionValues = [:]) {
        self.title = title
        self.input = input
        self.options = options
    }
}

public struct ToolIO: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable { case text, binary, image, file, none }
    public var input: Kind
    public var output: Kind
    public var acceptsFiles: Bool
    public var dualInput: Bool
    public var inputLanguage: CodeLanguage
    public var outputLanguage: CodeLanguage

    public init(input: Kind = .text, output: Kind = .text, acceptsFiles: Bool = true, dualInput: Bool = false,
                inputLanguage: CodeLanguage = .plain, outputLanguage: CodeLanguage = .plain) {
        self.input = input
        self.output = output
        self.acceptsFiles = acceptsFiles
        self.dualInput = dualInput
        self.inputLanguage = inputLanguage
        self.outputLanguage = outputLanguage
    }

    public static let text = ToolIO()
    public static func text(_ inLang: CodeLanguage, _ outLang: CodeLanguage) -> ToolIO {
        ToolIO(inputLanguage: inLang, outputLanguage: outLang)
    }
    public static let generator = ToolIO(input: .none, output: .text, acceptsFiles: false)
    public static let imageIn = ToolIO(input: .image, output: .text)
    public static let fileIn = ToolIO(input: .file, output: .text)
}

// MARK: - Options

public enum OptionValue: Codable, Sendable, Hashable, CustomStringConvertible {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        }
    }

    public var boolValue: Bool {
        switch self {
        case .bool(let b): b
        case .int(let i): i != 0
        case .double(let d): d != 0
        case .string(let s): ["1", "true", "yes", "on"].contains(s.lowercased())
        }
    }
    public var intValue: Int {
        switch self {
        case .bool(let b): b ? 1 : 0
        case .int(let i): i
        case .double(let d): Int(d)
        case .string(let s): Int(s) ?? 0
        }
    }
    public var doubleValue: Double {
        switch self {
        case .bool(let b): b ? 1 : 0
        case .int(let i): Double(i)
        case .double(let d): d
        case .string(let s): Double(s) ?? 0
        }
    }
    public var stringValue: String {
        switch self {
        case .bool(let b): b ? "true" : "false"
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .string(let s): s
        }
    }
    public var description: String { stringValue }

    /// Parse a CLI string into the value kind of the given field.
    public static func parse(_ raw: String, like field: OptionField) -> OptionValue {
        switch field.defaultValue {
        case .bool: .bool(["1", "true", "yes", "on", ""].contains(raw.lowercased()))
        case .int: .int(Int(raw) ?? field.defaultValue.intValue)
        case .double: .double(Double(raw) ?? field.defaultValue.doubleValue)
        case .string: .string(raw)
        }
    }
}

public typealias OptionValues = [String: OptionValue]

public struct OptionChoice: Sendable, Hashable, Identifiable {
    public var id: String { value }
    public var value: String
    public var label: String
    public init(_ value: String, _ label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }
}

public struct OptionField: Sendable, Identifiable, Hashable {
    public enum Kind: Sendable, Hashable {
        case toggle
        case picker([OptionChoice])
        case segmented([OptionChoice])
        case stepper(min: Int, max: Int, step: Int)
        case slider(min: Double, max: Double)
        case text(placeholder: String)
        case secret(placeholder: String)
        case multiline(placeholder: String)
    }

    public var id: String { key }
    public var key: String
    public var label: String
    public var kind: Kind
    public var defaultValue: OptionValue
    public var help: String?
    /// Only show this field when another field has one of these values.
    public var visibleWhen: (key: String, values: [String])?

    /// Whether this field should be shown. A condition on an option the tool does not declare counts as met,
    /// so shared fields (e.g. "indent, only when mode = format") still appear on tools without a mode.
    public func isVisible(among fields: [OptionField], value: (String) -> String) -> Bool {
        guard let c = visibleWhen, fields.contains(where: { $0.key == c.key }) else { return true }
        return c.values.contains(value(c.key))
    }
    /// Fields in the same group render together; advanced fields live in the inspector.
    public var advanced: Bool

    public init(_ key: String, _ label: String, _ kind: Kind, default defaultValue: OptionValue,
                help: String? = nil, visibleWhen: (key: String, values: [String])? = nil, advanced: Bool = false) {
        self.key = key
        self.label = label
        self.kind = kind
        self.defaultValue = defaultValue
        self.help = help
        self.visibleWhen = visibleWhen
        self.advanced = advanced
    }

    public static func == (lhs: OptionField, rhs: OptionField) -> Bool { lhs.key == rhs.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }

    // Convenience constructors
    public static func toggle(_ key: String, _ label: String, default value: Bool = false, help: String? = nil,
                              visibleWhen: (key: String, values: [String])? = nil, advanced: Bool = false) -> OptionField {
        OptionField(key, label, .toggle, default: .bool(value), help: help, visibleWhen: visibleWhen, advanced: advanced)
    }
    public static func picker(_ key: String, _ label: String, _ choices: [OptionChoice], default value: String,
                              help: String? = nil, visibleWhen: (key: String, values: [String])? = nil, advanced: Bool = false) -> OptionField {
        OptionField(key, label, .picker(choices), default: .string(value), help: help, visibleWhen: visibleWhen, advanced: advanced)
    }
    public static func segmented(_ key: String, _ label: String, _ choices: [OptionChoice], default value: String,
                                 help: String? = nil, visibleWhen: (key: String, values: [String])? = nil) -> OptionField {
        OptionField(key, label, .segmented(choices), default: .string(value), help: help, visibleWhen: visibleWhen)
    }
    public static func stepper(_ key: String, _ label: String, min: Int, max: Int, step: Int = 1, default value: Int,
                               help: String? = nil, visibleWhen: (key: String, values: [String])? = nil, advanced: Bool = false) -> OptionField {
        OptionField(key, label, .stepper(min: min, max: max, step: step), default: .int(value), help: help, visibleWhen: visibleWhen, advanced: advanced)
    }
    public static func slider(_ key: String, _ label: String, min: Double, max: Double, default value: Double, help: String? = nil,
                              visibleWhen: (key: String, values: [String])? = nil, advanced: Bool = false) -> OptionField {
        OptionField(key, label, .slider(min: min, max: max), default: .double(value), help: help, visibleWhen: visibleWhen, advanced: advanced)
    }
    public static func text(_ key: String, _ label: String, placeholder: String = "", default value: String = "",
                            help: String? = nil, visibleWhen: (key: String, values: [String])? = nil, advanced: Bool = false) -> OptionField {
        OptionField(key, label, .text(placeholder: placeholder), default: .string(value), help: help, visibleWhen: visibleWhen, advanced: advanced)
    }
    public static func secret(_ key: String, _ label: String, placeholder: String = "", help: String? = nil,
                              visibleWhen: (key: String, values: [String])? = nil) -> OptionField {
        OptionField(key, label, .secret(placeholder: placeholder), default: .string(""), help: help, visibleWhen: visibleWhen)
    }
    public static func multiline(_ key: String, _ label: String, placeholder: String = "", help: String? = nil,
                                 visibleWhen: (key: String, values: [String])? = nil) -> OptionField {
        OptionField(key, label, .multiline(placeholder: placeholder), default: .string(""), help: help, visibleWhen: visibleWhen, advanced: true)
    }

    /// Simple mode switch shared by encode/decode style tools.
    public static func mode(_ choices: [OptionChoice], default value: String) -> OptionField {
        .segmented("mode", "Mode", choices, default: value)
    }
    public static let encodeDecode: OptionField = .mode([.init("encode", "Encode"), .init("decode", "Decode")], default: "encode")
}

public extension Array where Element == OptionField {
    var defaults: OptionValues {
        var v: OptionValues = [:]
        for f in self { v[f.key] = f.defaultValue }
        return v
    }
}

/// Options structs are plain Codable values; they are produced from `OptionValues`
/// by merging the field defaults with the user's overrides.
public protocol ToolOptions: Codable, Sendable {
    init()
}

public struct NoOptions: ToolOptions {
    public init() {}
}

public enum OptionDecoder {
    public static func decode<T: ToolOptions>(_ type: T.Type, from values: OptionValues, fields: [OptionField]) throws -> T {
        // Start from the struct's own defaults so keys that have no OptionField still decode.
        var merged = encode(T())
        for (k, v) in fields.defaults { merged[k] = v }
        for (k, v) in values { merged[k] = v }
        if merged.isEmpty { return T() }
        let data = try JSONEncoder().encode(merged)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ToolError("Invalid options: \(error.localizedDescription)")
        }
    }

    public static func encode<T: ToolOptions>(_ options: T) -> OptionValues {
        guard let data = try? JSONEncoder().encode(options),
              let values = try? JSONDecoder().decode(OptionValues.self, from: data) else { return [:] }
        return values
    }
}

// MARK: - The protocol

public protocol DevTool: Sendable {
    static var id: String { get }
    static var name: String { get }
    static var summary: String { get }
    static var category: ToolCategory { get }
    static var symbol: String { get }
    static var keywords: [String] { get }
    static var samples: [ToolSample] { get }
    static var io: ToolIO { get }
    static var optionFields: [OptionField] { get }
    static var sideEffects: Bool { get }
    static var historyEnabledByDefault: Bool { get }

    associatedtype Options: ToolOptions

    init()
    func run(_ input: ToolInput, options: Options) async throws -> ToolOutput
    static func detect(_ sample: String) -> DetectionScore?
}

public extension DevTool {
    static var keywords: [String] { [] }
    static var samples: [ToolSample] { [] }
    static var io: ToolIO { .text }
    static var optionFields: [OptionField] { [] }
    static var sideEffects: Bool { false }
    static var historyEnabledByDefault: Bool { true }
    static func detect(_ sample: String) -> DetectionScore? { nil }
}

// MARK: - Entitlements seam

public enum Entitlement: String, Sendable, Codable {
    case free, pro
}

public protocol EntitlementProviding: Sendable {
    func has(_ entitlement: Entitlement) -> Bool
}

public struct AllEntitlements: EntitlementProviding {
    public init() {}
    public func has(_ entitlement: Entitlement) -> Bool { true }
}
