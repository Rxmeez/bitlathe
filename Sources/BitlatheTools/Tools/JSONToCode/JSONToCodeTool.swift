import Foundation
import BitlatheCore

/// Infers a type model from sample JSON and emits it in ten languages.
public struct JSONToCodeTool: DevTool {
    public static let id = "json.to-code"
    public static let name = "JSON → Code Types"
    public static let summary = "Generate TypeScript, Swift, Go, Kotlin, Rust, Python, C#, Java or JSON Schema from JSON"
    public static let category = ToolCategory.convert
    public static let symbol = "curlybraces.square"
    public static let keywords = ["json", "typescript", "swift", "codable", "go", "struct", "kotlin", "rust", "serde", "python", "dataclass", "pydantic", "csharp", "java", "schema", "quicktype", "types"]
    public static let io = ToolIO.text(.json, .typescript)
    public static let samples = [ToolSample("API response", #"{"id":123,"name":"Ada","email":null,"isAdmin":true,"score":9.5,"tags":["a","b"],"address":{"street":"1 Main St","zip":"02134"},"orders":[{"id":1,"total":10.5,"items":[{"sku":"X1","qty":2}]},{"id":2,"total":3,"note":"gift"}]}"#)]
    public static let optionFields: [OptionField] = [
        .picker("language", "Language", [.init("typescript", "TypeScript"), .init("swift", "Swift Codable"), .init("go", "Go"), .init("kotlin", "Kotlin"), .init("rust", "Rust serde"),
                                         .init("python", "Python dataclass"), .init("pydantic", "Pydantic"), .init("csharp", "C#"), .init("java", "Java"), .init("jsonschema", "JSON Schema")], default: "typescript"),
        .text("rootName", "Root type", placeholder: "Root", default: "Root"),
        .picker("naming", "Properties", [.init("keep", "Keep names"), .init("camel", "camelCase"), .init("snake", "snake_case")], default: "keep"),
        .toggle("optionals", "Nullable → optional", default: true, help: "Fields that are null or missing in some objects become optional"),
        .picker("swiftKind", "Swift", [.init("struct", "struct"), .init("class", "final class")], default: "struct", visibleWhen: ("language", ["swift"])),
        .toggle("swiftVar", "Use var", visibleWhen: ("language", ["swift"])),
        .picker("tsKind", "TS", [.init("interface", "interface"), .init("type", "type")], default: "interface", visibleWhen: ("language", ["typescript"])),
        .toggle("tsExport", "export", default: true, visibleWhen: ("language", ["typescript"])),
        .toggle("goPointers", "Pointers for optionals", default: true, visibleWhen: ("language", ["go"])),
        .toggle("kotlinSerialization", "@Serializable", visibleWhen: ("language", ["kotlin"])),
        .toggle("javaRecords", "Records", default: true, visibleWhen: ("language", ["java"])),
    ]
    public struct Options: ToolOptions {
        public var language = "typescript"
        public var rootName = "Root"
        public var naming = "keep"
        public var optionals = true
        public var swiftKind = "struct"
        public var swiftVar = false
        public var tsKind = "interface"
        public var tsExport = true
        public var goPointers = true
        public var kotlinSerialization = false
        public var javaRecords = true
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let json = try JSONParser.parse(text, options: .json5)
        var model = TypeModel(rootName: options.rootName.isEmpty ? "Root" : options.rootName, naming: options.naming, optionals: options.optionals)
        if case .object = json {
            _ = model.infer(json, name: model.rootName)
        } else {
            // Root is an array or scalar: infer the element as <Root>Element and wrap it in a root type.
            let rootShape = model.infer(json, name: model.rootName + "Element")
            model.types.append(TypeModel.TypeDef(name: model.rootName, fields: [TypeModel.Field(name: "value", jsonName: "value", shape: rootShape, optional: false)]))
        }
        let emitter: any CodeEmitter = switch options.language {
        case "swift": SwiftEmitter(kind: options.swiftKind, useVar: options.swiftVar)
        case "go": GoEmitter(pointers: options.goPointers)
        case "kotlin": KotlinEmitter(serializable: options.kotlinSerialization)
        case "rust": RustEmitter()
        case "python": PythonEmitter(pydantic: false)
        case "pydantic": PythonEmitter(pydantic: true)
        case "csharp": CSharpEmitter()
        case "java": JavaEmitter(records: options.javaRecords)
        case "jsonschema": JSONSchemaEmitter()
        default: TypeScriptEmitter(kind: options.tsKind, export: options.tsExport)
        }
        let code = emitter.emit(model)
        return ToolOutput(text: code, language: emitter.language, metadata: [MetaRow("Types", "\(model.types.count)")])
    }
}

// MARK: - Type model

struct TypeModel {
    indirect enum Shape: Equatable {
        case null, bool, int, double, string, any
        case array(Shape)
        case object(String)   // reference to a TypeDef by name

        func merged(with other: Shape) -> Shape {
            if self == other { return self }
            switch (self, other) {
            case (.null, let o), (let o, .null): return o
            case (.int, .double), (.double, .int): return .double
            case (.array(let a), .array(let b)): return .array(a.merged(with: b))
            default: return .any
            }
        }
    }

    struct Field {
        var name: String
        var jsonName: String
        var shape: Shape
        var optional: Bool
    }

    struct TypeDef {
        var name: String
        var fields: [Field]
    }

    let rootName: String
    let naming: String
    let optionals: Bool
    var types: [TypeDef] = []
    private var usedNames: Set<String> = []

    init(rootName: String, naming: String, optionals: Bool) {
        self.rootName = Self.pascal(rootName)
        self.naming = naming
        self.optionals = optionals
    }

    mutating func infer(_ v: JSONValue, name: String) -> Shape {
        switch v {
        case .null: return .null
        case .bool: return .bool
        case .number(let s): return Int(s) != nil ? .int : .double
        case .string: return .string
        case .array(let a):
            if a.isEmpty { return .array(.any) }
            let objects = a.compactMap { $0.objectValue != nil ? $0 : nil }
            if objects.count == a.count {
                let typeName = uniqueName(Self.singular(Self.pascal(name)))
                var fields: [String: (Shape, Int)] = [:]
                var order: [String] = []
                for obj in objects {
                    guard case .object(let o) = obj else { continue }
                    for (k, val) in o {
                        let s = infer(val, name: k)
                        if let existing = fields[k] { fields[k] = (existing.0.merged(with: s), existing.1 + 1) }
                        else { fields[k] = (s, 1); order.append(k) }
                    }
                }
                let def = TypeDef(name: typeName, fields: order.map { k in
                    let (shape, count) = fields[k]!   // swiftlint:disable:this force_unwrapping
                    return Field(name: fieldName(k), jsonName: k, shape: shape == .null ? .any : shape, optional: optionals && (count < objects.count || shape == .null || fieldIsNullable(k, in: objects)))
                })
                types.append(def)
                return .array(.object(typeName))
            }
            var shape = infer(a[0], name: name)
            for item in a.dropFirst() { shape = shape.merged(with: infer(item, name: name)) }
            return .array(shape)
        case .object(let o):
            let typeName = uniqueName(Self.pascal(name))
            var fields: [Field] = []
            for (k, val) in o {
                let s = infer(val, name: k)
                fields.append(Field(name: fieldName(k), jsonName: k, shape: s == .null ? .any : s, optional: optionals && s == .null))
            }
            types.append(TypeDef(name: typeName, fields: fields))
            return .object(typeName)
        }
    }

    private func fieldIsNullable(_ key: String, in objects: [JSONValue]) -> Bool {
        objects.contains { $0[key]?.isNull == true }
    }

    private mutating func uniqueName(_ base: String) -> String {
        var name = base.isEmpty ? "Item" : base
        var i = 2
        while usedNames.contains(name) { name = base + String(i); i += 1 }
        usedNames.insert(name)
        return name
    }

    func fieldName(_ k: String) -> String {
        switch naming {
        case "camel": Self.camel(k)
        case "snake": Self.snake(k)
        default: k
        }
    }

    static func words(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var prev: Character?
        for c in s {
            if c.isLetter || c.isNumber {
                if let p = prev, p.isLowercase, c.isUppercase, !current.isEmpty { out.append(current); current = "" }
                else if let p = prev, p.isNumber != c.isNumber, !current.isEmpty, c.isNumber { out.append(current); current = "" }
                current.append(c)
            } else if !current.isEmpty { out.append(current); current = "" }
            prev = c
        }
        if !current.isEmpty { out.append(current) }
        return out.map { $0.lowercased() }
    }
    static func pascal(_ s: String) -> String { words(s).map { $0.capitalizedFirst() }.joined() }
    static func camel(_ s: String) -> String {
        let w = words(s)
        guard let f = w.first else { return s }
        return f + w.dropFirst().map { $0.capitalizedFirst() }.joined()
    }
    static func snake(_ s: String) -> String { words(s).joined(separator: "_") }
    static func singular(_ s: String) -> String {
        if s.hasSuffix("ies"), s.count > 3 { return String(s.dropLast(3)) + "y" }
        if s.hasSuffix("ses") || s.hasSuffix("xes") || s.hasSuffix("ches") || s.hasSuffix("shes") { return String(s.dropLast(2)) }
        if s.hasSuffix("s"), !s.hasSuffix("ss"), s.count > 2 { return String(s.dropLast()) }
        return s
    }
    static func isIdentifier(_ s: String) -> Bool { s.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil }
}

protocol CodeEmitter {
    var language: CodeLanguage { get }
    func emit(_ model: TypeModel) -> String
}

private func ordered(_ model: TypeModel) -> [TypeModel.TypeDef] {
    // Root last for languages where order does not matter, root first for readability.
    var defs = model.types
    if let i = defs.firstIndex(where: { $0.name == model.rootName }) { let root = defs.remove(at: i); defs.insert(root, at: 0) }
    return defs
}

struct TypeScriptEmitter: CodeEmitter {
    let kind: String
    let export: Bool
    var language: CodeLanguage { .typescript }
    func type(_ s: TypeModel.Shape) -> String {
        switch s {
        case .null: "null"
        case .bool: "boolean"
        case .int, .double: "number"
        case .string: "string"
        case .any: "unknown"
        case .array(let i): type(i).contains(" ") ? "(\(type(i)))[]" : "\(type(i))[]"
        case .object(let n): n
        }
    }
    func emit(_ model: TypeModel) -> String {
        ordered(model).map { def in
            let head = export ? "export " : ""
            let open = kind == "type" ? "\(head)type \(def.name) = {" : "\(head)interface \(def.name) {"
            let body = def.fields.map { f in
                let name = TypeModel.isIdentifier(f.name) ? f.name : "\"\(f.name)\""
                return "  \(name)\(f.optional ? "?" : ""): \(type(f.shape))\(f.optional && f.shape != .any ? " | null" : "");"
            }.joined(separator: "\n")
            return open + "\n" + body + "\n}" + (kind == "type" ? ";" : "")
        }.joined(separator: "\n\n")
    }
}

struct SwiftEmitter: CodeEmitter {
    let kind: String
    let useVar: Bool
    var language: CodeLanguage { .swift }
    func type(_ s: TypeModel.Shape) -> String {
        switch s {
        case .null, .any: "AnyCodable"
        case .bool: "Bool"
        case .int: "Int"
        case .double: "Double"
        case .string: "String"
        case .array(let i): "[\(type(i))]"
        case .object(let n): n
        }
    }
    static let keywords: Set<String> = ["class", "struct", "enum", "protocol", "func", "var", "let", "import", "default", "case", "switch", "if", "else", "for", "while", "return", "in", "is", "as", "self", "Self", "Type", "init", "deinit", "extension", "operator", "static", "public", "private", "internal", "true", "false", "nil", "where", "throws", "try", "catch", "guard", "defer", "repeat", "do", "break", "continue", "fallthrough", "subscript", "typealias", "associatedtype", "inout", "super", "Any", "some"]
    func emit(_ model: TypeModel) -> String {
        var usesAny = false
        let decl = useVar ? "var" : "let"
        let out = ordered(model).map { def in
            var lines = ["\(kind == "class" ? "final class" : "struct") \(def.name): Codable {"]
            var keys: [String] = []
            var needsKeys = false
            for f in def.fields {
                var name = TypeModel.camel(f.jsonName)
                if name.isEmpty { name = "value" }
                if Self.keywords.contains(name) { name = "`\(name)`" }
                if name.replacingOccurrences(of: "`", with: "") != f.jsonName { needsKeys = true }
                let t = type(f.shape)
                if t.contains("AnyCodable") { usesAny = true }
                lines.append("    \(decl) \(name): \(t)\(f.optional ? "?" : "")")
                keys.append(name.replacingOccurrences(of: "`", with: "") == f.jsonName ? "case \(name)" : "case \(name) = \"\(f.jsonName)\"")
            }
            if needsKeys {
                lines.append("")
                lines.append("    enum CodingKeys: String, CodingKey {")
                lines += keys.map { "        \($0)" }
                lines.append("    }")
            }
            lines.append("}")
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
        var header = "import Foundation\n\n"
        if usesAny {
            header += """
            /// Wraps values whose type varies or is unknown (null in the sample).
            struct AnyCodable: Codable {
                let value: Any?
                init(from decoder: Decoder) throws {
                    let c = try decoder.singleValueContainer()
                    if c.decodeNil() { value = nil }
                    else if let v = try? c.decode(Bool.self) { value = v }
                    else if let v = try? c.decode(Int.self) { value = v }
                    else if let v = try? c.decode(Double.self) { value = v }
                    else if let v = try? c.decode(String.self) { value = v }
                    else if let v = try? c.decode([AnyCodable].self) { value = v.map(\\.value) }
                    else if let v = try? c.decode([String: AnyCodable].self) { value = v.mapValues(\\.value) }
                    else { value = nil }
                }
                func encode(to encoder: Encoder) throws {
                    var c = encoder.singleValueContainer()
                    switch value {
                    case nil: try c.encodeNil()
                    case let v as Bool: try c.encode(v)
                    case let v as Int: try c.encode(v)
                    case let v as Double: try c.encode(v)
                    case let v as String: try c.encode(v)
                    default: try c.encode(String(describing: value!))
                    }
                }
            }


            """
        }
        return header + out
    }
}

struct GoEmitter: CodeEmitter {
    let pointers: Bool
    var language: CodeLanguage { .go }
    func type(_ s: TypeModel.Shape) -> String {
        switch s {
        case .null, .any: "interface{}"
        case .bool: "bool"
        case .int: "int64"
        case .double: "float64"
        case .string: "string"
        case .array(let i): "[]\(type(i))"
        case .object(let n): n
        }
    }
    func emit(_ model: TypeModel) -> String {
        "package main\n\n" + ordered(model).map { def in
            let width = def.fields.map { TypeModel.pascal($0.jsonName).count }.max() ?? 0
            let body = def.fields.map { f in
                var t = type(f.shape)
                if f.optional, pointers, !t.hasPrefix("[]"), t != "interface{}" { t = "*" + t }
                let name = TypeModel.pascal(f.jsonName).padding(toLength: width, withPad: " ", startingAt: 0)
                return "\t\(name) \(t) `json:\"\(f.jsonName)\(f.optional ? ",omitempty" : "")\"`"
            }.joined(separator: "\n")
            return "type \(def.name) struct {\n\(body)\n}"
        }.joined(separator: "\n\n")
    }
}

struct KotlinEmitter: CodeEmitter {
    let serializable: Bool
    var language: CodeLanguage { .kotlin }
    func type(_ s: TypeModel.Shape) -> String {
        switch s {
        case .null, .any: "Any"
        case .bool: "Boolean"
        case .int: "Long"
        case .double: "Double"
        case .string: "String"
        case .array(let i): "List<\(type(i))>"
        case .object(let n): n
        }
    }
    func emit(_ model: TypeModel) -> String {
        let header = serializable ? "import kotlinx.serialization.SerialName\nimport kotlinx.serialization.Serializable\n\n" : ""
        return header + ordered(model).map { def in
            let body = def.fields.map { f in
                let name = TypeModel.camel(f.jsonName)
                let ann = serializable && name != f.jsonName ? "    @SerialName(\"\(f.jsonName)\")\n" : ""
                return "\(ann)    val \(name): \(type(f.shape))\(f.optional ? "? = null" : "")"
            }.joined(separator: ",\n")
            return (serializable ? "@Serializable\n" : "") + "data class \(def.name)(\n\(body)\n)"
        }.joined(separator: "\n\n")
    }
}

struct RustEmitter: CodeEmitter {
    var language: CodeLanguage { .rust }
    func type(_ s: TypeModel.Shape) -> String {
        switch s {
        case .null, .any: "serde_json::Value"
        case .bool: "bool"
        case .int: "i64"
        case .double: "f64"
        case .string: "String"
        case .array(let i): "Vec<\(type(i))>"
        case .object(let n): n
        }
    }
    static let keywords: Set<String> = ["type", "match", "ref", "struct", "enum", "fn", "let", "mut", "pub", "impl", "use", "mod", "self", "super", "crate", "where", "as", "in", "loop", "move", "return", "static", "trait", "true", "false", "while", "for", "if", "else", "break", "continue", "const", "dyn", "async", "await"]
    func emit(_ model: TypeModel) -> String {
        "use serde::{Deserialize, Serialize};\n\n" + ordered(model).map { def in
            let body = def.fields.map { f in
                var name = TypeModel.snake(f.jsonName)
                if Self.keywords.contains(name) { name = "r#" + name }
                let rename = name.replacingOccurrences(of: "r#", with: "") != f.jsonName ? "    #[serde(rename = \"\(f.jsonName)\")]\n" : ""
                let t = f.optional ? "Option<\(type(f.shape))>" : type(f.shape)
                return "\(rename)    pub \(name): \(t),"
            }.joined(separator: "\n")
            return "#[derive(Debug, Clone, Serialize, Deserialize)]\npub struct \(def.name) {\n\(body)\n}"
        }.joined(separator: "\n\n")
    }
}

struct PythonEmitter: CodeEmitter {
    let pydantic: Bool
    var language: CodeLanguage { .python }
    func type(_ s: TypeModel.Shape) -> String {
        switch s {
        case .null, .any: "Any"
        case .bool: "bool"
        case .int: "int"
        case .double: "float"
        case .string: "str"
        case .array(let i): "list[\(type(i))]"
        case .object(let n): n
        }
    }
    func emit(_ model: TypeModel) -> String {
        var defs = ordered(model)
        defs.reverse()   // dependencies first
        let header = pydantic ? "from typing import Any, Optional\n\nfrom pydantic import BaseModel, Field\n\n\n" : "from dataclasses import dataclass, field\nfrom typing import Any, Optional\n\n\n"
        return header + defs.map { def in
            let body = def.fields.isEmpty ? "    pass" : def.fields.map { f in
                let name = TypeModel.snake(f.jsonName)
                let t = f.optional ? "Optional[\(type(f.shape))]" : type(f.shape)
                if pydantic {
                    let alias = name != f.jsonName ? "alias=\"\(f.jsonName)\"" : ""
                    let dflt = f.optional ? "None" : ""
                    let args = [dflt, alias].filter { !$0.isEmpty }.joined(separator: ", ")
                    return "    \(name): \(t)" + (args.isEmpty ? "" : " = Field(\(args))")
                }
                return "    \(name): \(t)" + (f.optional ? " = None" : "")
            }.joined(separator: "\n")
            let decorator = pydantic ? "" : "@dataclass\n"
            let base = pydantic ? "(BaseModel)" : ""
            return "\(decorator)class \(def.name)\(base):\n\(body)"
        }.joined(separator: "\n\n\n")
    }
}

struct CSharpEmitter: CodeEmitter {
    var language: CodeLanguage { .csharp }
    func type(_ s: TypeModel.Shape) -> String {
        switch s {
        case .null, .any: "object"
        case .bool: "bool"
        case .int: "long"
        case .double: "double"
        case .string: "string"
        case .array(let i): "List<\(type(i))>"
        case .object(let n): n
        }
    }
    func emit(_ model: TypeModel) -> String {
        "using System.Collections.Generic;\nusing System.Text.Json.Serialization;\n\n" + ordered(model).map { def in
            let body = def.fields.map { f in
                let t = type(f.shape)
                let nullable = f.optional && ["bool", "long", "double"].contains(t) ? t + "?" : t
                return "    [JsonPropertyName(\"\(f.jsonName)\")]\n    public \(nullable) \(TypeModel.pascal(f.jsonName)) { get; set; }"
            }.joined(separator: "\n\n")
            return "public class \(def.name)\n{\n\(body)\n}"
        }.joined(separator: "\n\n")
    }
}

struct JavaEmitter: CodeEmitter {
    let records: Bool
    var language: CodeLanguage { .java }
    func type(_ s: TypeModel.Shape) -> String {
        switch s {
        case .null, .any: "Object"
        case .bool: "Boolean"
        case .int: "Long"
        case .double: "Double"
        case .string: "String"
        case .array(let i): "List<\(type(i))>"
        case .object(let n): n
        }
    }
    func emit(_ model: TypeModel) -> String {
        "import java.util.List;\nimport com.fasterxml.jackson.annotation.JsonProperty;\n\n" + ordered(model).map { def in
            if records {
                let body = def.fields.map { f in "    @JsonProperty(\"\(f.jsonName)\") \(type(f.shape)) \(TypeModel.camel(f.jsonName))" }.joined(separator: ",\n")
                return "public record \(def.name)(\n\(body)\n) {}"
            }
            var lines = ["public class \(def.name) {"]
            for f in def.fields { lines.append("    @JsonProperty(\"\(f.jsonName)\")\n    private \(type(f.shape)) \(TypeModel.camel(f.jsonName));") }
            lines.append("")
            for f in def.fields {
                let n = TypeModel.camel(f.jsonName)
                let p = TypeModel.pascal(f.jsonName)
                lines.append("    public \(type(f.shape)) get\(p)() { return \(n); }")
                lines.append("    public void set\(p)(\(type(f.shape)) \(n)) { this.\(n) = \(n); }")
            }
            lines.append("}")
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

struct JSONSchemaEmitter: CodeEmitter {
    var language: CodeLanguage { .json }
    func schema(_ s: TypeModel.Shape, model: TypeModel) -> JSONValue {
        switch s {
        case .null: .object([(key: "type", value: .string("null"))])
        case .bool: .object([(key: "type", value: .string("boolean"))])
        case .int: .object([(key: "type", value: .string("integer"))])
        case .double: .object([(key: "type", value: .string("number"))])
        case .string: .object([(key: "type", value: .string("string"))])
        case .any: .object([])
        case .array(let i): .object([(key: "type", value: .string("array")), (key: "items", value: schema(i, model: model))])
        case .object(let n): .object([(key: "$ref", value: .string("#/$defs/\(n)"))])
        }
    }
    func emit(_ model: TypeModel) -> String {
        var defs: [(key: String, value: JSONValue)] = []
        for def in model.types {
            let props: [(key: String, value: JSONValue)] = def.fields.map { f in
                var s = schema(f.shape, model: model)
                if f.optional, case .object(var o) = s, let t = o.first(where: { $0.key == "type" })?.value.stringValue {
                    o = o.filter { $0.key != "type" }
                    o.insert((key: "type", value: .array([.string(t), .string("null")])), at: 0)
                    s = .object(o)
                }
                return (key: f.jsonName, value: s)
            }
            defs.append((key: def.name, value: .object([
                (key: "type", value: .string("object")),
                (key: "properties", value: .object(props)),
                (key: "required", value: .array(def.fields.filter { !$0.optional }.map { .string($0.jsonName) })),
                (key: "additionalProperties", value: .bool(false)),
            ])))
        }
        let root: JSONValue = .object([
            (key: "$schema", value: .string("https://json-schema.org/draft/2020-12/schema")),
            (key: "$ref", value: .string("#/$defs/\(model.rootName)")),
            (key: "$defs", value: .object(defs)),
        ])
        return JSONSerializer.string(root)
    }
}
