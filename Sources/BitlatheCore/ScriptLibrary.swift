import Foundation

/// A problem found while loading a script file. Scripts with a fatal problem are not registered.
public struct ScriptLoadIssue: Sendable, Identifiable, Hashable {
    public var id: String { url.path + message }
    public let url: URL
    public let message: String
    public let isFatal: Bool
}

public struct ScriptLoadReport: Sendable {
    public var scripts: [UserScript] = []
    public var issues: [ScriptLoadIssue] = []
    public init() {}
    public func issues(for url: URL) -> [ScriptLoadIssue] { issues.filter { $0.url.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path } }
}

extension ScriptLoader {
    /// Like `load(folder:)`, but reports unreadable files, malformed headers, missing `main` and duplicate ids.
    public static func loadReport(folder: URL) -> ScriptLoadReport {
        var report = ScriptLoadReport()
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return report }
        var seen = Set<String>()
        for url in items.filter({ $0.pathExtension.lowercased() == "js" && !$0.lastPathComponent.hasPrefix(".") })
            .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                report.issues.append(.init(url: url, message: "Couldn't read the file as UTF-8 text.", isFatal: true)); continue
            }
            guard let script = UserScript(url: url, source: source) else { continue }
            if let problem = headerProblem(in: source) {
                report.issues.append(.init(url: url, message: problem, isFatal: false))
            }
            if source.range(of: #"function\s+main\s*\(|\b(?:var|let|const)\s+main\s*=|\bmain\s*=\s*(?:function|\()"#, options: .regularExpression) == nil {
                report.issues.append(.init(url: url, message: "No main(input) function found.", isFatal: true)); continue
            }
            if !seen.insert(script.id).inserted {
                report.issues.append(.init(url: url, message: "Another script already uses the id \(script.id).", isFatal: true)); continue
            }
            report.scripts.append(script)
        }
        return report
    }

    /// Returns a message when the file has a header comment whose JSON can't be parsed.
    static func headerProblem(in source: String) -> String? {
        let parsed = UserScript.parseHeader(source)
        return parsed.found && parsed.meta == nil ? "The header JSON is invalid, so defaults were used for name and icon." : nil
    }
}
