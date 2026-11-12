import Foundation
import JavaScriptCore

/// A user script: a JavaScript file with a `@bitlathe` header, run in a fresh sandboxed JSContext.
public struct UserScript: Sendable, Identifiable, Hashable {
    public var id: String { "script." + slug }
    public let slug: String
    public let name: String
    public let summary: String
    public let symbol: String
    public let keywords: [String]
    public let detectPattern: String?
    public let url: URL
    public let source: String

    public static let headerPattern = #"/\*\*\s*@bitlathe\s*(\{[\s\S]*?\})\s*\*/"#
    public static let boopHeaderPattern = #"/\*\*\s*(\{[\s\S]*?\})\s*\*\*/"#

    public init?(url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.init(url: url, source: source)
    }

    public init?(url: URL, source: String) {
        self.url = url
        self.source = source
        var meta: [String: Any] = [:]
        for pattern in [Self.headerPattern, Self.boopHeaderPattern] {
            if let r = source.range(of: pattern, options: .regularExpression),
               let inner = source[r].range(of: #"\{[\s\S]*\}"#, options: .regularExpression),
               let obj = try? JSONSerialization.jsonObject(with: Data(source[inner].utf8), options: [.fragmentsAllowed, .json5Allowed]) as? [String: Any] {
                meta = obj
                break
            }
        }
        let base = url.deletingPathExtension().lastPathComponent
        name = meta["name"] as? String ?? base
        summary = meta["description"] as? String ?? "User script"
        symbol = meta["icon"] as? String ?? "scroll"
        let tags = (meta["tags"] as? String)?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        keywords = (meta["keywords"] as? [String] ?? tags) + ["script"]
        detectPattern = meta["detect"] as? String
        slug = base.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    }

    public func detect(_ sample: String) -> DetectionScore? {
        guard let p = detectPattern, sample.utf8.count < 4096, sample.range(of: p, options: .regularExpression) != nil else { return nil }
        return DetectionScore(0.6, "Matches script pattern")
    }

    public static let runTimeout: TimeInterval = 2.0

    /// Runs the script on a dedicated thread with a watchdog. The script defines `function main(input)`;
    /// `input.text` is read and written. Scripts that exceed `runTimeout` are reported as errors.
    public func run(_ input: ToolInput) throws -> ToolOutput {
        final class Box: @unchecked Sendable { var result: Result<ToolOutput, any Error>? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let script = self
        let thread = Thread {
            box.result = Result { try script.runUnbounded(input) }
            done.signal()
        }
        thread.name = "Bitlathe.script.\(slug)"
        thread.stackSize = 8 * 1024 * 1024
        thread.start()
        guard done.wait(timeout: .now() + Self.runTimeout) == .success, let result = box.result else {
            throw ToolError("Script timed out after \(Int(Self.runTimeout)) s", hint: "Scripts must finish within \(Int(Self.runTimeout)) seconds. Check for infinite loops.")
        }
        return try result.get()
    }

    private func runUnbounded(_ input: ToolInput) throws -> ToolOutput {
        guard let ctx = JSContext() else { throw ToolError("Could not create JavaScript context") }
        ctx.name = "Bitlathe.script.\(slug)"

        final class Messages: @unchecked Sendable { var info: [String] = []; var errors: [String] = [] }
        let messages = Messages()
        let postInfo: @convention(block) (String) -> Void = { messages.info.append($0) }
        let postError: @convention(block) (String) -> Void = { messages.errors.append($0) }
        let insert: @convention(block) (String) -> Void = { _ in }
        ctx.setObject(postInfo, forKeyedSubscript: "__postInfo" as NSString)
        ctx.setObject(postError, forKeyedSubscript: "__postError" as NSString)
        ctx.setObject(insert, forKeyedSubscript: "__insert" as NSString)

        let full = input.text
        let selectionText: String
        if let sel = input.selection, let r = Range(NSRange(location: sel.lowerBound, length: sel.count), in: full) {
            selectionText = String(full[r])
        } else {
            selectionText = ""
        }
        ctx.setObject(selectionText.isEmpty ? full : selectionText, forKeyedSubscript: "__text" as NSString)
        ctx.setObject(full, forKeyedSubscript: "__fullText" as NSString)
        ctx.setObject(selectionText, forKeyedSubscript: "__selection" as NSString)

        ctx.evaluateScript("""
        var console = { log: function(m){ __postInfo(String(m)); }, error: function(m){ __postError(String(m)); } };
        var input = {
            text: __text, fullText: __fullText, selection: __selection, isSelection: __selection.length > 0,
            postInfo: function(m){ __postInfo(String(m)); },
            postError: function(m){ __postError(String(m)); },
            insert: function(s){ this.text = String(s); }
        };
        var state = input;
        """)
        ctx.exception = nil
        ctx.evaluateScript(source, withSourceURL: url)
        if let e = ctx.exception { throw scriptError(e) }
        guard let main = ctx.objectForKeyedSubscript("main"), main.isObject else {
            throw ToolError("Script has no main(input) function", hint: "Define `function main(input) { input.text = … }`")
        }
        ctx.exception = nil
        main.call(withArguments: [ctx.objectForKeyedSubscript("input") as Any])
        if let e = ctx.exception { throw scriptError(e) }
        let result = ctx.objectForKeyedSubscript("input")?.objectForKeyedSubscript("text")?.toString() ?? ""
        if let err = messages.errors.first { throw ToolError(err) }
        var out = ToolOutput(text: result)
        out.warnings = messages.info
        return out
    }

    private func scriptError(_ e: JSValue) -> ToolError {
        let msg = e.toString() ?? "Script error"
        let line = e.objectForKeyedSubscript("line")?.toInt32()
        let col = e.objectForKeyedSubscript("column")?.toInt32()
        return ToolError(msg, line: line.map(Int.init), column: col.map(Int.init))
    }

    public var asTool: AnyTool {
        let script = self
        return AnyTool(id: id, name: name, summary: summary, category: .scripting, symbol: symbol, keywords: keywords,
                       kind: .script, detect: { script.detect($0) }) { input, _ in
            try script.run(input)
        }
    }
}

public enum ScriptLoader {
    public static func load(folder: URL) -> [UserScript] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension == "js" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { UserScript(url: $0) }
    }

    public static var defaultFolder: URL {
        StorePaths.appSupport.appendingPathComponent("Scripts", isDirectory: true)
    }
}
