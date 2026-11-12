import Foundation
import BitlatheCore

/// Shared implementation for the Prettier-backed formatters.
enum WebFormatting {
    static func format(_ text: String, parser: String, mode: String, indent: Int, printWidth: Int, singleQuote: Bool = false,
                       semi: Bool = true, language: CodeLanguage) async throws -> ToolOutput {
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let before = text.utf8.count
        var out: String
        switch mode {
        case "minify":
            switch language {
            case .css: out = Minify.css(text)
            case .html: out = Minify.html(text)
            case .javascript, .typescript:
                out = try await JSRuntime.shared.evaluate("""
                return Terser.minify(__source, { module: false, compress: true, mangle: __mangle === "1" }).then(function(r){ return r.code; });
                """, in: JSBundles.terser, arguments: ["__source": text, "__mangle": "1"])
            default:
                out = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            }
        default:
            var opts: [String: Any] = ["tabWidth": indent, "printWidth": printWidth, "singleQuote": singleQuote, "semi": semi]
            if indent == 0 { opts["useTabs"] = true; opts["tabWidth"] = 4 }
            out = try await Prettier.format(text, parser: parser, options: opts)
        }
        let after = out.utf8.count
        let meta = [MetaRow("Size", "\(ByteFormatter.string(before)) → \(ByteFormatter.string(after))"),
                    MetaRow("Change", String(format: "%+.1f%%", before == 0 ? 0 : (Double(after - before) / Double(before)) * 100))]
        return ToolOutput(text: out, language: language, metadata: mode == "minify" ? meta : [])
    }

    static let indentField = OptionField.picker("indent", "Indent", [.init("2", "2 spaces"), .init("4", "4 spaces"), .init("0", "Tab")], default: "2", visibleWhen: ("mode", ["format"]))
    static let widthField = OptionField.stepper("printWidth", "Width", min: 40, max: 200, step: 10, default: 80, visibleWhen: ("mode", ["format"]), advanced: true)
    static let modeField = OptionField.mode([.init("format", "Beautify"), .init("minify", "Minify")], default: "format")

}

public struct WebFormatOptions: ToolOptions {
    public var mode = "format"
    public var indent = "2"
    public var printWidth = 80
    public var singleQuote = false
    public var semi = true
    public init() {}
}

public struct HTMLFormatTool: DevTool {
    public static let id = "html.format"
    public static let name = "HTML Formatter"
    public static let summary = "Beautify or minify HTML"
    public static let category = ToolCategory.format
    public static let symbol = "chevron.left.forwardslash.chevron.right"
    public static let keywords = ["html", "beautify", "prettify", "minify", "markup"]
    public static let io = ToolIO.text(.html, .html)
    public static let samples = [ToolSample("Page", "<!DOCTYPE html><html><head><title>Hi</title></head><body><div class=\"a\"><p>Hello <b>world</b></p><ul><li>One<li>Two</ul></div></body></html>")]
    public static let optionFields = [WebFormatting.modeField, WebFormatting.indentField, WebFormatting.widthField]
    public typealias Options = WebFormatOptions
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        try await WebFormatting.format(input.text, parser: "html", mode: options.mode, indent: Int(options.indent) ?? 2, printWidth: options.printWidth, language: .html)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        let l = s.lowercased()
        if l.hasPrefix("<!doctype html") || l.hasPrefix("<html") { return DetectionScore(0.95, "HTML document") }
        if s.hasPrefix("<"), s.hasSuffix(">"), l.range(of: "<(div|p|span|a|ul|li|table|body|head|section|h[1-6]|img|form|input|button|br|script|style)\\b", options: .regularExpression) != nil {
            return DetectionScore(0.8, "HTML markup")
        }
        return nil
    }
}

public struct CSSFormatTool: DevTool {
    public static let id = "css.format"
    public static let name = "CSS Formatter"
    public static let summary = "Beautify or minify CSS"
    public static let category = ToolCategory.format
    public static let symbol = "paintbrush"
    public static let keywords = ["css", "stylesheet", "beautify", "minify"]
    public static let io = ToolIO.text(.css, .css)
    public static let samples = [ToolSample("Rules", ".card{display:flex;padding:8px 12px;color:#333}.card:hover{background:rgba(0,0,0,.05)}@media (max-width:600px){.card{padding:4px}}")]
    public static let optionFields = [WebFormatting.modeField, WebFormatting.indentField, WebFormatting.widthField]
    public typealias Options = WebFormatOptions
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        try await WebFormatting.format(input.text, parser: "css", mode: options.mode, indent: Int(options.indent) ?? 2, printWidth: options.printWidth, language: .css)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        guard !s.hasPrefix("<"), !s.hasPrefix("{"), s.contains("{"), s.contains("}") else { return nil }
        if s.range(of: "(^|[\\s}])[.#@]?[A-Za-z][\\w\\-\\s,.:#>\\[\\]=\"'*+~()]*\\{[^}]*:[^}]*\\}", options: .regularExpression) != nil {
            if s.contains("$") || s.contains("@mixin") || s.contains("@include") { return DetectionScore(0.5, "Looks like SCSS") }
            return DetectionScore(0.75, "CSS rules")
        }
        return nil
    }
}

