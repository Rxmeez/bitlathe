import XCTest
import Darwin
@testable import BitlatheTools
import BitlatheCore

final class PerformanceJSONTests: XCTestCase {
    /// Realistic API-ish records (nested objects, arrays, floats, unicode, escapes) totalling about `megabytes` MB.
    static func makeFixture(megabytes: Int) -> String {
        var out = "{\"generated\":\"2026-11-12T10:00:00Z\",\"records\":[\n"
        var i = 0
        let target = megabytes * 1_048_576
        while out.utf8.count < target {
            if i > 0 { out += ",\n" }
            out += "{\"id\":\(i),\"uuid\":\"\(i)-3f2b-4c1d-9a7e-\(i * 31)\",\"name\":\"Customer \(i) \\\"Quoted\\\" \\u00e9\u{00e9}\\n\","
            out += "\"active\":\(i % 3 == 0),\"balance\":\(Double(i) * 1.37 + 0.25),\"score\":null,"
            out += "\"tags\":[\"alpha\",\"beta\",\"gamma-\(i % 17)\"],"
            out += "\"address\":{\"street\":\"\(i) Main St\",\"city\":\"Zürich\",\"geo\":{\"lat\":47.\(i % 1000),\"lon\":8.\(i % 997)}},"
            out += "\"notes\":\"Lorem ipsum dolor sit amet, consectetur adipiscing elit \(i) / path\\\\to\\\\file\"}"
            i += 1
        }
        out += "\n]}"
        return out
    }

    private func peakRSSMB() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_maxrss) / 1_048_576   // bytes on macOS
    }

    private func time<T>(_ label: String, _ body: () throws -> T) rethrows -> (T, Double) {
        let s = ContinuousClock.now
        let r = try body()
        let d = ContinuousClock.now - s
        let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        print("PERF \(label): \(Int(ms)) ms")
        return (r, ms)
    }

    func testTenMegabyteJSONFormatMinifyRoundTrip() throws {
        let text = Self.makeFixture(megabytes: 10)
        print("PERF fixture bytes: \(text.utf8.count)")
        let rssBefore = peakRSSMB()
        let (value, parseMS) = try time("parse 10MB") { try JSONParser.parse(text) }
        let (pretty, prettyMS) = time("pretty-print 10MB") { JSONSerializer.string(value, options: .pretty) }
        let (mini, miniMS) = time("minify 10MB") { JSONSerializer.string(value, options: .minified) }
        print("PERF peak RSS: \(Int(rssBefore)) MB before -> \(Int(peakRSSMB())) MB after (pretty \(pretty.utf8.count) B, mini \(mini.utf8.count) B)")
        // Round trip: minified output reparses to the same value.
        XCTAssertEqual(try JSONParser.parse(mini), value)
        XCTAssertEqual(value["records"]?.count, try JSONParser.parse(pretty)["records"]?.count)
        let isRelease: Bool = {
            #if DEBUG
            false
            #else
            true
            #endif
        }()
        if isRelease {
            XCTAssertLessThan(parseMS + prettyMS, 1500, "format of 10 MB should take < 1.5 s")
            XCTAssertLessThan(parseMS + miniMS, 1500)
        }
    }

    func testFormatToolOutputMatchesSerializerOnEscapes() throws {
        let v = try JSONParser.parse(#"{"a":"x\u2028y\u007f/\"\\\n\t\u0001é😀","b":[1,2.50,true,null,{}],"c":[]}"#)
        var o = JSONSerializerOptions(); o.escapeNonASCII = true; o.escapeSlashes = true
        XCTAssertEqual(JSONSerializer.string(v, options: o),
                       "{\n  \"a\": \"x\\u2028y\\u007f\\/\\\"\\\\\\n\\t\\u0001\\u00e9\\ud83d\\ude00\",\n  \"b\": [\n    1,\n    2.50,\n    true,\n    null,\n    {}\n  ],\n  \"c\": []\n}")
        XCTAssertEqual(JSONSerializer.string(v, options: .minified), "{\"a\":\"x\\u2028y\\u007f/\\\"\\\\\\n\\t\\u0001é😀\",\"b\":[1,2.50,true,null,{}],\"c\":[]}")
    }

    func testCancellingLargeFormatStopsPromptly() async throws {
        let text = Self.makeFixture(megabytes: 10)
        let tool = ToolCatalog.all.first { $0.id == "json.format" }!   // swiftlint:disable:this force_unwrapping
        let task = Task { try await tool.run(text: text) }
        try await Task.sleep(for: .milliseconds(30))
        let s = ContinuousClock.now
        task.cancel()
        let result = await task.result
        let waited = ContinuousClock.now - s
        if case .success = result {
            print("PERF cancel: format finished before cancel landed (fast machine)")
        } else if case .failure(let e) = result {
            XCTAssertTrue(e is CancellationError, "unexpected error \(e)")
        }
        XCTAssertLessThan(waited, .milliseconds(500), "cancel took \(waited)")
        print("PERF cancel latency: \(waited)")
    }
}
