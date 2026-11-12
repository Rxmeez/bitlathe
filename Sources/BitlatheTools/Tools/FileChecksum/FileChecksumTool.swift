import Foundation
import CryptoKit
import BitlatheCore

public struct FileChecksumTool: DevTool {
    public static let id = "file.checksum"
    public static let name = "File Checksum"
    public static let summary = "Drop a file to get MD5, SHA-1, SHA-256, SHA-512, CRC32 and compare against an expected hash"
    public static let category = ToolCategory.inspect
    public static let symbol = "doc.badge.ellipsis"
    public static let keywords = ["checksum", "sha256", "md5", "sha1", "sha512", "crc32", "verify", "integrity", "file", "hash", "download"]
    public static let io = ToolIO(input: .file, output: .text, acceptsFiles: true)
    public static let optionFields: [OptionField] = [
        .text("expected", "Expected", placeholder: "paste a hash to compare", help: "Any of the algorithms; matched case-insensitively"),
        .toggle("uppercase", "Uppercase"),
    ]
    public struct Options: ToolOptions {
        public var expected = ""
        public var uppercase = false
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        var md5 = Insecure.MD5(), sha1 = Insecure.SHA1(), sha256 = SHA256(), sha512 = SHA512(), sha384 = SHA384()
        var crc: UInt32 = 0
        var size = 0
        var blake3Buffer = Data()
        func feed(_ chunk: Data) {
            md5.update(data: chunk); sha1.update(data: chunk); sha256.update(data: chunk); sha512.update(data: chunk); sha384.update(data: chunk)
            crc = chunk.withUnsafeBytes { UInt32(zlib.crc32(uLong(crc), $0.bindMemory(to: Bytef.self).baseAddress, uInt(chunk.count))) }
            size += chunk.count
            if blake3Buffer.count < 64 * 1024 * 1024 { blake3Buffer.append(chunk) }
        }
        switch input.payload {
        case .file(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let handle = try? FileHandle(forReadingFrom: url) else { throw ToolError("Cannot read \(url.lastPathComponent)") }
            defer { try? handle.close() }
            while true {
                let chunk = handle.readData(ofLength: 4 * 1024 * 1024)
                if chunk.isEmpty { break }
                feed(chunk)
                try Task.checkpoint()
            }
        case .none:
            throw ToolError("Drop a file or paste text", hint: "Use Open… or drag a file into the window")
        default:
            feed(input.data)
        }
        func hex(_ d: Data) -> String { options.uppercase ? d.hexString.uppercased() : d.hexString }
        let results: [(String, String)] = [
            ("MD5", hex(Data(md5.finalize()))), ("SHA-1", hex(Data(sha1.finalize()))), ("SHA-256", hex(Data(sha256.finalize()))), ("SHA-384", hex(Data(sha384.finalize()))),
            ("SHA-512", hex(Data(sha512.finalize()))), ("CRC32", String(format: options.uppercase ? "%08X" : "%08x", crc)),
            ("BLAKE3", blake3Buffer.count == size ? hex(Blake3.hash(blake3Buffer)) : "(file > 64 MB; skipped)"),
        ]
        var rows: [MetaRow] = [MetaRow("Size", "\(ByteFormatter.string(size)) (\(size) bytes)")]
        if let name = input.fileName { rows.insert(MetaRow("File", name), at: 0) }
        var matched: String?
        let expected = options.expected.trimmed().lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ":", with: "")
        for (name, value) in results {
            var style: MetaRow.Style = .mono
            if !expected.isEmpty, value.lowercased() == expected { style = .success; matched = name }
            rows.append(MetaRow(name, value, style: style))
        }
        if !expected.isEmpty {
            rows.insert(MetaRow("Verification", matched.map { "✓ Matches \($0)" } ?? "✗ No algorithm matches the expected hash", style: matched == nil ? .danger : .success), at: 0)
        }
        let text = results.map { "\($0.0.padding(toLength: 8, withPad: " ", startingAt: 0)) \($0.1)" }.joined(separator: "\n")
        let facets = results.map { OutputFacet($0.0, text: $0.1) } + [OutputFacet("shasum format", text: "\(results[2].1)  \(input.fileName ?? "-")")]
        return ToolOutput(text: text, facets: facets, metadata: rows, isValid: expected.isEmpty ? nil : matched != nil)
    }
}

import zlib
