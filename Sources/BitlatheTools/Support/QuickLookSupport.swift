import Foundation
import BitlatheCore

/// Small public surface used by the Quick Look extension (YAMLBridge itself is module-internal).
public enum QuickLookSupport {
    /// Re-serialises every document of a YAML stream with normalised indentation, separated by `---`.
    public static func prettyYAML(_ text: String) throws -> String {
        let docs = try YAMLBridge.parse(text)
        let out = try docs.map { try YAMLBridge.serialize($0, indent: 2, width: 0) }
        return docs.count > 1 ? out.map { "---\n" + $0 }.joined(separator: "\n") : out.joined()
    }
}
