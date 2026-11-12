import Foundation
import JavaScriptCore

/// Hosts bundled JavaScript libraries (prettier, sql-formatter, …) inside JavaScriptCore.
/// One warmed context per bundle set, created lazily on first use. No network, no Node.
public actor JSRuntime {
    public static let shared = JSRuntime()

    public struct Bundle: Hashable, Sendable {
        public let name: String
        public let scripts: [URL]
        public init(name: String, scripts: [URL]) {
            self.name = name
            self.scripts = scripts
        }
    }

    private var contexts: [String: JSContext] = [:]
    private var loadedScripts: [String: Set<URL>] = [:]

    public init() {}

    private func context(for bundle: Bundle) throws -> JSContext {
        if let ctx = contexts[bundle.name], loadedScripts[bundle.name]?.isSuperset(of: bundle.scripts) == true { return ctx }
        let ctx = contexts[bundle.name] ?? {
            let c = JSContext()!   // swiftlint:disable:this force_unwrapping
            c.name = "Bitlathe." + bundle.name
            c.evaluateScript("var window = globalThis; var self = globalThis; var console = { log: function(){}, warn: function(){}, error: function(){} };")
            return c
        }()
        var loaded = loadedScripts[bundle.name] ?? []
        for url in bundle.scripts where !loaded.contains(url) {
            let src = try String(contentsOf: url, encoding: .utf8)
            ctx.exception = nil
            ctx.evaluateScript(src, withSourceURL: url)
            if let e = ctx.exception {
                throw ToolError("Failed to load \(url.lastPathComponent): \(e.toString() ?? "unknown")")
            }
            loaded.insert(url)
        }
        contexts[bundle.name] = ctx
        loadedScripts[bundle.name] = loaded
        return ctx
    }

    /// Evaluate a script that produces a string synchronously or via a Promise.
    /// The script may assign `__result` or return a value / promise.
    public func evaluate(_ script: String, in bundle: Bundle, arguments: [String: String] = [:]) throws -> String {
        let ctx = try context(for: bundle)
        ctx.exception = nil
        for (k, v) in arguments { ctx.setObject(v, forKeyedSubscript: k as NSString) }
        ctx.evaluateScript("var __result = undefined, __error = undefined, __settled = false;")
        let wrapped = """
        (function(){ try {
            var __v = (function(){ \(script) })();
            if (__v && typeof __v.then === 'function') {
                __v.then(function(r){ __result = r; __settled = true; }, function(e){ __error = (e && (e.message || e.toString())) || String(e); __settled = true; });
            } else { __result = __v; __settled = true; }
        } catch (e) { __error = (e && (e.message || e.toString())) || String(e); __settled = true; } })();
        """
        ctx.evaluateScript(wrapped)
        if let e = ctx.exception { throw ToolError(cleanJSError(e.toString() ?? "JavaScript error")) }
        // Promise jobs drain when control returns to native; poll briefly as a safety net.
        var spins = 0
        while ctx.objectForKeyedSubscript("__settled")?.toBool() == false && spins < 1000 {
            ctx.evaluateScript("0")
            spins += 1
        }
        if let err = ctx.objectForKeyedSubscript("__error"), !err.isUndefined, !err.isNull {
            throw parseJSError(err.toString() ?? "JavaScript error")
        }
        guard let result = ctx.objectForKeyedSubscript("__result"), !result.isUndefined else {
            throw ToolError("No result from JavaScript")
        }
        return result.toString() ?? ""
    }

    private func cleanJSError(_ s: String) -> String {
        s.replacingOccurrences(of: "SyntaxError: ", with: "")
    }

    /// Prettier/Terser errors look like "Unexpected token (3:14)" — extract the location.
    private func parseJSError(_ s: String) -> ToolError {
        let msg = cleanJSError(s)
        if let r = msg.range(of: #"\((\d+):(\d+)\)"#, options: .regularExpression) {
            let nums = msg[r].dropFirst().dropLast().split(separator: ":").compactMap { Int($0) }
            if nums.count == 2 {
                let clean = msg[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                let firstLine = clean.split(separator: "\n").first.map(String.init) ?? clean
                return ToolError(firstLine, line: nums[0], column: nums[1])
            }
        }
        if let r = msg.range(of: #"line (\d+)"#, options: [.regularExpression, .caseInsensitive]) {
            let n = Int(msg[r].split(separator: " ").last ?? "")
            return ToolError(msg.split(separator: "\n").first.map(String.init) ?? msg, line: n)
        }
        return ToolError(msg.split(separator: "\n").first.map(String.init) ?? msg)
    }
}

/// Escapes a Swift string for embedding inside a JS string literal.
public extension String {
    var jsLiteral: String {
        var out = "\""
        for u in unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04X", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }
}