public struct SCSSFormatTool: DevTool {
    public static let id = "scss.format"
    public static let name = "SCSS Formatter"
    public static let summary = "Beautify SCSS"
    public static let category = ToolCategory.format
    public static let symbol = "paintbrush.pointed"
    public static let keywords = ["scss", "sass", "stylesheet", "beautify"]
    public static let io = ToolIO.text(.css, .css)
    public static let samples = [ToolSample("Nested", "$c:#333;.card{color:$c;&:hover{color:lighten($c,10%)}.title{font-weight:bold}}")]
    public static let optionFields = [WebFormatting.indentField, WebFormatting.widthField]
    public typealias Options = WebFormatOptions
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        try await WebFormatting.format(input.text, parser: "scss", mode: "format", indent: Int(options.indent) ?? 2, printWidth: options.printWidth, language: .css)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        guard s.contains("{"), s.contains("}"), !s.hasPrefix("<") else { return nil }
        if s.contains("@mixin") || s.contains("@include") || s.range(of: "\\$[a-zA-Z-]+\\s*:", options: .regularExpression) != nil || s.contains("&:") { return DetectionScore(0.8, "SCSS syntax") }
        return nil
    }
}

public struct LESSFormatTool: DevTool {
    public static let id = "less.format"
    public static let name = "LESS Formatter"
    public static let summary = "Beautify LESS"
    public static let category = ToolCategory.format
    public static let symbol = "paintbrush.pointed.fill"
    public static let keywords = ["less", "stylesheet", "beautify"]
    public static let io = ToolIO.text(.css, .css)
    public static let samples = [ToolSample("Mixin", "@c:#333;.bordered(@w:2px){border:@w solid black}.box{color:@c;.bordered(4px)}")]
    public static let optionFields = [WebFormatting.indentField, WebFormatting.widthField]
    public typealias Options = WebFormatOptions
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        try await WebFormatting.format(input.text, parser: "less", mode: "format", indent: Int(options.indent) ?? 2, printWidth: options.printWidth, language: .css)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        guard s.contains("{"), s.contains("}"), !s.hasPrefix("<") else { return nil }
        if s.range(of: "@[a-zA-Z-]+\\s*:", options: .regularExpression) != nil, s.range(of: "\\.[a-zA-Z-]+\\(", options: .regularExpression) != nil { return DetectionScore(0.75, "LESS syntax") }
        return nil
    }
}

public struct JavaScriptFormatTool: DevTool {
    public static let id = "js.format"
    public static let name = "JavaScript Formatter"
    public static let summary = "Beautify or minify JavaScript"
    public static let category = ToolCategory.format
    public static let symbol = "j.square"
    public static let keywords = ["javascript", "js", "beautify", "minify", "uglify", "terser", "prettier"]
    public static let io = ToolIO.text(.javascript, .javascript)
    public static let samples = [ToolSample("Function", "const add=(a,b)=>{return a+b};function greet(name){console.log(`Hi ${name}`)};export default {add,greet}")]
    public static let optionFields = [WebFormatting.modeField, WebFormatting.indentField, WebFormatting.widthField,
                                      .toggle("singleQuote", "Single quotes", visibleWhen: ("mode", ["format"])),
                                      .toggle("semi", "Semicolons", default: true, visibleWhen: ("mode", ["format"]))]
    public typealias Options = WebFormatOptions
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        try await WebFormatting.format(input.text, parser: "babel", mode: options.mode, indent: Int(options.indent) ?? 2, printWidth: options.printWidth,
                                       singleQuote: options.singleQuote, semi: options.semi, language: .javascript)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        guard !s.hasPrefix("<"), !s.hasPrefix("{"), !s.hasPrefix("[") else { return nil }
        let hits = ["function ", "const ", "let ", "=>", "console.", "require(", "import ", "export ", "var ", "document."].filter { s.contains($0) }.count
        if hits >= 2 {
            if s.range(of: ":\\s*(string|number|boolean)\\b|\\binterface\\s+\\w+|\\btype\\s+\\w+\\s*=|<\\w+>\\(", options: .regularExpression) != nil { return DetectionScore(0.55, "Looks like TypeScript") }
            return DetectionScore(0.7, "JavaScript syntax")
        }
        return nil
    }
}

