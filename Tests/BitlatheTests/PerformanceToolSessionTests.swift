import XCTest
@testable import BitlatheUI
import BitlatheCore

@MainActor
final class PerformanceToolSessionTests: XCTestCase {
    /// A tool that cooperatively loops until cancelled (or `seconds` elapse), recording whether it saw the cancel.
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var _sawCancel = false
        var sawCancel: Bool { lock.lock(); defer { lock.unlock() }; return _sawCancel }
        func markCancelled() { lock.lock(); _sawCancel = true; lock.unlock() }
    }

    private func slowTool(seconds: Double, probe: Probe) -> AnyTool {
        AnyTool(id: "test.slow", name: "Slow", summary: "", category: .format, symbol: "clock", kind: .script) { _, _ in
            let end = ContinuousClock.now + .seconds(seconds)
            while ContinuousClock.now < end {
                if Task.isCancelled { probe.markCancelled(); throw CancellationError() }
                do { try await Task.sleep(for: .milliseconds(5)) } catch { probe.markCancelled(); throw error }
            }
            return ToolOutput(text: "done")
        }
    }

    func testIndicatorAppearsOnlyAfterDelayAndCancelStopsEngine() async throws {
        let probe = Probe()
        let session = ToolSession(tool: slowTool(seconds: 5, probe: probe), input: "x")   // starts the run immediately; no debounce timer
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(session.isRunning, "indicator must not show before ~150 ms")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(session.isRunning, "indicator should show after ~150 ms")
        session.cancel()
        XCTAssertFalse(session.isRunning)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(probe.sawCancel, "engine must observe cancellation")
        XCTAssertFalse(session.isRunning)
        XCTAssertNil(session.output)
    }

    func testFastRunNeverShowsIndicator() async throws {
        let probe = Probe()
        let session = ToolSession(tool: slowTool(seconds: 0.03, probe: probe), input: "x")
        var everRunning = false
        for _ in 0..<40 {
            if session.isRunning { everRunning = true }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(everRunning)
        XCTAssertEqual(session.output?.text, "done")
    }

    func testCancelledNonCooperativeRunNeverReshowsIndicator() async throws {
        // Engine ignores cancellation for 400 ms; cancelling at 50 ms must not let the 150 ms timer flip the indicator on.
        let tool = AnyTool(id: "test.stubborn", name: "Stubborn", summary: "", category: .format, symbol: "clock", kind: .script) { _, _ in
            let end = ContinuousClock.now + .milliseconds(400)
            while ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(5)) }
            return ToolOutput(text: "late")
        }
        let session = ToolSession(tool: tool, input: "x")
        try await Task.sleep(for: .milliseconds(50))
        session.cancel()
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertFalse(session.isRunning)
        XCTAssertNil(session.output, "a cancelled run's late result must be dropped")
    }
}
