import Foundation
import XCTest
import BitlatheCore
@testable import BitlatheTools

/// Shared helpers for the format / convert / encode test files.
enum T {
    static func run<X: DevTool>(_ tool: X.Type, _ text: String, _ opts: OptionValues = [:]) async throws -> ToolOutput {
        try await AnyTool(tool).run(text: text, options: opts)
    }

    static func text<X: DevTool>(_ tool: X.Type, _ text: String, _ opts: OptionValues = [:]) async throws -> String {
        try await run(tool, text, opts).text
    }

    /// Runs and returns the thrown ToolError (fails the test if nothing is thrown).
    static func error<X: DevTool>(_ tool: X.Type, _ text: String, _ opts: OptionValues = [:],
                                  file: StaticString = #filePath, line: UInt = #line) async -> ToolError? {
        do {
            let out = try await run(tool, text, opts)
            XCTFail("expected an error, got output: \(out.text.prefix(80))", file: file, line: line)
            return nil
        } catch let e as ToolError {
            return e
        } catch {
            XCTFail("expected ToolError, got \(error)", file: file, line: line)
            return nil
        }
    }

    static func fixture(_ path: String) throws -> String {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
}

/// Deterministic pseudo-random bytes (SplitMix64) so tests are repeatable.
func pseudoRandomBytes(_ n: Int, seed: UInt64 = 42) -> Data {
    var s = seed
    var out = [UInt8](); out.reserveCapacity(n)
    while out.count < n {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        for i in 0..<8 where out.count < n { out.append(UInt8(truncatingIfNeeded: z >> (8 * UInt64(i)))) }
    }
    return Data(out)
}

let unicodeSample = "Héllo wörld ✓ 日本語 😀👨‍👩‍👧 \u{1F1EF}\u{1F1F5} 𝔘𝔫𝔦"

/// `XCTAssertEqual` whose first argument may `await` (XCTest autoclosures are synchronous).
func AEq<V: Equatable>(_ actual: @autoclosure () async throws -> V, _ expected: @autoclosure () -> V, _ message: String = "",
                       file: StaticString = #filePath, line: UInt = #line) async throws {
    let a = try await actual()
    XCTAssertEqual(a, expected(), message, file: file, line: line)
}
