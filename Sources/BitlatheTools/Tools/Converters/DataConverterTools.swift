import Foundation
import BitlatheCore

// MARK: - YAML ⇄ JSON

public struct YAMLJSONTool: DevTool {
    public static let id = "convert.yaml-json"
    public static let name = "YAML ⇄ JSON"
    public static let summary = "Convert between YAML and JSON in either direction"
    public static let category = ToolCategory.convert
    public static let symbol = "arrow.left.arrow.right.square"
    public static let keywords = ["yaml", "yml", "json", "convert"]
    public static let samples = [ToolSample("YAML → JSON", "name: Bitlathe\nfeatures:\n  - fast\n  - offline\nversion: 1.0\nstable: true"),
                                 ToolSample("JSON → YAML", #"{"name":"Bitlathe","features":["fast","offline"],"nested":{"ok":true}}"#, options: ["direction": .string("json2yaml")])]
    public static let optionFields: [OptionField] = [
        .segmented("direction", "Direction", [.init("auto", "Auto"), .init("yaml2json", "YAML → JSON"), .init("json2yaml", "JSON → YAML")], default: "auto"),
        .picker("indent", "Indent", [.init("2", "2 spaces"), .init("4", "4 spaces")], default: "2"),
        .toggle("sortKeys", "Sort keys"),
    ]
    public struct Options: ToolOptions {
        public var direction = "auto"
        public var indent = "2"
        public var sortKeys = false
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let toJSON: Bool = switch options.direction {
        case "yaml2json": true
        case "json2yaml": false
        default: !Detect.looksLikeJSON(text.trimmed())
        }
        let indent = Int(options.indent) ?? 2
        if toJSON {
            let docs = try YAMLBridge.parse(text)
            let v: JSONValue = docs.count == 1 ? docs[0] : .array(docs)
            var o = JSONSerializerOptions()
            o.indent = indent
            o.sortKeys = options.sortKeys
            return ToolOutput(text: JSONSerializer.string(v, options: o), language: .json, metadata: [MetaRow("Documents", "\(docs.count)")])
        } else {
            let v = try JSONParser.parse(text, options: .json5)
            return ToolOutput(text: try YAMLBridge.serialize(v, indent: indent, sortKeys: options.sortKeys), language: .yaml)
        }
    }
    public static func detect(_ s: String) -> DetectionScore? {
        guard let y = YAMLFormatTool.detect(s), y.confidence >= 0.7 else { return nil }
        return DetectionScore(0.6, "YAML → JSON")
    }
}

// MARK: - JSON ⇄ CSV

public struct JSONCSVTool: DevTool {
    public static let id = "convert.json-csv"
    public static let name = "JSON ⇄ CSV"
    public static let summary = "Convert arrays of objects to CSV/TSV and back"
    public static let category = ToolCategory.convert
    public static let symbol = "tablecells"
    public static let keywords = ["json", "csv", "tsv", "table", "spreadsheet", "convert"]
    public static let samples = [ToolSample("JSON → CSV", #"[{"id":1,"name":"Ada","langs":["en","fr"]},{"id":2,"name":"Linus","address":{"city":"Portland"}}]"#),
                                 ToolSample("CSV → JSON", "id,name,active\n1,Ada,true\n2,\"Smith, John\",false", options: ["direction": .string("csv2json")])]
    public static let optionFields: [OptionField] = [
        .segmented("direction", "Direction", [.init("auto", "Auto"), .init("json2csv", "JSON → CSV"), .init("csv2json", "CSV → JSON")], default: "auto"),
        .picker("delimiter", "Delimiter", [.init("auto", "Auto"), .init(",", "Comma"), .init("\t", "Tab"), .init(";", "Semicolon"), .init("|", "Pipe")], default: "auto"),
        .toggle("flatten", "Flatten nested", default: true, help: "address.city style columns for nested objects"),
        .toggle("header", "First row is header", default: true, visibleWhen: ("direction", ["auto", "csv2json"])),
        .toggle("typed", "Infer types", default: true, visibleWhen: ("direction", ["auto", "csv2json"])),
    ]
    public struct Options: ToolOptions {
        public var direction = "auto"
        public var delimiter = "auto"
        public var flatten = true
        public var header = true
        public var typed = true
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let toCSV: Bool = switch options.direction {
        case "json2csv": true
        case "csv2json": false
        default: Detect.looksLikeJSON(text.trimmed())
        }
        if toCSV {
            let v = try JSONParser.parse(text, options: .json5)
            let rowsIn: [JSONValue]
            switch v {
            case .array(let a): rowsIn = a
            case .object(let o):
                if let first = o.first(where: { $0.value.arrayValue != nil }), o.count == 1 { rowsIn = first.value.arrayValue ?? [] } else { rowsIn = [v] }
            default: throw ToolError("Expected an array of objects", hint: "CSV needs rows; wrap the value in [ ]")
            }
            var columns: [String] = []
            var flatRows: [[String: String]] = []
            for r in rowsIn {
                var flat: [String: String] = [:]
                Self.flatten(r, prefix: "", flatten: options.flatten, into: &flat, order: &columns)
                flatRows.append(flat)
            }
            let delim: Character = options.delimiter == "auto" ? "," : Character(options.delimiter)
            let out = CSV.write(header: columns, rows: flatRows.map { row in columns.map { row[$0] ?? "" } }, delimiter: delim)
            return ToolOutput(text: out, language: .csv, metadata: [MetaRow("Rows", "\(flatRows.count)"), MetaRow("Columns", "\(columns.count)")])
        } else {
            let table = try CSV.parse(text, delimiter: options.delimiter == "auto" ? nil : Character(options.delimiter), hasHeader: options.header)
            let objects: [JSONValue] = table.rows.map { row in
                .object(zip(table.header, row).map { (key: $0, value: options.typed ? CSV.typed($1) : .string($1)) })
            }
            var o = JSONSerializerOptions()
            o.indent = 2
            return ToolOutput(text: JSONSerializer.string(.array(objects), options: o), language: .json,
                              metadata: [MetaRow("Rows", "\(table.rows.count)"), MetaRow("Columns", "\(table.header.count)"), MetaRow("Delimiter", table.delimiter == "\t" ? "tab" : String(table.delimiter))])
        }
    }

    static func flatten(_ v: JSONValue, prefix: String, flatten: Bool, into out: inout [String: String], order: inout [String]) {
        switch v {
        case .object(let o) where flatten || prefix.isEmpty:
            for (k, val) in o { Self.flatten(val, prefix: prefix.isEmpty ? k : "\(prefix).\(k)", flatten: flatten, into: &out, order: &order) }
        case .array(let a) where flatten && a.allSatisfy({ $0.objectValue != nil || $0.arrayValue != nil }):
            for (i, val) in a.enumerated() { Self.flatten(val, prefix: "\(prefix)[\(i)]", flatten: flatten, into: &out, order: &order) }
        default:
            let key = prefix.isEmpty ? "value" : prefix
            if !order.contains(key) { order.append(key) }
            switch v {
            case .string(let s): out[key] = s
            case .null: out[key] = ""
            case .array, .object: out[key] = JSONSerializer.string(v, options: .minified)
            default: out[key] = XMLJSON.scalar(v)
            }
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard s.contains("\n"), !s.hasPrefix("{"), !s.hasPrefix("["), !s.hasPrefix("<") else { return nil }
        let lines = s.split(separator: "\n").prefix(20)
        guard lines.count >= 2 else { return nil }
        let delim = CSV.sniffDelimiter(s)
        let counts = lines.map { $0.filter { $0 == delim }.count }
        guard let first = counts.first, first >= 1, counts.allSatisfy({ $0 == first }) else { return nil }
        if delim == ";" || delim == "|" { return DetectionScore(0.6, "Delimited rows") }
        if s.contains(": ") && delim == "," { return nil }
        return DetectionScore(0.65, "CSV rows → JSON", options: ["direction": .string("csv2json")])
    }
}

// MARK: - JSON ⇄ TOML

public struct JSONTOMLTool: DevTool {
    public static let id = "convert.json-toml"
    public static let name = "JSON ⇄ TOML"
    public static let summary = "Convert between JSON and TOML"
    public static let category = ToolCategory.convert
    public static let symbol = "doc.text.below.ecg"
    public static let keywords = ["json", "toml", "convert", "cargo", "pyproject"]
    public static let samples = [ToolSample("TOML → JSON", "title = \"Example\"\n[owner]\nname = \"Tom\"\n[database]\nports = [8000, 8001]\nenabled = true"),
                                 ToolSample("JSON → TOML", #"{"package":{"name":"bl","version":"0.1.0"},"dependencies":{"serde":"1"}}"#, options: ["direction": .string("json2toml")])]
    public static let optionFields: [OptionField] = [
        .segmented("direction", "Direction", [.init("auto", "Auto"), .init("toml2json", "TOML → JSON"), .init("json2toml", "JSON → TOML")], default: "auto"),
    ]
    public struct Options: ToolOptions {
        public var direction = "auto"
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let toJSON: Bool = switch options.direction {
        case "toml2json": true
        case "json2toml": false
        default: !Detect.looksLikeJSON(text.trimmed())
        }
        if toJSON {
            return ToolOutput(text: JSONSerializer.string(try TOMLBridge.parse(text)), language: .json)
        }
        return ToolOutput(text: try TOMLBridge.serialize(try JSONParser.parse(text, options: .json5)).trimmed(), language: .toml)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        guard let t = TOMLFormatTool.detect(s), t.confidence >= 0.8 else { return nil }
        return DetectionScore(0.55, "TOML → JSON")
    }
}

// MARK: - JSON ⇄ XML

public struct JSONXMLTool: DevTool {
    public static let id = "convert.json-xml"
    public static let name = "JSON ⇄ XML"
    public static let summary = "Convert between JSON and XML (attributes as @keys, text as #text)"
    public static let category = ToolCategory.convert
    public static let symbol = "chevron.left.forwardslash.chevron.right"
    public static let keywords = ["json", "xml", "convert", "soap", "plist"]
    public static let samples = [ToolSample("XML → JSON", "<library name=\"Main\"><book id=\"1\"><title>Dune</title><year>1965</year></book><book id=\"2\"><title>Emma</title></book></library>"),
                                 ToolSample("JSON → XML", #"{"note":{"@priority":"high","to":"Ada","body":"Hello"}}"#, options: ["direction": .string("json2xml")])]
    public static let optionFields: [OptionField] = [
        .segmented("direction", "Direction", [.init("auto", "Auto"), .init("xml2json", "XML → JSON"), .init("json2xml", "JSON → XML")], default: "auto"),
        .text("rootName", "Root", placeholder: "root", default: "root", visibleWhen: ("direction", ["auto", "json2xml"])),
        .text("attributesPrefix", "Attr prefix", placeholder: "@", default: "@", advanced: true),
        .text("textKey", "Text key", placeholder: "#text", default: "#text", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var direction = "auto"
        public var rootName = "root"
        public var attributesPrefix = "@"
        public var textKey = "#text"
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let toJSON: Bool = switch options.direction {
        case "xml2json": true
        case "json2xml": false
        default: text.trimmed().hasPrefix("<")
        }
        if toJSON {
            return ToolOutput(text: JSONSerializer.string(try XMLJSON.toJSON(text, attributesPrefix: options.attributesPrefix, textKey: options.textKey)), language: .json)
        }
        let v = try JSONParser.parse(text, options: .json5)
        return ToolOutput(text: XMLJSON.toXML(v, rootName: options.rootName.isEmpty ? "root" : options.rootName, attributesPrefix: options.attributesPrefix, textKey: options.textKey), language: .xml)
    }
}

// MARK: - JSON ⇄ Property List

public struct JSONPlistTool: DevTool {
    public static let id = "convert.json-plist"
    public static let name = "JSON ⇄ Property List"
    public static let summary = "Convert between JSON and XML or binary property lists"
    public static let category = ToolCategory.convert
    public static let symbol = "list.bullet.rectangle"
    public static let keywords = ["plist", "property list", "json", "xcode", "info.plist", "convert"]
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: true)
    public static let samples = [ToolSample("JSON → plist", #"{"CFBundleName":"Bitlathe","CFBundleVersion":"1","LSMinimumSystemVersion":"14.0","Features":["a","b"],"Sandboxed":true}"#),
                                 ToolSample("plist → JSON", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict><key>Name</key><string>Bitlathe</string><key>Count</key><integer>3</integer></dict></plist>")]
    public static let optionFields: [OptionField] = [
        .segmented("direction", "Direction", [.init("auto", "Auto"), .init("json2plist", "JSON → plist"), .init("plist2json", "plist → JSON")], default: "auto"),
        .segmented("format", "Format", [.init("xml", "XML"), .init("binary", "Binary")], default: "xml", visibleWhen: ("direction", ["auto", "json2plist"])),
    ]
    public struct Options: ToolOptions {
        public var direction = "auto"
        public var format = "xml"
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let data = input.data
        guard !data.isEmpty else { throw ToolError.emptyInput }
        let text = input.payload.text ?? ""
        let isBinaryPlist = data.starts(with: Array("bplist".utf8))
        let toPlist: Bool = switch options.direction {
        case "json2plist": true
        case "plist2json": false
        default: !(isBinaryPlist || text.contains("<plist") || text.trimmed().hasPrefix("<?xml"))
        }
        if toPlist {
            let v = try JSONParser.parse(text, options: .json5)
            let obj = v.foundationObject
            guard PropertyListSerialization.propertyList(obj, isValidFor: .xml) else {
                throw ToolError("This JSON cannot be a property list", hint: "Property lists cannot contain null values")
            }
            let fmt: PropertyListSerialization.PropertyListFormat = options.format == "binary" ? .binary : .xml
            let out = try PropertyListSerialization.data(fromPropertyList: obj, format: fmt, options: 0)
            if fmt == .binary { return ToolOutput(.data(out), metadata: [MetaRow("Size", ByteFormatter.string(out.count))], suggestedFileName: "output.plist") }
            return ToolOutput(text: String(decoding: out, as: UTF8.self).trimmed(), language: .xml)
        }
        var fmt = PropertyListSerialization.PropertyListFormat.xml
        let obj: Any
        do { obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &fmt) } catch {
            throw ToolError("Invalid property list: \((error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription)")
        }
        return ToolOutput(text: JSONSerializer.string(JSONValue(foundation: obj)), language: .json,
                          metadata: [MetaRow("Source format", fmt == .binary ? "Binary" : (fmt == .openStep ? "OpenStep" : "XML"))])
    }
    public static func detect(_ s: String) -> DetectionScore? {
        if s.contains("<plist") || s.hasPrefix("bplist") { return DetectionScore(0.95, "Property list") }
        return nil
    }
}

// MARK: - JSON ⇄ query string

public struct JSONQueryStringTool: DevTool {
    public static let id = "convert.json-query"
    public static let name = "JSON ⇄ Query String"
    public static let summary = "Convert URL query strings to JSON and back (supports a[b]=1 and a[]=1)"
    public static let category = ToolCategory.convert
    public static let symbol = "questionmark.square"
    public static let keywords = ["query", "querystring", "url", "params", "form", "json", "convert"]
    public static let samples = [ToolSample("Query → JSON", "page=2&sort=name&filter[status]=active&tags[]=a&tags[]=b&q=hello%20world"),
                                 ToolSample("JSON → query", #"{"page":2,"filter":{"status":"active"},"tags":["a","b"]}"#, options: ["direction": .string("json2query")])]
    public static let optionFields: [OptionField] = [
        .segmented("direction", "Direction", [.init("auto", "Auto"), .init("query2json", "Query → JSON"), .init("json2query", "JSON → Query")], default: "auto"),
        .toggle("typed", "Infer types", default: true),
    ]
    public struct Options: ToolOptions {
        public var direction = "auto"
        public var typed = true
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        var text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let toJSON: Bool = switch options.direction {
        case "query2json": true
        case "json2query": false
        default: !Detect.looksLikeJSON(text)
        }
        if toJSON {
            if let q = text.firstIndex(of: "?"), text.contains("://") || text.hasPrefix("?") { text = String(text[text.index(after: q)...]) }
            if let h = text.firstIndex(of: "#") { text = String(text[..<h]) }
            var root: [(key: String, value: JSONValue)] = []
            for pair in text.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = Self.decode(String(kv[0]))
                let raw = kv.count > 1 ? Self.decode(String(kv[1])) : ""
                let value: JSONValue = options.typed ? CSV.typed(raw) : .string(raw)
                Self.insert(path: Self.parseKey(key), value: value, into: &root)
            }
            return ToolOutput(text: JSONSerializer.string(.object(root)), language: .json, metadata: [MetaRow("Parameters", "\(text.split(separator: "&").count)")])
        }
        let v = try JSONParser.parse(text, options: .json5)
        guard case .object(let o) = v else { throw ToolError("Expected a JSON object") }
        var parts: [String] = []
        for (k, val) in o { Self.flatten(val, key: k, into: &parts) }
        return ToolOutput(text: parts.joined(separator: "&"))
    }

    static func decode(_ s: String) -> String { s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s }
    static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func parseKey(_ key: String) -> [String] {
        guard let b = key.firstIndex(of: "[") else { return [key] }
        var parts = [String(key[..<b])]
        let rest = key[b...]
        for m in rest.matches(of: /\[([^\]]*)\]/) { parts.append(String(m.1)) }
        return parts
    }

    static func insert(path: [String], value: JSONValue, into obj: inout [(key: String, value: JSONValue)]) {
        guard let first = path.first else { return }
        let rest = Array(path.dropFirst())
        if rest.isEmpty {
            if let i = obj.firstIndex(where: { $0.key == first }) {
                if case .array(var arr) = obj[i].value { arr.append(value); obj[i].value = .array(arr) } else { obj[i].value = .array([obj[i].value, value]) }
            } else {
                obj.append((key: first, value: value))
            }
            return
        }
        if rest == [""] {
            if let i = obj.firstIndex(where: { $0.key == first }), case .array(var arr) = obj[i].value { arr.append(value); obj[i].value = .array(arr) }
            else { obj.append((key: first, value: .array([value]))) }
            return
        }
        var child: [(key: String, value: JSONValue)] = []
        var existingIndex: Int?
        if let i = obj.firstIndex(where: { $0.key == first }) {
            existingIndex = i
            if case .object(let o) = obj[i].value { child = o }
        }
        insert(path: rest, value: value, into: &child)
        if let i = existingIndex { obj[i].value = .object(child) } else { obj.append((key: first, value: .object(child))) }
    }

    static func flatten(_ v: JSONValue, key: String, into parts: inout [String]) {
        switch v {
        case .object(let o): for (k, val) in o { flatten(val, key: "\(key)[\(k)]", into: &parts) }
        case .array(let a): for val in a { flatten(val, key: "\(key)[]", into: &parts) }
        case .null: parts.append(encode(key))
        default: parts.append("\(encode(key))=\(encode(XMLJSON.scalar(v)))")
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isSingleLine(s), s.contains("="), !s.contains("://"), !s.contains(" "), s.range(of: "^[^=&?#]+=[^&]*(&[^=&]+=[^&]*)+$", options: .regularExpression) != nil else { return nil }
        return DetectionScore(0.7, "Query string parameters")
    }
}