public struct TypeScriptFormatTool: DevTool {
    public static let id = "ts.format"
    public static let name = "TypeScript Formatter"
    public static let summary = "Beautify TypeScript and TSX"
    public static let category = ToolCategory.format
    public static let symbol = "t.square"
    public static let keywords = ["typescript", "ts", "tsx", "beautify", "prettier"]
    public static let io = ToolIO.text(.typescript, .typescript)
    public static let samples = [ToolSample("Interface", "interface User{id:number;name:string;tags?:string[]}export const load=async(id:number):Promise<User>=>{const r=await fetch(`/u/${id}`);return r.json()}")]
    public static let optionFields = [WebFormatting.indentField, WebFormatting.widthField, .toggle("singleQuote", "Single quotes"), .toggle("semi", "Semicolons", default: true)]
    public typealias Options = WebFormatOptions
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        try await WebFormatting.format(input.text, parser: "typescript", mode: "format", indent: Int(options.indent) ?? 2, printWidth: options.printWidth,
                                       singleQuote: options.singleQuote, semi: options.semi, language: .typescript)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        guard !s.hasPrefix("<"), !s.hasPrefix("{") else { return nil }
        if s.range(of: "\\binterface\\s+\\w+\\s*\\{|\\btype\\s+\\w+\\s*=|:\\s*(string|number|boolean|any|void)\\b|\\bas\\s+const\\b|\\benum\\s+\\w+", options: .regularExpression) != nil,
           ["function", "const", "let", "=>", "import", "export", "class"].contains(where: { s.contains($0) }) {
            return DetectionScore(0.75, "TypeScript syntax")
        }
        return nil
    }
}

public struct GraphQLFormatTool: DevTool {
    public static let id = "graphql.format"
    public static let name = "GraphQL Formatter"
    public static let summary = "Beautify GraphQL queries and schemas"
    public static let category = ToolCategory.format
    public static let symbol = "point.3.filled.connected.trianglepath.dotted"
    public static let keywords = ["graphql", "gql", "query", "schema", "beautify"]
    public static let io = ToolIO.text(.graphql, .graphql)
    public static let samples = [ToolSample("Query", "query GetUser($id:ID!){user(id:$id){id name posts(first:10){edges{node{id title}}}}}")]
    public static let optionFields = [WebFormatting.indentField, WebFormatting.widthField]
    public typealias Options = WebFormatOptions
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        try await WebFormatting.format(input.text, parser: "graphql", mode: "format", indent: Int(options.indent) ?? 2, printWidth: options.printWidth, language: .graphql)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        if s.range(of: "^\\s*(query|mutation|subscription|fragment)\\b[^{]*\\{|^\\s*(type|input|enum|interface|schema)\\s+\\w+[^{]*\\{", options: .regularExpression) != nil {
            return DetectionScore(0.8, "GraphQL syntax")
        }
        return nil
    }
}

public struct ERBFormatTool: DevTool {
    public static let id = "erb.format"
    public static let name = "ERB Formatter"
    public static let summary = "Beautify HTML templates with embedded Ruby"
    public static let category = ToolCategory.format
    public static let symbol = "diamond"
    public static let keywords = ["erb", "ruby", "rails", "template", "beautify"]
    public static let io = ToolIO.text(.html, .html)
    public static let samples = [ToolSample("Template", "<div class=\"users\"><% @users.each do |u| %><p><%= u.name %></p><% end %></div>")]
    public static let optionFields = [WebFormatting.indentField, WebFormatting.widthField]
    public typealias Options = WebFormatOptions
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        // Protect <% ... %> tags as comments that Prettier keeps, then restore them.
        var tags: [String] = []
        let ns = text as NSString
        let re = try NSRegularExpression(pattern: "<%[\\s\\S]*?%>")
        var protected = ""
        var cursor = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            protected += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let tag = ns.substring(with: m.range)
            tags.append(tag)
            let isBlock = tag.range(of: "<%-?\\s*(if|unless|else|elsif|end|do|each|while|case|when)\\b|\\bdo\\s*(\\|[^|]*\\|)?\\s*-?%>", options: .regularExpression) != nil
            protected += isBlock ? "<!--ERB\(tags.count - 1)-->" : "<erb-\(tags.count - 1)></erb-\(tags.count - 1)>"
            cursor = NSMaxRange(m.range)
        }
        protected += ns.substring(from: cursor)
        var out = try await Prettier.format(protected, parser: "html", options: ["tabWidth": Int(options.indent) ?? 2, "printWidth": options.printWidth])
        for (i, tag) in tags.enumerated() {
            out = out.replacingOccurrences(of: "<!--ERB\(i)-->", with: tag)
            out = out.replacingOccurrences(of: "<erb-\(i)></erb-\(i)>", with: tag)
        }
        return ToolOutput(text: out, language: .html)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        s.contains("<%") && s.contains("%>") && s.contains("<") ? DetectionScore(0.85, "ERB template") : nil
    }
}
