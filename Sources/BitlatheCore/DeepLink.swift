import Foundation

/// A parsed `bitlathe://` URL. Pure value type: no UI, no I/O.
///
///     bitlathe://tool/<id>?input=…&action=open|copy|replace&<option>=<value>
///     bitlathe://pipeline/<name-or-slug>?input=…&action=…
///     bitlathe://detect?input=…
public struct DeepLink: Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        case tool(String)
        case pipeline(String)
        case detect
    }

    public enum Action: String, Sendable, Equatable {
        /// Show the tool in the app with input and options filled in.
        case open
        /// Run headlessly, put the output on the clipboard.
        case copy
        /// Same as copy; never brings the app forward. (The caller pastes it back.)
        case replace
    }

    public struct ParseError: Error, Equatable, CustomStringConvertible, LocalizedError, Sendable {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var description: String { message }
        public var errorDescription: String? { message }
    }

    public static let scheme = "bitlathe"
    /// The development build ("Bitlathe Dev") registers its own scheme so it never steals links from the installed app.
    public static let devScheme = "bitlathe-dev"
    public static let acceptedSchemes: Set<String> = [scheme, devScheme]

    /// The scheme the running app registered in its Info.plist (`bitlathe`, or `bitlathe-dev` for the dev build).
    /// Outside an app bundle (CLI, tests) this is `bitlathe`.
    public static var appScheme: String {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?.compactMap { $0["CFBundleURLSchemes"] as? [String] }.joined()
        return schemes?.first { acceptedSchemes.contains($0.lowercased()) } ?? scheme
    }
    /// Query keys that are never treated as tool options.
    public static let reservedKeys: Set<String> = ["input", "input64", "action"]

    public var target: Target
    public var input: String?
    public var action: Action
    /// Raw option query items in URL order (later duplicates win when resolved).
    public var rawOptions: [Option]

    public struct Option: Sendable, Equatable {
        public var key: String
        public var value: String
        public init(_ key: String, _ value: String) { self.key = key; self.value = value }
    }

    public init(target: Target, input: String? = nil, action: Action = .open, rawOptions: [Option] = []) {
        self.target = target
        self.input = input
        self.action = action
        self.rawOptions = rawOptions
    }

    // MARK: Parsing

    public static func parse(_ url: URL) throws -> DeepLink {
        guard let s = url.scheme?.lowercased(), acceptedSchemes.contains(s) else { throw ParseError("Not a bitlathe:// URL.") }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw ParseError("Malformed URL.") }

        // bitlathe://tool/json.format -> host "tool", path "/json.format".
        // Also accept bitlathe:///tool/json.format.
        var segments: [String] = []
        if let host = comps.host, !host.isEmpty { segments.append(host) }
        segments += comps.path.split(separator: "/").map(String.init)
        guard let kind = segments.first?.lowercased() else {
            throw ParseError("Missing route. Use tool/<id>, pipeline/<name> or detect.")
        }
        let rest = segments.dropFirst().map { $0.removingPercentEncoding ?? $0 }

        let target: Target
        switch kind {
        case "tool":
            guard let id = rest.first, !id.isEmpty else { throw ParseError("Missing tool id. Use bitlathe://tool/<id>.") }
            target = .tool(id)
        case "pipeline":
            let name = rest.joined(separator: "/")
            guard !name.isEmpty else { throw ParseError("Missing pipeline name. Use bitlathe://pipeline/<name>.") }
            target = .pipeline(name)
        case "detect":
            target = .detect
        default:
            throw ParseError("Unknown route \"\(kind)\". Use tool, pipeline or detect.")
        }

        var input: String?
        var input64: String?
        var action: Action = .open
        var options: [Option] = []
        for item in comps.queryItems ?? [] {
            let value = item.value ?? ""
            switch item.name {
            case "input": input = value
            case "input64": input64 = value
            case "action":
                guard let a = Action(rawValue: value.lowercased()) else {
                    throw ParseError("Unknown action \"\(value)\". Use open, copy or replace.")
                }
                action = a
            default: options.append(Option(item.name, value))
            }
        }
        if let input64 {
            guard let decoded = decodeBase64(input64) else { throw ParseError("input64 is not valid Base64 text.") }
            input = decoded
        }
        if target == .detect { options = [] }
        return DeepLink(target: target, input: input, action: action, rawOptions: options)
    }

    /// Base64 or base64url, padding optional; a `+` that arrived as a space is repaired. Result must be UTF-8.
    public static func decodeBase64(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .newlines)
            .replacingOccurrences(of: " ", with: "+")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        s = s.filter { !$0.isNewline }
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Map raw query values onto a tool's option fields (typed like each field's default).
    /// Unknown keys throw so typos are surfaced instead of silently ignored.
    public func resolveOptions(for fields: [OptionField]) throws -> OptionValues {
        var out: OptionValues = [:]
        for opt in rawOptions {
            guard let field = fields.first(where: { $0.key == opt.key }) else {
                let known = fields.map(\.key).joined(separator: ", ")
                throw ParseError("Unknown option \"\(opt.key)\"." + (known.isEmpty ? " This tool has no options." : " Available: \(known)."))
            }
            out[opt.key] = OptionValue.parse(opt.value, like: field)
        }
        return out
    }

    // MARK: Building

    /// Build a URL for a link (docs, tests, "copy link" affordances).
    public func url() -> URL? {
        var c = URLComponents()
        c.scheme = Self.appScheme
        switch target {
        case .tool(let id): c.host = "tool"; c.path = "/" + id
        case .pipeline(let n): c.host = "pipeline"; c.path = "/" + n
        case .detect: c.host = "detect"
        }
        var items: [URLQueryItem] = []
        if let input { items.append(URLQueryItem(name: "input", value: input)) }
        if action != .open { items.append(URLQueryItem(name: "action", value: action.rawValue)) }
        items += rawOptions.map { URLQueryItem(name: $0.key, value: $0.value) }
        if !items.isEmpty { c.queryItems = items }
        return c.url
    }
}
