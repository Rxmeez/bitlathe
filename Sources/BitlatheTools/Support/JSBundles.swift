import Foundation
import BitlatheCore

/// Locations of the bundled JavaScript libraries and thin wrappers around them.
enum JSBundles {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources/JS")
            ?? Bundle.module.url(forResource: name, withExtension: nil)
            ?? URL(fileURLWithPath: name)
    }

    static func prettier(_ plugins: [String]) -> JSRuntime.Bundle {
        JSRuntime.Bundle(name: "prettier", scripts: [url("prettier-standalone.js")] + plugins.map { url("prettier-plugin-\($0).js") })
    }
    static let sqlFormatter = JSRuntime.Bundle(name: "sql", scripts: [url("sql-formatter.min.js")])
    static let terser = JSRuntime.Bundle(name: "terser", scripts: [url("terser.min.js")])
    static let marked = JSRuntime.Bundle(name: "marked", scripts: [url("marked.min.js")])

    static func resourceText(_ name: String, subdirectory: String = "Resources/Data") -> String {
        guard let u = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: subdirectory) ?? Bundle.module.url(forResource: name, withExtension: nil),
              let s = try? String(contentsOf: u, encoding: .utf8) else { return "" }
        return s
    }

    static func resourceURL(_ name: String, subdirectory: String = "Resources/JS") -> URL? {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: subdirectory)
    }
}

enum Prettier {
    /// Parsers: babel, typescript, css, scss, less, html, vue, markdown, yaml, graphql, json, json5
    static func format(_ source: String, parser: String, options: [String: Any] = [:]) async throws -> String {
        let plugins: [String] = switch parser {
        case "babel", "json", "json5", "babel-flow": ["babel", "estree"]
        case "typescript": ["typescript", "estree"]
        case "css", "scss", "less": ["postcss"]
        case "html", "vue", "angular": ["html", "postcss", "babel", "estree"]
        case "markdown", "mdx": ["markdown", "babel", "estree"]
        case "yaml": ["yaml"]
        case "graphql": ["graphql"]
        default: ["babel", "estree"]
        }
        let pluginList = plugins.map { "prettierPlugins.\($0)" }.joined(separator: ",")
        var opts = options
        opts["parser"] = parser
        let optsJSON = String(decoding: try JSONSerialization.data(withJSONObject: opts), as: UTF8.self)
        let script = """
        var o = \(optsJSON); o.plugins = [\(pluginList)];
        return prettier.format(__source, o);
        """
        let result = try await JSRuntime.shared.evaluate(script, in: JSBundles.prettier(plugins), arguments: ["__source": source])
        return result
    }
}
