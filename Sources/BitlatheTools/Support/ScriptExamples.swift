import Foundation

/// Bundled script template and example scripts.
public enum ScriptExamples {
    public static var template: String {
        guard let u = Bundle.module.url(forResource: "template.js", withExtension: "txt", subdirectory: "Resources/Scripts"),
              let s = try? String(contentsOf: u, encoding: .utf8) else { return "function main(input) {\n    // input.text = input.text.toUpperCase();\n}\n" }
        return s
    }

    public static var exampleURLs: [URL] {
        (Bundle.module.urls(forResourcesWithExtension: "js", subdirectory: "Resources/Scripts/Examples") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Copies the examples into `folder` (creating it), never overwriting an existing file. Returns the number copied.
    @discardableResult
    public static func install(into folder: URL) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var n = 0
        for src in exampleURLs {
            let dst = folder.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dst.path) { continue }
            try fm.copyItem(at: src, to: dst)
            n += 1
        }
        return n
    }

    /// Writes the template as a new, uniquely named script in `folder` and returns its URL.
    public static func createNewScript(in folder: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder.appendingPathComponent("my-script.js")
        var i = 2
        while fm.fileExists(atPath: url.path) { url = folder.appendingPathComponent("my-script-\(i).js"); i += 1 }
        try template.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
