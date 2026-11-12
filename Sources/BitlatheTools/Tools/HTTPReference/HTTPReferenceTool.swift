import Foundation
import BitlatheCore

public struct HTTPReferenceTool: DevTool {
    public static let id = "http.reference"
    public static let name = "HTTP Reference"
    public static let summary = "Look up HTTP status codes, headers and methods"
    public static let category = ToolCategory.inspect
    public static let symbol = "network"
    public static let keywords = ["http", "status", "code", "header", "404", "500", "reference", "cors", "cache-control", "method"]
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: false)
    public static let samples = [ToolSample("Status", "418"), ToolSample("Header", "Cache-Control"), ToolSample("Search", "redirect")]
    public static let optionFields: [OptionField] = [.segmented("scope", "Show", [.init("all", "All"), .init("status", "Status codes"), .init("headers", "Headers"), .init("methods", "Methods")], default: "all")]
    public struct Options: ToolOptions {
        public var scope = "all"
        public init() {}
    }
    public init() {}

    public struct Entry: Sendable, Identifiable, Equatable {
        public var id: String { kind + ":" + name }
        public var kind: String
        public var name: String
        public var title: String
        public var detail: String
        public var spec: String
    }

    public static let statuses: [Entry] = [
        (100, "Continue", "The server received the request headers; the client should send the body.", "RFC 9110"), (101, "Switching Protocols", "The server agrees to switch protocols as requested via Upgrade.", "RFC 9110"),
        (102, "Processing", "WebDAV: the server is processing but no response is available yet.", "RFC 2518"), (103, "Early Hints", "Preload hints sent before the final response.", "RFC 8297"),
        (200, "OK", "The request succeeded.", "RFC 9110"), (201, "Created", "A new resource was created; Location usually points to it.", "RFC 9110"), (202, "Accepted", "Accepted for processing, not completed.", "RFC 9110"),
        (203, "Non-Authoritative Information", "Transformed by a proxy.", "RFC 9110"), (204, "No Content", "Success with no body.", "RFC 9110"), (205, "Reset Content", "Success; the client should reset the document view.", "RFC 9110"),
        (206, "Partial Content", "Range request succeeded.", "RFC 9110"), (207, "Multi-Status", "WebDAV: multiple status codes in the body.", "RFC 4918"), (208, "Already Reported", "WebDAV: members already enumerated.", "RFC 5842"), (226, "IM Used", "Delta encoding applied.", "RFC 3229"),
        (300, "Multiple Choices", "Several representations are available.", "RFC 9110"), (301, "Moved Permanently", "Permanent redirect; method may change to GET.", "RFC 9110"), (302, "Found", "Temporary redirect; method may change to GET.", "RFC 9110"),
        (303, "See Other", "Redirect with GET to another URI (after POST).", "RFC 9110"), (304, "Not Modified", "Cached version is still valid.", "RFC 9110"), (307, "Temporary Redirect", "Temporary redirect; method and body preserved.", "RFC 9110"), (308, "Permanent Redirect", "Permanent redirect; method and body preserved.", "RFC 9110"),
        (400, "Bad Request", "Malformed syntax or invalid request.", "RFC 9110"), (401, "Unauthorized", "Authentication required or failed (WWW-Authenticate).", "RFC 9110"), (402, "Payment Required", "Reserved; used by some APIs for billing.", "RFC 9110"),
        (403, "Forbidden", "Authenticated but not allowed.", "RFC 9110"), (404, "Not Found", "No resource at this URI.", "RFC 9110"), (405, "Method Not Allowed", "Method not supported; see Allow header.", "RFC 9110"), (406, "Not Acceptable", "No representation matches Accept headers.", "RFC 9110"),
        (407, "Proxy Authentication Required", "Authenticate with the proxy first.", "RFC 9110"), (408, "Request Timeout", "Server timed out waiting for the request.", "RFC 9110"), (409, "Conflict", "Conflicts with the current state (e.g. version mismatch).", "RFC 9110"),
        (410, "Gone", "Permanently removed; clients should purge references.", "RFC 9110"), (411, "Length Required", "Content-Length is required.", "RFC 9110"), (412, "Precondition Failed", "If-Match / If-Unmodified-Since failed.", "RFC 9110"),
        (413, "Content Too Large", "Request body too large.", "RFC 9110"), (414, "URI Too Long", "The URI is longer than the server accepts.", "RFC 9110"), (415, "Unsupported Media Type", "Content-Type not supported.", "RFC 9110"),
        (416, "Range Not Satisfiable", "Requested range is outside the resource.", "RFC 9110"), (417, "Expectation Failed", "Expect header cannot be met.", "RFC 9110"), (418, "I'm a teapot", "April Fools' joke (HTCPCP). Some servers return it for refused requests.", "RFC 2324"),
        (421, "Misdirected Request", "Sent to a server that cannot produce a response for this authority.", "RFC 9110"), (422, "Unprocessable Content", "Well-formed but semantically invalid (validation errors).", "RFC 9110"), (423, "Locked", "WebDAV: resource is locked.", "RFC 4918"),
        (424, "Failed Dependency", "WebDAV: a prior request failed.", "RFC 4918"), (425, "Too Early", "Risk of replay; retry later.", "RFC 8470"), (426, "Upgrade Required", "Switch to a different protocol (Upgrade header).", "RFC 9110"),
        (428, "Precondition Required", "Server requires conditional requests.", "RFC 6585"), (429, "Too Many Requests", "Rate limited; check Retry-After.", "RFC 6585"), (431, "Request Header Fields Too Large", "Headers are too large.", "RFC 6585"),
        (451, "Unavailable For Legal Reasons", "Blocked for legal reasons.", "RFC 7725"), (499, "Client Closed Request", "nginx: client closed the connection before the response.", "nginx"),
        (500, "Internal Server Error", "Unexpected server failure.", "RFC 9110"), (501, "Not Implemented", "Method not supported by the server.", "RFC 9110"), (502, "Bad Gateway", "Invalid response from an upstream server.", "RFC 9110"),
        (503, "Service Unavailable", "Overloaded or down for maintenance; check Retry-After.", "RFC 9110"), (504, "Gateway Timeout", "Upstream server did not respond in time.", "RFC 9110"), (505, "HTTP Version Not Supported", "HTTP version not supported.", "RFC 9110"),
        (506, "Variant Also Negotiates", "Content negotiation misconfiguration.", "RFC 2295"), (507, "Insufficient Storage", "WebDAV: out of storage.", "RFC 4918"), (508, "Loop Detected", "WebDAV: infinite loop.", "RFC 5842"),
        (510, "Not Extended", "Further extensions required.", "RFC 2774"), (511, "Network Authentication Required", "Captive portal: authenticate to gain network access.", "RFC 6585"),
        (520, "Web Server Returned an Unknown Error", "Cloudflare: origin returned an empty/unknown response.", "Cloudflare"), (521, "Web Server Is Down", "Cloudflare: origin refused the connection.", "Cloudflare"),
        (522, "Connection Timed Out", "Cloudflare: TCP handshake with origin timed out.", "Cloudflare"), (523, "Origin Is Unreachable", "Cloudflare: cannot reach origin.", "Cloudflare"), (524, "A Timeout Occurred", "Cloudflare: origin did not respond in time.", "Cloudflare"),
        (525, "SSL Handshake Failed", "Cloudflare: TLS handshake with origin failed.", "Cloudflare"), (526, "Invalid SSL Certificate", "Cloudflare: origin certificate invalid.", "Cloudflare"),
    ].map { Entry(kind: "status", name: String($0.0), title: $0.1, detail: $0.2, spec: $0.3) }

    public static let headers: [Entry] = [
        ("Accept", "Media types the client can handle.", "Accept: application/json, text/plain;q=0.9"), ("Accept-Encoding", "Content encodings the client supports.", "Accept-Encoding: gzip, br"),
        ("Accept-Language", "Preferred natural languages.", "Accept-Language: en-GB, en;q=0.8"), ("Access-Control-Allow-Origin", "CORS: origins allowed to read the response.", "Access-Control-Allow-Origin: https://app.example.com"),
        ("Access-Control-Allow-Methods", "CORS preflight: allowed methods.", "Access-Control-Allow-Methods: GET, POST, PUT"), ("Access-Control-Allow-Headers", "CORS preflight: allowed request headers.", "Access-Control-Allow-Headers: Authorization, Content-Type"),
        ("Access-Control-Allow-Credentials", "CORS: allow cookies/credentials.", "Access-Control-Allow-Credentials: true"), ("Access-Control-Max-Age", "CORS: how long the preflight can be cached.", "Access-Control-Max-Age: 86400"),
        ("Access-Control-Expose-Headers", "CORS: response headers exposed to JS.", "Access-Control-Expose-Headers: X-Request-Id"), ("Age", "Seconds the response spent in a cache.", "Age: 120"),
        ("Allow", "Methods supported by the resource (with 405).", "Allow: GET, HEAD, OPTIONS"), ("Authorization", "Credentials for the request.", "Authorization: Bearer <token>"),
        ("Cache-Control", "Caching directives for requests and responses.", "Cache-Control: public, max-age=3600, stale-while-revalidate=60"), ("Clear-Site-Data", "Clear browsing data for the origin.", "Clear-Site-Data: \"cache\", \"cookies\""),
        ("Connection", "Connection control (keep-alive/close).", "Connection: keep-alive"), ("Content-Disposition", "Inline vs attachment and filename.", "Content-Disposition: attachment; filename=\"report.pdf\""),
        ("Content-Encoding", "Encoding applied to the body.", "Content-Encoding: br"), ("Content-Language", "Language of the body.", "Content-Language: de-DE"), ("Content-Length", "Body size in bytes.", "Content-Length: 348"),
        ("Content-Location", "Alternate location for the returned data.", "Content-Location: /documents/foo.json"), ("Content-Range", "Where a partial body belongs.", "Content-Range: bytes 200-1000/67589"),
        ("Content-Security-Policy", "Controls which resources the page may load.", "Content-Security-Policy: default-src 'self'; img-src https:"), ("Content-Type", "Media type of the body.", "Content-Type: application/json; charset=utf-8"),
        ("Cookie", "Cookies sent by the client.", "Cookie: session=abc; theme=dark"), ("Cross-Origin-Embedder-Policy", "Require CORP/CORS for embedded resources.", "Cross-Origin-Embedder-Policy: require-corp"),
        ("Cross-Origin-Opener-Policy", "Isolate the browsing context group.", "Cross-Origin-Opener-Policy: same-origin"), ("Cross-Origin-Resource-Policy", "Who may load this resource.", "Cross-Origin-Resource-Policy: same-site"),
        ("Date", "When the message was originated.", "Date: Wed, 21 Oct 2026 07:28:00 GMT"), ("ETag", "Version identifier for conditional requests.", "ETag: \"33a64df5\""), ("Expect", "Expectations the server must meet.", "Expect: 100-continue"),
        ("Expires", "Legacy expiry date; Cache-Control max-age wins.", "Expires: Wed, 21 Oct 2026 07:28:00 GMT"), ("Forwarded", "Proxy-added client info (standard).", "Forwarded: for=192.0.2.60;proto=http;by=203.0.113.43"),
        ("From", "Email of the requesting user/agent.", "From: ops@example.com"), ("Host", "Target host and port (required in HTTP/1.1).", "Host: api.example.com"),
        ("If-Match", "Conditional: only if ETag matches.", "If-Match: \"33a64df5\""), ("If-Modified-Since", "Conditional GET by date.", "If-Modified-Since: Sat, 29 Oct 2025 19:43:31 GMT"),
        ("If-None-Match", "Conditional: only if ETag differs (304).", "If-None-Match: \"33a64df5\""), ("If-Range", "Range only if unchanged.", "If-Range: \"33a64df5\""), ("If-Unmodified-Since", "Conditional by date (412).", "If-Unmodified-Since: Sat, 29 Oct 2025 19:43:31 GMT"),
        ("Keep-Alive", "Connection timeout/max hints.", "Keep-Alive: timeout=5, max=1000"), ("Last-Modified", "When the resource last changed.", "Last-Modified: Tue, 15 Nov 2025 12:45:26 GMT"),
        ("Link", "Related resources (pagination, preload).", "Link: </page/2>; rel=\"next\""), ("Location", "Redirect target or created resource.", "Location: /users/42"), ("Origin", "Origin of the request (CORS).", "Origin: https://app.example.com"),
        ("Permissions-Policy", "Enable/disable browser features.", "Permissions-Policy: geolocation=(), camera=()"), ("Pragma", "Legacy no-cache.", "Pragma: no-cache"), ("Proxy-Authorization", "Credentials for a proxy.", "Proxy-Authorization: Basic …"),
        ("Range", "Request part of a resource.", "Range: bytes=0-1023"), ("Referer", "Address of the previous page (sic).", "Referer: https://example.com/page"), ("Referrer-Policy", "How much Referer to send.", "Referrer-Policy: strict-origin-when-cross-origin"),
        ("Retry-After", "When to retry (429/503/3xx).", "Retry-After: 120"), ("Server", "Server software.", "Server: nginx/1.27"), ("Server-Timing", "Timing metrics for devtools.", "Server-Timing: db;dur=53, app;dur=47.2"),
        ("Set-Cookie", "Send a cookie to the client.", "Set-Cookie: id=a3f; Path=/; HttpOnly; Secure; SameSite=Lax"), ("Strict-Transport-Security", "Force HTTPS (HSTS).", "Strict-Transport-Security: max-age=63072000; includeSubDomains; preload"),
        ("TE", "Transfer encodings the client accepts.", "TE: trailers"), ("Trailer", "Headers present in the trailer.", "Trailer: Expires"), ("Transfer-Encoding", "Body transfer form (chunked).", "Transfer-Encoding: chunked"),
        ("Upgrade", "Switch protocol (WebSocket).", "Upgrade: websocket"), ("User-Agent", "Client software identification.", "User-Agent: Mozilla/5.0 (…)"), ("Vary", "Request headers that affect the cached response.", "Vary: Accept-Encoding, Origin"),
        ("Via", "Proxies the message passed through.", "Via: 1.1 vegur"), ("WWW-Authenticate", "Authentication challenge (401).", "WWW-Authenticate: Bearer realm=\"api\""), ("X-Content-Type-Options", "Disable MIME sniffing.", "X-Content-Type-Options: nosniff"),
        ("X-Forwarded-For", "De-facto client IP behind proxies.", "X-Forwarded-For: 203.0.113.195, 70.41.3.18"), ("X-Forwarded-Proto", "Original protocol behind a proxy.", "X-Forwarded-Proto: https"), ("X-Frame-Options", "Legacy clickjacking protection.", "X-Frame-Options: DENY"),
        ("X-Request-Id", "Correlation id for tracing (de-facto).", "X-Request-Id: 7c1e…"), ("X-RateLimit-Limit", "Rate limit ceiling (de-facto).", "X-RateLimit-Limit: 1000"), ("X-RateLimit-Remaining", "Requests left in the window (de-facto).", "X-RateLimit-Remaining: 998"),
        ("X-XSS-Protection", "Legacy XSS filter; use CSP instead.", "X-XSS-Protection: 0"), ("Sec-Fetch-Site", "Relationship between request origin and target.", "Sec-Fetch-Site: same-origin"), ("Sec-Fetch-Mode", "Request mode (navigate, cors…).", "Sec-Fetch-Mode: cors"),
        ("Sec-Fetch-Dest", "Request destination (document, image…).", "Sec-Fetch-Dest: image"), ("Sec-WebSocket-Key", "WebSocket handshake nonce.", "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=="), ("Idempotency-Key", "De-duplicate retried POSTs (de-facto).", "Idempotency-Key: 8e03978e-40d5"),
    ].map { Entry(kind: "header", name: $0.0, title: $0.0, detail: $0.1, spec: $0.2) }

    public static let methods: [Entry] = [
        ("GET", "Retrieve a representation. Safe, idempotent, cacheable."), ("HEAD", "Like GET without the body. Safe, idempotent."), ("POST", "Submit data / create. Not idempotent."), ("PUT", "Replace the resource. Idempotent."),
        ("PATCH", "Partial update. Not necessarily idempotent."), ("DELETE", "Remove the resource. Idempotent."), ("OPTIONS", "Describe communication options; CORS preflight."), ("CONNECT", "Open a tunnel (HTTPS through proxy)."), ("TRACE", "Echo the request for diagnostics."),
        ("QUERY", "Safe request with a body (draft)."), ("PROPFIND", "WebDAV: retrieve properties."), ("MKCOL", "WebDAV: create a collection."), ("COPY", "WebDAV: copy a resource."), ("MOVE", "WebDAV: move a resource."), ("LOCK", "WebDAV: lock a resource."),
    ].map { Entry(kind: "method", name: $0.0, title: $0.0, detail: $0.1, spec: "RFC 9110 / 4918") }

    public static func search(_ query: String, scope: String = "all") -> [Entry] {
        var pool: [Entry] = []
        if scope == "all" || scope == "status" { pool += statuses }
        if scope == "all" || scope == "headers" { pool += headers }
        if scope == "all" || scope == "methods" { pool += methods }
        let q = query.trimmed().lowercased()
        if q.isEmpty { return pool }
        if let n = Int(q) {
            if let exact = pool.first(where: { $0.kind == "status" && $0.name == String(n) }) { return [exact] + pool.filter { $0.kind == "status" && $0.name.hasPrefix(String(n / 100)) && $0.name != String(n) } }
            return pool.filter { $0.name.hasPrefix(q) }
        }
        let exact = pool.filter { $0.name.lowercased() == q || $0.title.lowercased() == q }
        if !exact.isEmpty { return exact }
        let scored = pool.compactMap { e -> (Entry, Int)? in
            let hay = (e.name + " " + e.title + " " + e.detail + " " + e.spec).lowercased()
            if e.name.lowercased().hasPrefix(q) { return (e, 3) }
            if e.name.lowercased().contains(q) || e.title.lowercased().contains(q) { return (e, 2) }
            if hay.contains(q) { return (e, 1) }
            return Fuzzy.score(query: q, in: e.name) != nil ? (e, 0) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        let results = Self.search(text, scope: options.scope)
        if results.isEmpty { throw ToolError("Nothing matches \"\(text)\"", hint: "Try a status code (404), a header name (ETag) or a word (cache)") }
        let rows = results.prefix(60).map { e -> MetaRow in
            switch e.kind {
            case "status":
                let code = Int(e.name) ?? 0
                let style: MetaRow.Style = code >= 500 ? .danger : (code >= 400 ? .warning : (code >= 200 && code < 300 ? .success : .plain))
                return MetaRow("\(e.name) \(e.title)", "\(e.detail)  [\(e.spec)]", style: style)
            case "header": return MetaRow(e.name, "\(e.detail)  e.g. \(e.spec)")
            default: return MetaRow(e.name, e.detail)
            }
        }
        let listing = results.prefix(60).map { e in e.kind == "status" ? "\(e.name) \(e.title) — \(e.detail)" : "\(e.name) — \(e.detail)" }.joined(separator: "\n")
        return ToolOutput(text: listing, metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.range(of: "^[1-5]\\d\\d$", options: .regularExpression) != nil, statuses.contains(where: { $0.name == s }) { return DetectionScore(0.6, "HTTP status code") }
        if headers.contains(where: { $0.name.lowercased() == s.lowercased() }) { return DetectionScore(0.7, "HTTP header name") }
        return nil
    }
}
