import Foundation
import BitlatheCore
import UniformTypeIdentifiers

public struct MIMELookupTool: DevTool {
    public static let id = "mime.lookup"
    public static let name = "MIME Type Lookup"
    public static let summary = "Find the MIME type for a file extension, the extensions for a MIME type, and the UTI"
    public static let category = ToolCategory.inspect
    public static let symbol = "doc.badge.gearshape"
    public static let keywords = ["mime", "content-type", "media type", "extension", "uti", "file type", "lookup"]
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: false)
    public static let samples = [ToolSample("Extension", ".webp"), ToolSample("MIME type", "application/json"), ToolSample("Search", "font")]
    public struct Options: ToolOptions { public init() {} }
    public init() {}

    static let table: [(String, [String], String)] = [
        ("application/json", ["json"], "JSON"), ("application/ld+json", ["jsonld"], "JSON-LD"), ("application/xml", ["xml", "xsd"], "XML"), ("text/xml", ["xml"], "XML (text)"), ("application/yaml", ["yaml", "yml"], "YAML"),
        ("application/toml", ["toml"], "TOML"), ("text/csv", ["csv"], "CSV"), ("text/tab-separated-values", ["tsv"], "TSV"), ("text/plain", ["txt", "log", "text"], "Plain text"), ("text/markdown", ["md", "markdown"], "Markdown"),
        ("text/html", ["html", "htm"], "HTML"), ("text/css", ["css"], "CSS"), ("text/javascript", ["js", "mjs"], "JavaScript"), ("application/javascript", ["js"], "JavaScript (legacy)"), ("application/typescript", ["ts"], "TypeScript"),
        ("application/wasm", ["wasm"], "WebAssembly"), ("application/graphql", ["graphql", "gql"], "GraphQL"), ("application/x-www-form-urlencoded", [], "Form data"), ("multipart/form-data", [], "Multipart form"),
        ("application/octet-stream", ["bin", "dat"], "Binary"), ("application/pdf", ["pdf"], "PDF"), ("application/zip", ["zip"], "ZIP"), ("application/gzip", ["gz", "tgz"], "Gzip"), ("application/x-tar", ["tar"], "TAR"),
        ("application/x-7z-compressed", ["7z"], "7-Zip"), ("application/vnd.rar", ["rar"], "RAR"), ("application/x-bzip2", ["bz2"], "Bzip2"), ("application/zstd", ["zst"], "Zstandard"), ("application/x-xz", ["xz"], "XZ"),
        ("image/png", ["png"], "PNG"), ("image/jpeg", ["jpg", "jpeg"], "JPEG"), ("image/gif", ["gif"], "GIF"), ("image/webp", ["webp"], "WebP"), ("image/avif", ["avif"], "AVIF"), ("image/heic", ["heic"], "HEIC"), ("image/heif", ["heif"], "HEIF"),
        ("image/svg+xml", ["svg"], "SVG"), ("image/x-icon", ["ico"], "ICO"), ("image/vnd.microsoft.icon", ["ico"], "ICO"), ("image/bmp", ["bmp"], "BMP"), ("image/tiff", ["tif", "tiff"], "TIFF"), ("image/apng", ["apng"], "Animated PNG"), ("image/jxl", ["jxl"], "JPEG XL"),
        ("audio/mpeg", ["mp3"], "MP3"), ("audio/wav", ["wav"], "WAV"), ("audio/ogg", ["oga", "ogg"], "Ogg audio"), ("audio/aac", ["aac"], "AAC"), ("audio/flac", ["flac"], "FLAC"), ("audio/mp4", ["m4a"], "MPEG-4 audio"), ("audio/webm", ["weba"], "WebM audio"), ("audio/opus", ["opus"], "Opus"),
        ("video/mp4", ["mp4", "m4v"], "MP4"), ("video/webm", ["webm"], "WebM"), ("video/quicktime", ["mov"], "QuickTime"), ("video/x-matroska", ["mkv"], "Matroska"), ("video/mpeg", ["mpeg", "mpg"], "MPEG"), ("video/ogg", ["ogv"], "Ogg video"), ("video/x-msvideo", ["avi"], "AVI"), ("application/x-mpegURL", ["m3u8"], "HLS playlist"), ("video/mp2t", ["ts"], "MPEG-TS"),
        ("font/woff", ["woff"], "WOFF"), ("font/woff2", ["woff2"], "WOFF2"), ("font/ttf", ["ttf"], "TrueType"), ("font/otf", ["otf"], "OpenType"), ("application/vnd.ms-fontobject", ["eot"], "EOT"),
        ("application/msword", ["doc"], "Word 97"), ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", ["docx"], "Word"), ("application/vnd.ms-excel", ["xls"], "Excel 97"),
        ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", ["xlsx"], "Excel"), ("application/vnd.ms-powerpoint", ["ppt"], "PowerPoint 97"), ("application/vnd.openxmlformats-officedocument.presentationml.presentation", ["pptx"], "PowerPoint"),
        ("application/vnd.apple.keynote", ["key"], "Keynote"), ("application/vnd.apple.pages", ["pages"], "Pages"), ("application/vnd.apple.numbers", ["numbers"], "Numbers"), ("application/epub+zip", ["epub"], "EPUB"), ("application/rtf", ["rtf"], "RTF"),
        ("application/vnd.oasis.opendocument.text", ["odt"], "OpenDocument text"), ("application/vnd.oasis.opendocument.spreadsheet", ["ods"], "OpenDocument spreadsheet"),
        ("application/x-apple-diskimage", ["dmg"], "Disk image"), ("application/vnd.apple.installer+xml", ["pkg"], "Installer package"), ("application/vnd.android.package-archive", ["apk"], "Android package"), ("application/x-msdownload", ["exe", "dll"], "Windows executable"),
        ("application/x-sh", ["sh"], "Shell script"), ("application/x-python", ["py"], "Python"), ("text/x-swift", ["swift"], "Swift"), ("text/x-go", ["go"], "Go"), ("text/x-rust", ["rs"], "Rust"), ("text/x-java-source", ["java"], "Java"), ("text/x-c", ["c", "h"], "C"), ("text/x-c++", ["cpp", "hpp", "cc"], "C++"),
        ("application/x-httpd-php", ["php"], "PHP"), ("text/x-ruby", ["rb"], "Ruby"), ("application/sql", ["sql"], "SQL"), ("application/x-sqlite3", ["sqlite", "db"], "SQLite"), ("application/x-ndjson", ["ndjson", "jsonl"], "Newline-delimited JSON"),
        ("application/x-pem-file", ["pem"], "PEM"), ("application/x-x509-ca-cert", ["crt", "cer", "der"], "X.509 certificate"), ("application/pkcs12", ["p12", "pfx"], "PKCS #12"), ("application/pkcs8", ["p8"], "PKCS #8 key"), ("application/jwt", ["jwt"], "JSON Web Token"),
        ("application/x-protobuf", ["pb", "proto"], "Protocol Buffers"), ("application/msgpack", ["msgpack"], "MessagePack"), ("application/cbor", ["cbor"], "CBOR"), ("application/vnd.api+json", [], "JSON:API"), ("application/problem+json", [], "Problem details"),
        ("text/event-stream", [], "Server-sent events"), ("application/x-ndjson", [], "NDJSON stream"), ("text/calendar", ["ics"], "iCalendar"), ("text/vcard", ["vcf"], "vCard"), ("application/rss+xml", ["rss"], "RSS"), ("application/atom+xml", ["atom"], "Atom"),
        ("application/manifest+json", ["webmanifest"], "Web app manifest"), ("application/x-bittorrent", ["torrent"], "Torrent"), ("model/gltf+json", ["gltf"], "glTF"), ("model/gltf-binary", ["glb"], "glTF binary"), ("model/usd", ["usdz", "usd"], "USD"), ("model/stl", ["stl"], "STL"),
    ]

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let raw = input.text.trimmed()
        guard !raw.isEmpty else { throw ToolError.emptyInput }
        let q = raw.lowercased().removingPrefix("*").removingPrefix(".")
        var rows: [MetaRow] = []
        var matches: [(String, [String], String)] = []
        if q.contains("/") {
            matches = Self.table.filter { $0.0.lowercased() == q }
            if matches.isEmpty { matches = Self.table.filter { $0.0.lowercased().contains(q) } }
            if let ut = UTType(mimeType: q) {
                rows.append(MetaRow("UTI", ut.identifier, style: .mono))
                rows.append(MetaRow("Description", ut.localizedDescription ?? "—"))
                let exts = ut.tags[.filenameExtension] ?? []
                if !exts.isEmpty { rows.append(MetaRow("Extensions (system)", exts.map { "." + $0 }.joined(separator: ", "))) }
            }
        } else if q.count <= 10, !q.contains(" ") {
            matches = Self.table.filter { $0.1.contains(q) }
            if let ut = UTType(filenameExtension: q) {
                rows.append(MetaRow("UTI", ut.identifier, style: .mono))
                rows.append(MetaRow("Description", ut.localizedDescription ?? "—"))
                if let m = ut.preferredMIMEType { rows.append(MetaRow("MIME (system)", m, style: .mono)) }
                rows.append(MetaRow("Conforms to", ut.supertypes.prefix(6).map(\.identifier).joined(separator: ", "), style: .mono))
            }
            if matches.isEmpty && rows.isEmpty { matches = Self.table.filter { $0.0.contains(q) || $0.2.lowercased().contains(q) } }
        } else {
            matches = Self.table.filter { $0.0.contains(q) || $0.2.lowercased().contains(q) || $0.1.contains(where: { $0.contains(q) }) }
        }
        for m in matches.prefix(40) {
            rows.append(MetaRow(m.0, "\(m.2)" + (m.1.isEmpty ? "" : " · ." + m.1.joined(separator: ", .")), style: .mono))
        }
        guard !rows.isEmpty else { throw ToolError("No MIME type found for \"\(raw)\"") }
        let primary = matches.first?.0 ?? rows.first { $0.label == "MIME (system)" }?.value ?? ""
        return ToolOutput(text: primary, metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.range(of: "^(application|text|image|audio|video|font|model|multipart)/[a-z0-9.+-]+$", options: .regularExpression) != nil { return DetectionScore(0.85, "MIME type") }
        if s.range(of: "^\\.[a-z0-9]{1,8}$", options: .regularExpression) != nil { return DetectionScore(0.7, "File extension") }
        return nil
    }
}
