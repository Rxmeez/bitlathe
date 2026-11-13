import XCTest
@testable import BitlatheTools
import BitlatheCore

final class PerformanceDetectionTests: XCTestCase {
    private func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    func testPerToolDetectTimeOnTypicalAndOneMegabyteInputs() {
        let tools = ToolCatalog.all
        var corpus = tools.flatMap { $0.samples.map(\.input) }.filter { !$0.isEmpty }
        corpus += ["hello world", "1700000000", "https://example.com/a?b=c", "#ff8800", "SELECT * FROM t WHERE id = 1"]
        let big = PerformanceJSONTests.makeFixture(megabytes: 1)
        let plainBig = String(repeating: "The quick brown fox jumps over the lazy dog. 0123456789 abcdef\n", count: 16_000)
        let b64Big = String(repeating: "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo=", count: 30_000)

        var worstTypical = (id: "", ms: 0.0)
        var worstBig = (id: "", ms: 0.0)
        let clock = ContinuousClock()
        for tool in tools where !tool.sideEffects {
            for sample in corpus {
                let t = sample.trimmingCharacters(in: .whitespacesAndNewlines)
                let s = clock.now
                _ = tool.detect(t)
                let e = ms(clock.now - s)
                if e > worstTypical.ms { worstTypical = (tool.id, e) }
            }
            for text in [big, plainBig, b64Big] {
                let sample = String(text.utf8.prefix(DetectionEngine.sampleLimit))!   // swiftlint:disable:this force_unwrapping
                let s = clock.now
                _ = tool.detect(sample)
                let e = ms(clock.now - s)
                if e > worstBig.ms { worstBig = (tool.id, e) }
            }
        }
        print("PERF detect worst single tool, typical corpus (\(corpus.count) inputs x \(tools.count) tools): \(worstTypical.id) \(worstTypical.ms) ms")
        print("PERF detect worst single tool, 64 KB sample of 1 MB inputs: \(worstBig.id) \(worstBig.ms) ms")

        var total = 0.0
        for sample in corpus {
            total += ms(clock.measure { _ = DetectionEngine.detect(sample, tools: tools) })
        }
        let perInput = total / Double(corpus.count)
        print("PERF detect all tools, mean per typical input: \(perInput) ms")
        let bigMS = ms(clock.measure { _ = DetectionEngine.detect(big, tools: tools) })
        print("PERF detect all tools, 1 MB JSON input: \(bigMS) ms")
        XCTAssertLessThan(perInput, 20)
        XCTAssertLessThan(worstTypical.ms, 100)
    }
}
