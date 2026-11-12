import Foundation
import BitlatheCore

public struct URLParseTool: DevTool {
    public static let id = "url.parse"
    public static let name = "URL Parser"
    public static let summary = "Break a URL into scheme, host, port, path, query parameters and fragment — and rebuild it live"
    public static let category = ToolCategory.inspect
    public static let symbol = "link.badge.plus"
    public static let keywords = ["url", "parse", "query", "params", "host", "path", "fragment", "uri", "builder"]
    public static let samples = [ToolSample("API URL", "https://user:pass@api.example.com:8443/v1/search?q=bitlathe&page=2&tags=a&tags=b&empty=#results")]
    public static let optionFields: [OptionField] = [.toggle("decode", "Decode values", default: true)]
    public struct Options: ToolOptions {
        public var decode = true
        public init() {}
    }
    public init() {}

    public struct Parsed: Sendable, Equatable {
        public var scheme: String?
        public var user: String?
        public var password: String?
        public var host: String?
        public var port: Int?
        public var path: String
        public var query: [(key: String, value: String)]
        public var fragment: String?

        public static func == (l: Parsed, r: Parsed) -> Bool { l.build() == r.build() }

        public func build() -> String {
            var c = URLComponents()
            c.scheme = scheme
            c.user = user
            c.password = password
            c.host = host
            c.port = port
            c.path = path
            c.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.key, value: $0.value.isEmpty ? nil : $0.value) }
            c.fragment = fragment
            if let s = c.string { return s }
            var out = (scheme.map { $0 + "://" } ?? "") + (host ?? "") + (port.map { ":\($0)" } ?? "") + path
            if !query.isEmpty { out += "?" + query.map { "\(JSONQueryStringTool.encode($0.key))=\(JSONQueryStringTool.encode($0.value))" }.joined(separator: "&") }
            if let f = fragment { out += "#" + f }
            return out
        }
    }

    public static func parse(_ text: String) throws -> Parsed {
        var s = text.trimmed()
        if !s.contains("://"), !s.hasPrefix("mailto:"), !s.hasPrefix("tel:") {
            if s.hasPrefix("//") { s = "https:" + s } else if s.hasPrefix("/") || s.hasPrefix("?") { s = "https://localhost" + s } else { s = "https://" + s }
        }
        guard let c = URLComponents(string: s) ?? URLComponents(string: s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(CharacterSet(charactersIn: "#"))) ?? s) else {
            throw ToolError("Not a valid URL")
        }
        var query: [(key: String, value: String)] = []
        if let raw = c.percentEncodedQuery {
            for pair in raw.split(separator: "&", omittingEmptySubsequences: true) {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let k = String(kv[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(kv[0])
                let v = kv.count > 1 ? (String(kv[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(kv[1])) : ""
                query.append((key: k, value: v))
            }
        }
        return Parsed(scheme: c.scheme, user: c.user, password: c.password, host: c.host, port: c.port, path: c.path, query: query, fragment: c.fragment)
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let p = try Self.parse(text)
        var rows: [MetaRow] = []
        if let s = p.scheme { rows.append(MetaRow("Scheme", s, style: .mono)) }
        if let u = p.user { rows.append(MetaRow("User", u, style: .mono)) }
        if let pw = p.password { rows.append(MetaRow("Password", pw, style: .mono)) }
        if let h = p.host {
            rows.append(MetaRow("Host", h, style: .mono))
            let labels = h.split(separator: ".")
            if labels.count >= 2, h.range(of: "^[\\d.]+$", options: .regularExpression) == nil {
                rows.append(MetaRow("Domain", labels.suffix(2).joined(separator: "."), style: .mono))
                if labels.count > 2 { rows.append(MetaRow("Subdomain", labels.dropLast(2).joined(separator: "."), style: .mono)) }
                rows.append(MetaRow("TLD", String(labels.last!), style: .mono))   // swiftlint:disable:this force_unwrapping
            }
            if h.contains("xn--"), let decoded = try? Punycode.decodeDomain(h) { rows.append(MetaRow("Unicode host", decoded)) }
        }
        rows.append(MetaRow("Port", p.port.map(String.init) ?? Self.defaultPort(p.scheme).map { "\($0) (default)" } ?? "—", style: .mono))
        rows.append(MetaRow("Path", p.path.isEmpty ? "/" : p.path, style: .mono))
        let segments = p.path.split(separator: "/").map(String.init)
        if !segments.isEmpty { rows.append(MetaRow("Path segments", segments.enumerated().map { "[\($0.offset)] \($0.element.removingPercentEncoding ?? $0.element)" }.joined(separator: "  "), style: .mono)) }
        if let last = segments.last, let dot = last.lastIndex(of: "."), dot != last.startIndex { rows.append(MetaRow("Extension", String(last[last.index(after: dot)...]), style: .mono)) }
        rows.append(MetaRow("Query parameters", "\(p.query.count)"))
        for (k, v) in p.query { rows.append(MetaRow("  \(k)", options.decode ? v : (v.addingPercentEncoding(withAllowedCharacters: URLEncodeTool.componentAllowed) ?? v), style: .mono)) }
        if let f = p.fragment { rows.append(MetaRow("Fragment", f, style: .mono)) }
        rows.append(MetaRow("Normalised", p.build(), style: .mono))
        let json = JSONSerializer.string(.object([
            (key: "scheme", value: p.scheme.map { .string($0) } ?? .null), (key: "host", value: p.host.map { .string($0) } ?? .null),
            (key: "port", value: p.port.map { .number($0) } ?? .null), (key: "path", value: .string(p.path)),
            (key: "query", value: .object(p.query.map { (key: $0.key, value: .string($0.value)) })), (key: "fragment", value: p.fragment.map { .string($0) } ?? .null),
        ]))
        return ToolOutput(text: json, language: .json, facets: [OutputFacet("Rebuilt URL", text: p.build())], metadata: rows)
    }

    static func defaultPort(_ scheme: String?) -> Int? {
        switch scheme?.lowercased() {
        case "http", "ws": 80
        case "https", "wss": 443
        case "ftp": 21
        case "ssh", "sftp": 22
        case "smtp": 25
        case "postgres", "postgresql": 5432
        case "mysql": 3306
        case "redis": 6379
        case "mongodb": 27017
        default: nil
        }
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isSingleLine(s), !s.contains(" ") else { return nil }
        if s.range(of: "^[a-z][a-z0-9+.-]*://[^\\s]+$", options: [.regularExpression, .caseInsensitive]) != nil {
            return DetectionScore(s.contains("?") ? 0.85 : 0.7, "URL")
        }
        if s.range(of: "^(www\\.)?[a-z0-9-]+(\\.[a-z0-9-]+)+(/[^\\s]*)?(\\?[^\\s]*)?$", options: [.regularExpression, .caseInsensitive]) != nil, s.contains("/") || s.contains("?") { return DetectionScore(0.5, "URL without scheme") }
        return nil
    }
}
