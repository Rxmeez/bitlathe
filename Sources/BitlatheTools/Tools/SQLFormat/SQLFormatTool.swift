import Foundation
import BitlatheCore

public struct SQLFormatTool: DevTool {
    public static let id = "sql.format"
    public static let name = "SQL Formatter"
    public static let summary = "Format SQL for PostgreSQL, MySQL, BigQuery, Snowflake, SQLite and more"
    public static let category = ToolCategory.format
    public static let symbol = "cylinder.split.1x2"
    public static let keywords = ["sql", "query", "postgres", "mysql", "bigquery", "snowflake", "sqlite", "format", "beautify"]
    public static let io = ToolIO.text(.sql, .sql)
    public static let samples = [ToolSample("Join", "select u.id, u.name, count(o.id) as orders from users u left join orders o on o.user_id = u.id where u.active = true group by u.id, u.name having count(o.id) > 1 order by orders desc limit 10;")]
    public static let optionFields: [OptionField] = [
        .picker("dialect", "Dialect", [.init("sql", "Standard"), .init("postgresql", "PostgreSQL"), .init("mysql", "MySQL"), .init("mariadb", "MariaDB"),
                                       .init("bigquery", "BigQuery"), .init("snowflake", "Snowflake"), .init("sqlite", "SQLite"), .init("tsql", "T-SQL"),
                                       .init("plsql", "PL/SQL"), .init("redshift", "Redshift"), .init("spark", "Spark"), .init("trino", "Trino"), .init("db2", "Db2")], default: "sql"),
        .segmented("keywordCase", "Keywords", [.init("preserve", "As is"), .init("upper", "UPPER"), .init("lower", "lower")], default: "upper"),
        .picker("indent", "Indent", [.init("2", "2 spaces"), .init("4", "4 spaces"), .init("tab", "Tab")], default: "2"),
        .toggle("minify", "Minify"),
        .picker("indentStyle", "Style", [.init("standard", "Standard"), .init("tabularLeft", "Tabular left"), .init("tabularRight", "Tabular right")], default: "standard", advanced: true),
        .picker("logicalOperatorNewline", "AND/OR", [.init("before", "Before"), .init("after", "After")], default: "before", advanced: true),
        .stepper("linesBetweenQueries", "Lines between queries", min: 0, max: 5, default: 1, advanced: true),
    ]
    public struct Options: ToolOptions {
        public var dialect = "sql"
        public var keywordCase = "upper"
        public var indent = "2"
        public var minify = false
        public var indentStyle = "standard"
        public var logicalOperatorNewline = "before"
        public var linesBetweenQueries = 1
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        if options.minify {
            var out = text.replacingOccurrences(of: "--[^\\n]*", with: "", options: .regularExpression)
            out = out.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
            out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            out = out.replacingOccurrences(of: "\\s*([(),;])\\s*", with: "$1", options: .regularExpression)
            return ToolOutput(text: out.trimmed(), language: .sql)
        }
        let cfg: [String: Any] = [
            "language": options.dialect,
            "keywordCase": options.keywordCase,
            "dataTypeCase": options.keywordCase,
            "functionCase": options.keywordCase,
            "tabWidth": options.indent == "tab" ? 4 : (Int(options.indent) ?? 2),
            "useTabs": options.indent == "tab",
            "indentStyle": options.indentStyle,
            "logicalOperatorNewline": options.logicalOperatorNewline,
            "linesBetweenQueries": options.linesBetweenQueries,
        ]
        let cfgJSON = String(decoding: try JSONSerialization.data(withJSONObject: cfg), as: UTF8.self)
        let out = try await JSRuntime.shared.evaluate("return sqlFormatter.format(__source, \(cfgJSON));", in: JSBundles.sqlFormatter, arguments: ["__source": text])
        let statements = out.split(separator: ";").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return ToolOutput(text: out, language: .sql, metadata: [MetaRow("Statements", "\(statements)")])
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.range(of: "^\\s*(select|insert\\s+into|update|delete\\s+from|create\\s+(table|index|view|or\\s+replace)|alter\\s+table|drop\\s+table|with\\s+\\w+\\s+as|merge\\s+into)\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            return DetectionScore(0.9, "SQL statement")
        }
        return nil
    }
}
