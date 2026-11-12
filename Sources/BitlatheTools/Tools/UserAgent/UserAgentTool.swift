import Foundation
import BitlatheCore

public struct UserAgentTool: DevTool {
    public static let id = "useragent.parse"
    public static let name = "User-Agent Parser"
    public static let summary = "Identify browser, engine, OS, device and bots from a User-Agent string"
    public static let category = ToolCategory.inspect
    public static let symbol = "person.text.rectangle"
    public static let keywords = ["user agent", "ua", "browser", "device", "os", "bot", "crawler", "parse"]
    public static let samples = [ToolSample("Safari on Mac", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"),
                                 ToolSample("Chrome on Android", "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"),
                                 ToolSample("Googlebot", "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Googlebot/2.1; +http://www.google.com/bot.html) Chrome/130.0.0.0 Safari/537.36")]
    public struct Options: ToolOptions { public init() {} }
    public init() {}

    public struct Result: Sendable, Equatable {
        public var browser = "Unknown"
        public var browserVersion = ""
        public var engine = "Unknown"
        public var engineVersion = ""
        public var os = "Unknown"
        public var osVersion = ""
        public var device = "Desktop"
        public var deviceModel = ""
        public var vendor = ""
        public var isBot = false
        public var botName = ""
        public var cpu = ""
    }

    static func cap(_ s: String, _ pattern: String, _ group: Int = 1) -> String? {
        s.captures(pattern).flatMap { $0.count > group ? ($0[group].isEmpty ? nil : $0[group]) : nil }
    }

    public static func parse(_ ua: String) -> Result {
        var r = Result()
        let s = ua
        // Bots
        let bots: [(String, String)] = [("Googlebot", "Googlebot"), ("bingbot", "Bingbot"), ("Slurp", "Yahoo Slurp"), ("DuckDuckBot", "DuckDuckBot"), ("Baiduspider", "Baiduspider"), ("YandexBot", "YandexBot"),
                                       ("facebookexternalhit", "Facebook"), ("Twitterbot", "Twitterbot"), ("LinkedInBot", "LinkedInBot"), ("Slackbot", "Slackbot"), ("Discordbot", "Discordbot"), ("TelegramBot", "TelegramBot"),
                                       ("WhatsApp", "WhatsApp"), ("Applebot", "Applebot"), ("GPTBot", "GPTBot"), ("ClaudeBot", "ClaudeBot"), ("anthropic-ai", "Anthropic"), ("PerplexityBot", "PerplexityBot"), ("Bytespider", "Bytespider"),
                                       ("AhrefsBot", "AhrefsBot"), ("SemrushBot", "SemrushBot"), ("MJ12bot", "Majestic"), ("PetalBot", "PetalBot"), ("curl/", "curl"), ("Wget/", "Wget"), ("python-requests", "python-requests"),
                                       ("Go-http-client", "Go http client"), ("okhttp", "OkHttp"), ("PostmanRuntime", "Postman"), ("insomnia", "Insomnia"), ("HeadlessChrome", "Headless Chrome"), ("Lighthouse", "Lighthouse"), ("UptimeRobot", "UptimeRobot")]
        for (needle, name) in bots where s.range(of: needle, options: .caseInsensitive) != nil { r.isBot = true; r.botName = name; break }
        if !r.isBot, s.range(of: "bot|crawl|spider|scraper|fetch", options: [.regularExpression, .caseInsensitive]) != nil { r.isBot = true; r.botName = cap(s, "([A-Za-z0-9_-]*(?:[Bb]ot|[Cc]rawler|[Ss]pider))") ?? "Bot" }

        // OS
        if let v = cap(s, "Windows NT ([\\d.]+)") {
            r.os = "Windows"
            r.osVersion = ["10.0": "10 / 11", "6.3": "8.1", "6.2": "8", "6.1": "7", "6.0": "Vista", "5.1": "XP"][v] ?? v
        } else if let v = cap(s, "iPhone OS ([\\d_]+)") { r.os = "iOS"; r.osVersion = v.replacingOccurrences(of: "_", with: ".") }
        else if s.contains("iPad"), let v = cap(s, "CPU OS ([\\d_]+)") { r.os = "iPadOS"; r.osVersion = v.replacingOccurrences(of: "_", with: ".") }
        else if let v = cap(s, "Mac OS X ([\\d_.]+)") {
            r.os = "macOS"
            r.osVersion = v.replacingOccurrences(of: "_", with: ".")
            if r.osVersion == "10.15.7", s.contains("Version/") { r.osVersion += " (frozen; real version hidden by Safari)" }
        }
        else if let v = cap(s, "Android ([\\d.]+)") { r.os = "Android"; r.osVersion = v }
        else if let v = cap(s, "CrOS [a-z0-9_]+ ([\\d.]+)") { r.os = "ChromeOS"; r.osVersion = v }
        else if s.contains("Linux") { r.os = "Linux"; r.osVersion = cap(s, "(Ubuntu|Fedora|Debian|Arch|Mint)") ?? "" }
        else if s.contains("FreeBSD") { r.os = "FreeBSD" }
        else if s.contains("Darwin") { r.os = "Darwin" }

        // CPU
        if s.contains("x86_64") || s.contains("Win64") || s.contains("x64") || s.contains("WOW64") { r.cpu = "x86-64" }
        else if s.contains("arm64") || s.contains("aarch64") || s.contains("ARM64") { r.cpu = "ARM64" }
        else if s.contains("Intel Mac") { r.cpu = "x86-64 (or Apple silicon via Rosetta/UA freeze)" }
        else if s.contains("PPC") { r.cpu = "PowerPC" }
        else if s.contains("armv7") || s.contains("arm;") { r.cpu = "ARM" }

        // Device
        if s.contains("iPhone") { r.device = "Phone"; r.deviceModel = "iPhone"; r.vendor = "Apple" }
        else if s.contains("iPad") { r.device = "Tablet"; r.deviceModel = "iPad"; r.vendor = "Apple" }
        else if s.contains("Macintosh") { r.device = "Desktop"; r.deviceModel = "Mac"; r.vendor = "Apple" }
        else if s.contains("Android") {
            r.device = s.contains("Mobile") ? "Phone" : "Tablet"
            if let m = cap(s, "Android [\\d.]+; ([^;)]+?)(?: Build|\\))") { r.deviceModel = m }
            if r.deviceModel.hasPrefix("SM-") || r.deviceModel.contains("Samsung") { r.vendor = "Samsung" }
            else if r.deviceModel.hasPrefix("Pixel") { r.vendor = "Google" }
            else if r.deviceModel.contains("OnePlus") { r.vendor = "OnePlus" }
            else if r.deviceModel.hasPrefix("M2") || r.deviceModel.contains("Redmi") || r.deviceModel.contains("Xiaomi") { r.vendor = "Xiaomi" }
        }
        else if s.contains("Windows Phone") { r.device = "Phone" }
        else if s.contains("Apple TV") || s.contains("SMART-TV") || s.contains("SmartTV") || s.contains("Tizen") { r.device = "TV" }
        else if s.contains("PlayStation") || s.contains("Xbox") || s.contains("Nintendo") { r.device = "Console" }
        else if s.contains("Mobile") { r.device = "Phone" }

        // Browser (order matters)
        let browsers: [(String, String, String)] = [
            ("Edg(?:e|A|iOS)?/([\\d.]+)", "Microsoft Edge", "Blink"), ("OPR/([\\d.]+)", "Opera", "Blink"), ("Opera[ /]([\\d.]+)", "Opera", "Presto"), ("SamsungBrowser/([\\d.]+)", "Samsung Internet", "Blink"),
            ("Vivaldi/([\\d.]+)", "Vivaldi", "Blink"), ("Brave/([\\d.]+)", "Brave", "Blink"), ("YaBrowser/([\\d.]+)", "Yandex Browser", "Blink"), ("UCBrowser/([\\d.]+)", "UC Browser", "Blink"),
            ("DuckDuckGo/([\\d.]+)", "DuckDuckGo", "WebKit"), ("Arc/([\\d.]+)", "Arc", "Blink"), ("FxiOS/([\\d.]+)", "Firefox for iOS", "WebKit"), ("CriOS/([\\d.]+)", "Chrome for iOS", "WebKit"),
            ("EdgiOS/([\\d.]+)", "Edge for iOS", "WebKit"), ("Firefox/([\\d.]+)", "Firefox", "Gecko"), ("Chromium/([\\d.]+)", "Chromium", "Blink"), ("HeadlessChrome/([\\d.]+)", "Headless Chrome", "Blink"),
            ("Chrome/([\\d.]+)", "Chrome", "Blink"), ("Version/([\\d.]+).*Safari", "Safari", "WebKit"), ("MSIE ([\\d.]+)", "Internet Explorer", "Trident"), ("Trident/.*rv:([\\d.]+)", "Internet Explorer", "Trident"),
            ("Electron/([\\d.]+)", "Electron", "Blink"), ("Safari/([\\d.]+)", "Safari (WebView)", "WebKit"),
        ]
        for (pattern, name, engine) in browsers {
            if let v = cap(s, pattern) { r.browser = name; r.browserVersion = v; r.engine = engine; break }
        }
        if r.browser == "Unknown", let m = cap(s, "^([A-Za-z][A-Za-z0-9._-]*)/([\\d.]+)") { r.browser = m; r.browserVersion = cap(s, "^[A-Za-z][A-Za-z0-9._-]*/([\\d.]+)") ?? "" }
        if let v = cap(s, "AppleWebKit/([\\d.]+)") { r.engineVersion = v; if r.engine == "Unknown" { r.engine = "WebKit" } }
        if let v = cap(s, "Gecko/([\\d.]+)"), r.engine == "Gecko" { r.engineVersion = cap(s, "rv:([\\d.]+)") ?? v }
        if r.engine == "Blink" { r.engineVersion = cap(s, "Chrome/([\\d.]+)") ?? r.engineVersion }
        if r.engine == "Trident" { r.engineVersion = cap(s, "Trident/([\\d.]+)") ?? "" }
        if r.engine == "WebKit", r.device == "Phone" || r.device == "Tablet", r.os.hasPrefix("i") { r.engine = "WebKit" }
        return r
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmed().isEmpty }
        if lines.count > 1 {
            let out = lines.map { l in
                let r = Self.parse(l)
                return "\(r.browser) \(r.browserVersion) · \(r.os) \(r.osVersion) · \(r.device)\(r.isBot ? " · BOT \(r.botName)" : "")"
            }.joined(separator: "\n")
            return ToolOutput(text: out)
        }
        let r = Self.parse(text)
        var rows = [
            MetaRow("Browser", "\(r.browser) \(r.browserVersion)".trimmed()),
            MetaRow("Engine", "\(r.engine) \(r.engineVersion)".trimmed()),
            MetaRow("OS", "\(r.os) \(r.osVersion)".trimmed()),
            MetaRow("Device", r.device + (r.deviceModel.isEmpty ? "" : " · \(r.deviceModel)") + (r.vendor.isEmpty ? "" : " (\(r.vendor))")),
        ]
        if !r.cpu.isEmpty { rows.append(MetaRow("CPU", r.cpu)) }
        rows.append(MetaRow("Bot", r.isBot ? "Yes — \(r.botName)" : "No", style: r.isBot ? .warning : .plain))
        let json = JSONSerializer.string(.object([
            (key: "browser", value: .object([(key: "name", value: .string(r.browser)), (key: "version", value: .string(r.browserVersion))])),
            (key: "engine", value: .object([(key: "name", value: .string(r.engine)), (key: "version", value: .string(r.engineVersion))])),
            (key: "os", value: .object([(key: "name", value: .string(r.os)), (key: "version", value: .string(r.osVersion))])),
            (key: "device", value: .object([(key: "type", value: .string(r.device)), (key: "model", value: .string(r.deviceModel)), (key: "vendor", value: .string(r.vendor))])),
            (key: "cpu", value: .string(r.cpu)), (key: "bot", value: .bool(r.isBot)), (key: "botName", value: .string(r.botName)),
        ]))
        return ToolOutput(text: json, language: .json, metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        s.hasPrefix("Mozilla/") || s.range(of: "^(curl|Wget|python-requests|PostmanRuntime|okhttp|Dalvik)/", options: .regularExpression) != nil ? DetectionScore(0.95, "User-Agent string") : nil
    }
}
