import Foundation
import BitlatheCore

/// A parsed HTTP request shared by cURL → code and code → cURL.
struct HTTPRequestModel: Equatable {
    var method = "GET"
    var url = ""
    var headers: [(String, String)] = []
    var body: String?
    var formFields: [(String, String)] = []
    var basicAuth: (String, String)?
    var insecure = false
    var followRedirects = false
    var isJSONBody: Bool {
        guard let b = body?.trimmed() else { return false }
        return (b.hasPrefix("{") || b.hasPrefix("[")) && (try? JSONParser.parse(b, options: .json5)) != nil
    }
    var contentType: String? { headers.first { $0.0.lowercased() == "content-type" }?.1 }
    static func == (l: HTTPRequestModel, r: HTTPRequestModel) -> Bool { l.method == r.method && l.url == r.url && l.body == r.body }
}

enum CurlParser {
    static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if let q = quote {
                if c == q { quote = nil }
                else if c == "\\", q == "\"", s.index(after: i) < s.endIndex {
                    i = s.index(after: i)
                    let n = s[i]
                    current.append(n == "n" ? "\n" : n)
                } else { current.append(c) }
            } else if c == "'" || c == "\"" { quote = c; hasToken = true }
            else if c == "\\", s.index(after: i) < s.endIndex {
                i = s.index(after: i)
                let n = s[i]
                if n != "\n" && n != "\r\n" { current.append(n); hasToken = true }
            } else if c == "$", s.index(after: i) < s.endIndex, s[s.index(after: i)] == "'" {
                // $'...' ANSI-C quoting
                i = s.index(after: i)
                quote = "'"
                hasToken = true
            } else if c.isWhitespace {
                if hasToken { tokens.append(current); current = ""; hasToken = false }
            } else { current.append(c); hasToken = true }
            i = s.index(after: i)
        }
        if hasToken { tokens.append(current) }
        return tokens
    }

    static func parse(_ command: String) throws -> HTTPRequestModel {
        var tokens = tokenize(command.trimmed())
        guard let first = tokens.first, first == "curl" || first.hasSuffix("/curl") else {
            throw ToolError("Command must start with curl", hint: "Example: curl -X POST https://api.example.com -d '{\"a\":1}'")
        }
        tokens.removeFirst()
        var req = HTTPRequestModel()
        var i = 0
        var explicitMethod: String?
        var dataParts: [String] = []
        func next() -> String? { i + 1 < tokens.count ? { i += 1; return tokens[i] }() : nil }
        while i < tokens.count {
            let t = tokens[i]
            switch t {
            case "-X", "--request": explicitMethod = next()?.uppercased()
            case "-H", "--header":
                if let h = next(), let colon = h.firstIndex(of: ":") {
                    req.headers.append((h[..<colon].trimmed(), h[h.index(after: colon)...].trimmed()))
                }
            case "-d", "--data", "--data-raw", "--data-binary", "--data-ascii", "--data-urlencode":
                if let d = next() { dataParts.append(d.hasPrefix("@") && t != "--data-raw" ? "<contents of \(d.dropFirst())>" : d) }
            case "--json":
                if let d = next() { dataParts.append(d); req.headers.append(("Content-Type", "application/json")); req.headers.append(("Accept", "application/json")) }
            case "-F", "--form":
                if let f = next() { let kv = f.split(separator: "=", maxSplits: 1); req.formFields.append((String(kv[0]), kv.count > 1 ? String(kv[1]) : "")) }
            case "-u", "--user":
                if let u = next() { let kv = u.split(separator: ":", maxSplits: 1); req.basicAuth = (String(kv[0]), kv.count > 1 ? String(kv[1]) : "") }
            case "-A", "--user-agent": if let ua = next() { req.headers.append(("User-Agent", ua)) }
            case "-e", "--referer": if let r = next() { req.headers.append(("Referer", r)) }
            case "-b", "--cookie": if let c = next() { req.headers.append(("Cookie", c)) }
            case "-k", "--insecure": req.insecure = true
            case "-L", "--location": req.followRedirects = true
            case "-I", "--head": explicitMethod = "HEAD"
            case "-G", "--get": explicitMethod = "GET"
            case "--url": if let u = next() { req.url = u }
            case "-o", "--output", "-m", "--max-time", "--connect-timeout", "-w", "--write-out", "--retry", "-x", "--proxy", "-c", "--cookie-jar", "--cacert", "--cert", "--key", "-T", "--upload-file":
                _ = next()
            case "-s", "--silent", "-S", "--show-error", "-v", "--verbose", "-i", "--include", "-f", "--fail", "--compressed", "-#", "--progress-bar", "-sS", "-sSL", "-fsSL", "-fsS", "-vL", "-kL", "-Ls", "-sL":
                if t.contains("L") { req.followRedirects = true }
                if t.contains("k") { req.insecure = true }
            default:
                if t.hasPrefix("-") {
                    // Unknown flag: skip, and skip a value if it doesn't look like a flag/URL.
                    if i + 1 < tokens.count, !tokens[i + 1].hasPrefix("-"), !tokens[i + 1].contains("://") { i += 1 }
                } else if req.url.isEmpty {
                    req.url = t
                }
            }
            i += 1
        }
        guard !req.url.isEmpty else { throw ToolError("No URL found in the curl command") }
        if !req.url.contains("://") { req.url = "https://" + req.url }
        if !dataParts.isEmpty {
            req.body = dataParts.joined(separator: "&")
            if req.contentType == nil, !req.isJSONBody { req.headers.append(("Content-Type", "application/x-www-form-urlencoded")) }
            if req.contentType == nil, req.isJSONBody { req.headers.append(("Content-Type", "application/json")) }
        }
        req.method = explicitMethod ?? ((req.body != nil || !req.formFields.isEmpty) ? "POST" : "GET")
        return req
    }

    static func toCurl(_ r: HTTPRequestModel, multiline: Bool = true) -> String {
        var parts = ["curl"]
        if r.method != "GET" || r.body == nil && r.method != "GET" { parts.append("-X \(r.method)") }
        if r.followRedirects { parts.append("-L") }
        if r.insecure { parts.append("-k") }
        for (k, v) in r.headers { parts.append("-H \(shellQuote("\(k): \(v)"))") }
        if let (u, p) = r.basicAuth { parts.append("-u \(shellQuote("\(u):\(p)"))") }
        for (k, v) in r.formFields { parts.append("-F \(shellQuote("\(k)=\(v)"))") }
        if let b = r.body { parts.append("-d \(shellQuote(b))") }
        parts.append(shellQuote(r.url))
        return multiline && parts.count > 2 ? parts.joined(separator: " \\\n  ") : parts.joined(separator: " ")
    }

    static func shellQuote(_ s: String) -> String {
        if s.range(of: "^[A-Za-z0-9_./:=@%+-]+$", options: .regularExpression) != nil { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum CodeGen {
    static func q(_ s: String) -> String { JSONSerializer.quoted(s) }
    static func indentJSON(_ body: String, by pad: String) -> String {
        guard let v = try? JSONParser.parse(body, options: .json5) else { return q(body) }
        return JSONSerializer.string(v).indented(by: pad).trimmingCharacters(in: .whitespaces)
    }

    static func swift(_ r: HTTPRequestModel) -> String {
        var s = "import Foundation\n\nvar request = URLRequest(url: URL(string: \(q(r.url)))!)\nrequest.httpMethod = \(q(r.method))\n"
        for (k, v) in r.headers { s += "request.setValue(\(q(v)), forHTTPHeaderField: \(q(k)))\n" }
        if let (u, p) = r.basicAuth { s += "request.setValue(\"Basic \" + Data(\"\(u):\(p)\".utf8).base64EncodedString(), forHTTPHeaderField: \"Authorization\")\n" }
        if let b = r.body {
            if r.isJSONBody { s += "let payload: [String: Any] = \(swiftLiteral(b))\nrequest.httpBody = try JSONSerialization.data(withJSONObject: payload)\n" }
            else { s += "request.httpBody = Data(\(q(b)).utf8)\n" }
        }
        s += "\nlet (data, response) = try await URLSession.shared.data(for: request)\nprint(String(decoding: data, as: UTF8.self))\n"
        return s
    }
    static func swiftLiteral(_ body: String) -> String {
        guard let v = try? JSONParser.parse(body, options: .json5) else { return q(body) }
        func lit(_ v: JSONValue) -> String {
            switch v {
            case .null: "NSNull()"
            case .bool(let b): b ? "true" : "false"
            case .number(let n): n
            case .string(let s): q(s)
            case .array(let a): "[" + a.map(lit).joined(separator: ", ") + "]"
            case .object(let o): o.isEmpty ? "[:]" : "[" + o.map { "\(q($0.key)): \(lit($0.value))" }.joined(separator: ", ") + "]"
            }
        }
        return lit(v)
    }

    static func python(_ r: HTTPRequestModel) -> String {
        var s = "import requests\n\n"
        s += "url = \(q(r.url))\n"
        if !r.headers.isEmpty { s += "headers = {\n" + r.headers.map { "    \(q($0.0)): \(q($0.1))," }.joined(separator: "\n") + "\n}\n" }
        var args = ["url"]
        if !r.headers.isEmpty { args.append("headers=headers") }
        if let b = r.body {
            if r.isJSONBody { s += "payload = \(pythonLiteral(b))\n"; args.append("json=payload") }
            else { s += "data = \(q(b))\n"; args.append("data=data") }
        }
        if !r.formFields.isEmpty { s += "files = {" + r.formFields.map { "\(q($0.0)): \(q($0.1))" }.joined(separator: ", ") + "}\n"; args.append("files=files") }
        if let (u, p) = r.basicAuth { args.append("auth=(\(q(u)), \(q(p)))") }
        if r.insecure { args.append("verify=False") }
        s += "\nresponse = requests.\(r.method.lowercased())(\(args.joined(separator: ", ")))\nprint(response.status_code)\nprint(response.text)\n"
        return s
    }
    static func pythonLiteral(_ body: String) -> String {
        guard let v = try? JSONParser.parse(body, options: .json5) else { return q(body) }
        return JSONSerializer.string(v).replacingOccurrences(of: ": null", with: ": None").replacingOccurrences(of: ": true", with: ": True").replacingOccurrences(of: ": false", with: ": False")
    }

    static func fetch(_ r: HTTPRequestModel) -> String {
        var opts: [String] = ["  method: \(q(r.method))"]
        if !r.headers.isEmpty { opts.append("  headers: {\n" + r.headers.map { "    \(q($0.0)): \(q($0.1))," }.joined(separator: "\n") + "\n  }") }
        if let b = r.body { opts.append(r.isJSONBody ? "  body: JSON.stringify(\(indentJSON(b, by: "  ")))" : "  body: \(q(b))") }
        if !r.formFields.isEmpty {
            return "const form = new FormData();\n" + r.formFields.map { "form.append(\(q($0.0)), \(q($0.1)));" }.joined(separator: "\n") +
                "\n\nconst response = await fetch(\(q(r.url)), {\n  method: \(q(r.method)),\n  body: form,\n});\nconsole.log(await response.text());\n"
        }
        return "const response = await fetch(\(q(r.url)), {\n\(opts.joined(separator: ",\n")),\n});\n\nconst data = await response.\(r.headers.contains { $0.1.contains("json") } ? "json" : "text")();\nconsole.log(data);\n"
    }

    static func axios(_ r: HTTPRequestModel) -> String {
        var s = "import axios from \"axios\";\n\nconst response = await axios({\n  method: \(q(r.method.lowercased())),\n  url: \(q(r.url)),\n"
        if !r.headers.isEmpty { s += "  headers: {\n" + r.headers.map { "    \(q($0.0)): \(q($0.1))," }.joined(separator: "\n") + "\n  },\n" }
        if let b = r.body { s += r.isJSONBody ? "  data: \(indentJSON(b, by: "  ")),\n" : "  data: \(q(b)),\n" }
        if let (u, p) = r.basicAuth { s += "  auth: { username: \(q(u)), password: \(q(p)) },\n" }
        s += "});\n\nconsole.log(response.data);\n"
        return s
    }

    static func go(_ r: HTTPRequestModel) -> String {
        var s = "package main\n\nimport (\n\t\"fmt\"\n\t\"io\"\n\t\"net/http\"\n"
        if r.body != nil { s += "\t\"strings\"\n" }
        s += ")\n\nfunc main() {\n"
        if let b = r.body { s += "\tbody := strings.NewReader(`\(b)`)\n\treq, err := http.NewRequest(\(q(r.method)), \(q(r.url)), body)\n" }
        else { s += "\treq, err := http.NewRequest(\(q(r.method)), \(q(r.url)), nil)\n" }
        s += "\tif err != nil {\n\t\tpanic(err)\n\t}\n"
        for (k, v) in r.headers { s += "\treq.Header.Set(\(q(k)), \(q(v)))\n" }
        if let (u, p) = r.basicAuth { s += "\treq.SetBasicAuth(\(q(u)), \(q(p)))\n" }
        s += "\n\tresp, err := http.DefaultClient.Do(req)\n\tif err != nil {\n\t\tpanic(err)\n\t}\n\tdefer resp.Body.Close()\n\n\tdata, _ := io.ReadAll(resp.Body)\n\tfmt.Println(resp.Status)\n\tfmt.Println(string(data))\n}\n"
        return s
    }

    static func rust(_ r: HTTPRequestModel) -> String {
        var s = "use reqwest::Client;\n\n#[tokio::main]\nasync fn main() -> Result<(), Box<dyn std::error::Error>> {\n    let client = Client::new();\n"
        let methodCall = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"].contains(r.method)
            ? ".\(r.method.lowercased())(\(q(r.url)))"
            : ".request(reqwest::Method::from_bytes(b\"\(r.method)\")?, \(q(r.url)))"
        s += "    let response = client\n        \(methodCall)\n"
        for (k, v) in r.headers { s += "        .header(\(q(k)), \(q(v)))\n" }
        if let (u, p) = r.basicAuth { s += "        .basic_auth(\(q(u)), Some(\(q(p))))\n" }
        if let b = r.body { s += "        .body(r#\"\(b)\"#)\n" }
        s += "        .send()\n        .await?;\n\n    println!(\"{}\", response.status());\n    println!(\"{}\", response.text().await?);\n    Ok(())\n}\n"
        return s
    }

    static func php(_ r: HTTPRequestModel) -> String {
        var s = "<?php\n\n$ch = curl_init();\ncurl_setopt($ch, CURLOPT_URL, \(phpQ(r.url)));\ncurl_setopt($ch, CURLOPT_RETURNTRANSFER, true);\ncurl_setopt($ch, CURLOPT_CUSTOMREQUEST, \(phpQ(r.method)));\n"
        if !r.headers.isEmpty { s += "curl_setopt($ch, CURLOPT_HTTPHEADER, [\n" + r.headers.map { "    \(phpQ("\($0.0): \($0.1)"))," }.joined(separator: "\n") + "\n]);\n" }
        if let b = r.body { s += "curl_setopt($ch, CURLOPT_POSTFIELDS, \(phpQ(b)));\n" }
        if let (u, p) = r.basicAuth { s += "curl_setopt($ch, CURLOPT_USERPWD, \(phpQ("\(u):\(p)")));\n" }
        if r.followRedirects { s += "curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);\n" }
        s += "\n$response = curl_exec($ch);\n$status = curl_getinfo($ch, CURLINFO_HTTP_CODE);\ncurl_close($ch);\n\necho $status . \"\\n\";\necho $response;\n"
        return s
    }
    static func phpQ(_ s: String) -> String { "'" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'" }

    static func ruby(_ r: HTTPRequestModel) -> String {
        var s = "require \"net/http\"\nrequire \"uri\"\nrequire \"json\"\n\nuri = URI(\(q(r.url)))\n"
        let cls = r.method.capitalized
        s += "request = Net::HTTP::\(["Get", "Post", "Put", "Delete", "Patch", "Head", "Options"].contains(cls) ? cls : "Get").new(uri)\n"
        for (k, v) in r.headers { s += "request[\(q(k))] = \(q(v))\n" }
        if let (u, p) = r.basicAuth { s += "request.basic_auth(\(q(u)), \(q(p)))\n" }
        if let b = r.body { s += r.isJSONBody ? "request.body = \(indentJSON(b, by: "")).to_json\n" : "request.body = \(q(b))\n" }
        s += "\nresponse = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == \"https\") do |http|\n  http.request(request)\nend\n\nputs response.code\nputs response.body\n"
        return s
    }

    static func rawHTTP(_ r: HTTPRequestModel) -> String {
        guard let u = URL(string: r.url) else { return "" }
        var path = u.path.isEmpty ? "/" : u.path
        if let q = u.query { path += "?" + q }
        var s = "\(r.method) \(path) HTTP/1.1\nHost: \(u.host ?? "")\n"
        for (k, v) in r.headers { s += "\(k): \(v)\n" }
        if let b = r.body { s += "Content-Length: \(b.utf8.count)\n\n\(b)" }
        return s
    }
}

public struct CurlToCodeTool: DevTool {
    public static let id = "curl.to-code"
    public static let name = "cURL → Code"
    public static let summary = "Turn a curl command into Swift, Python, JavaScript, Node, Go, Rust, PHP or Ruby"
    public static let category = ToolCategory.convert
    public static let symbol = "terminal"
    public static let keywords = ["curl", "http", "request", "fetch", "axios", "requests", "urlsession", "reqwest", "convert", "code"]
    public static let io = ToolIO.text(.shell, .swift)
    public static let samples = [ToolSample("POST JSON", "curl -X POST https://api.example.com/v1/users \\\n  -H 'Content-Type: application/json' \\\n  -H 'Authorization: Bearer TOKEN' \\\n  -d '{\"name\": \"Ada\", \"admin\": true}'")]
    public static let optionFields: [OptionField] = [
        .picker("target", "Target", [.init("swift", "Swift URLSession"), .init("python", "Python requests"), .init("fetch", "JavaScript fetch"), .init("axios", "Node axios"),
                                     .init("go", "Go net/http"), .init("rust", "Rust reqwest"), .init("php", "PHP cURL"), .init("ruby", "Ruby Net::HTTP"), .init("http", "Raw HTTP")], default: "swift"),
    ]
    public struct Options: ToolOptions {
        public var target = "swift"
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let r = try CurlParser.parse(text)
        let (code, lang): (String, CodeLanguage) = switch options.target {
        case "python": (CodeGen.python(r), .python)
        case "fetch": (CodeGen.fetch(r), .javascript)
        case "axios": (CodeGen.axios(r), .javascript)
        case "go": (CodeGen.go(r), .go)
        case "rust": (CodeGen.rust(r), .rust)
        case "php": (CodeGen.php(r), .php)
        case "ruby": (CodeGen.ruby(r), .ruby)
        case "http": (CodeGen.rawHTTP(r), .plain)
        default: (CodeGen.swift(r), .swift)
        }
        var meta = [MetaRow("Method", r.method), MetaRow("URL", r.url, style: .mono), MetaRow("Headers", "\(r.headers.count)")]
        if let b = r.body { meta.append(MetaRow("Body", r.isJSONBody ? "JSON (\(b.utf8.count) bytes)" : "\(b.utf8.count) bytes")) }
        return ToolOutput(text: code, language: lang, metadata: meta)
    }
    public static func detect(_ s: String) -> DetectionScore? {
        s.hasPrefix("curl ") || s.hasPrefix("curl\n") ? DetectionScore(0.95, "curl command") : nil
    }
}

public struct CodeToCurlTool: DevTool {
    public static let id = "code.to-curl"
    public static let name = "Code / HTTP → cURL"
    public static let summary = "Build a curl command from a raw HTTP request, fetch() call, axios or Python requests snippet"
    public static let category = ToolCategory.convert
    public static let symbol = "terminal.fill"
    public static let keywords = ["curl", "http", "request", "fetch", "axios", "reverse", "convert"]
    public static let io = ToolIO.text(.plain, .shell)
    public static let samples = [ToolSample("Raw HTTP", "POST /v1/items HTTP/1.1\nHost: api.example.com\nContent-Type: application/json\nAuthorization: Bearer abc\n\n{\"name\":\"Widget\"}"),
                                 ToolSample("fetch()", "await fetch(\"https://api.example.com/items?limit=5\", {\n  method: \"POST\",\n  headers: { \"Content-Type\": \"application/json\", \"X-Key\": \"k1\" },\n  body: JSON.stringify({ a: 1 })\n})")]
    public static let optionFields: [OptionField] = [.toggle("multiline", "Multi-line", default: true)]
    public struct Options: ToolOptions {
        public var multiline = true
        public init() {}
    }
    public init() {}
    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let r = try Self.parse(text)
        return ToolOutput(text: CurlParser.toCurl(r, multiline: options.multiline), language: .shell,
                          metadata: [MetaRow("Method", r.method), MetaRow("URL", r.url, style: .mono)])
    }

    static func parse(_ text: String) throws -> HTTPRequestModel {
        if text.range(of: "^[A-Z]+ \\S+ HTTP/\\d", options: .regularExpression) != nil { return try parseRaw(text) }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return HTTPRequestModel(method: "GET", url: text.split(separator: "\n")[0].trimmed()) }
        return try parseCode(text)
    }

    static func parseRaw(_ text: String) throws -> HTTPRequestModel {
        let parts = text.components(separatedBy: "\n\n")
        let lines = parts[0].split(separator: "\n").map { $0.removingSuffix("\r") }
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { throw ToolError("Invalid request line") }
        var r = HTTPRequestModel()
        r.method = String(first[0])
        var path = String(first[1])
        var host = ""
        for l in lines.dropFirst() {
            guard let c = l.firstIndex(of: ":") else { continue }
            let k = l[..<c].trimmed(), v = l[l.index(after: c)...].trimmed()
            if k.lowercased() == "host" { host = v } else if k.lowercased() != "content-length" { r.headers.append((k, v)) }
        }
        if !path.contains("://") { path = (host.contains(":443") ? "https://" : "https://") + host + path }
        r.url = path
        if parts.count > 1 { let b = parts[1...].joined(separator: "\n\n").trimmed(); if !b.isEmpty { r.body = b } }
        return r
    }

    static func parseCode(_ text: String) throws -> HTTPRequestModel {
        var r = HTTPRequestModel()
        guard let urlMatch = text.captures("[\"'`](https?://[^\"'`\\s]+)[\"'`]") else { throw ToolError("Could not find a URL in the snippet", hint: "Paste a fetch(), axios, requests call or a raw HTTP request") }
        r.url = urlMatch[1]
        if let m = text.captures("method\\s*[:=]\\s*[\"']([A-Za-z]+)[\"']") { r.method = m[1].uppercased() }
        else if let m = text.captures("(?:requests|axios|http)\\.(get|post|put|patch|delete|head)\\(") { r.method = m[1].uppercased() }
        if let m = text.captures("headers\\s*[:=]\\s*\\{([\\s\\S]*?)\\}") {
            for h in m[1].matches(of: /["']?([A-Za-z0-9\-]+)["']?\s*:\s*["']([^"']*)["']/) { r.headers.append((String(h.1), String(h.2))) }
        }
        if let m = text.captures("JSON\\.stringify\\(([\\s\\S]*?)\\)\\s*[,}\\n]") {
            if let v = try? JSONParser.parse(m[1], options: .json5) { r.body = JSONSerializer.string(v, options: .minified) }
            else { r.body = m[1].trimmed() }
        } else if let m = text.captures("(?:body|data|json)\\s*[:=]\\s*(\\{[\\s\\S]*?\\}|\\[[\\s\\S]*?\\]|[\"'][^\"']*[\"'])\\s*[,)\\n]") {
            var b = m[1].trimmed()
            if (b.hasPrefix("\"") && b.hasSuffix("\"")) || (b.hasPrefix("'") && b.hasSuffix("'")) { b = String(b.dropFirst().dropLast()) }
            else if let v = try? JSONParser.parse(b, options: .json5) { b = JSONSerializer.string(v, options: .minified) }
            r.body = b
        }
        if r.body != nil, r.method == "GET" { r.method = "POST" }
        if r.body != nil, r.isJSONBody, r.contentType == nil { r.headers.append(("Content-Type", "application/json")) }
        return r
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.range(of: "^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) /\\S* HTTP/1\\.[01]", options: .regularExpression) != nil { return DetectionScore(0.9, "Raw HTTP request") }
        if s.contains("fetch(") || s.contains("axios.") || s.contains("requests.") , s.contains("http") { return DetectionScore(0.55, "HTTP client code") }
        return nil
    }
}
