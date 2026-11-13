import XCTest
import BitlatheCore
@testable import BitlatheTools

final class CronTests: XCTestCase {
    /// Reference start: Wednesday 2024-01-31 12:00:00 UTC.
    private let start = Date(timeIntervalSince1970: 1_706_702_400)
    private let utc = TimeZone(identifier: "UTC")!

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func next(_ expr: String, _ n: Int = 4, syntax: String = "auto", zone: String = "UTC", after: Date? = nil) throws -> [String] {
        let tz = TimeZone(identifier: zone)!
        iso.timeZone = TimeZone(identifier: "UTC")!
        return try CronExpression.parse(expr, syntax: syntax).next(count: n, after: after ?? start, zone: tz).map { iso.string(from: $0) }
    }

    func testReferenceDateIsWhatWeThink() {
        iso.timeZone = utc
        XCTAssertEqual(iso.string(from: start), "2024-01-31T12:00:00Z")
    }

    // MARK: standard

    func testEveryFifteenMinutes() throws {
        XCTAssertEqual(try next("*/15 * * * *"), ["2024-01-31T12:15:00Z", "2024-01-31T12:30:00Z", "2024-01-31T12:45:00Z", "2024-01-31T13:00:00Z"])
    }

    func testWeekdaysAtNineThirty() throws {
        XCTAssertEqual(try next("30 9 * * 1-5", 3), ["2024-02-01T09:30:00Z", "2024-02-02T09:30:00Z", "2024-02-05T09:30:00Z"])
    }

    func testMonthlyAndMacros() throws {
        XCTAssertEqual(try next("0 0 1 * *", 3), ["2024-02-01T00:00:00Z", "2024-03-01T00:00:00Z", "2024-04-01T00:00:00Z"])
        XCTAssertEqual(try next("@monthly", 2), ["2024-02-01T00:00:00Z", "2024-03-01T00:00:00Z"])
        XCTAssertEqual(try next("@daily", 2), ["2024-02-01T00:00:00Z", "2024-02-02T00:00:00Z"])
        XCTAssertEqual(try next("@hourly", 2), ["2024-01-31T13:00:00Z", "2024-01-31T14:00:00Z"])
        XCTAssertEqual(try next("@weekly", 1), ["2024-02-04T00:00:00Z"])
        XCTAssertEqual(try next("@yearly", 1), ["2025-01-01T00:00:00Z"])
    }

    func testLeapDayAndNames() throws {
        XCTAssertEqual(try next("0 0 29 2 *", 2), ["2024-02-29T00:00:00Z", "2028-02-29T00:00:00Z"])
        XCTAssertEqual(try next("0 0 * * SUN", 2), ["2024-02-04T00:00:00Z", "2024-02-11T00:00:00Z"])
        XCTAssertEqual(try next("0 0 1 JAN,MAR *", 2), ["2024-03-01T00:00:00Z", "2025-01-01T00:00:00Z"])
    }

    func testStandardDayOfMonthOrDayOfWeekSemantics() throws {
        // Vixie cron: when both day fields are restricted, a day matching EITHER runs.
        XCTAssertEqual(try next("0 0 13 * 5", 4), ["2024-02-02T00:00:00Z", "2024-02-09T00:00:00Z", "2024-02-13T00:00:00Z", "2024-02-16T00:00:00Z"])
    }

    func testStartIsExclusive() throws {
        XCTAssertEqual(try next("0 12 * * *", 1), ["2024-02-01T12:00:00Z"])
    }

    func testListsRangesAndSteps() throws {
        XCTAssertEqual(try next("0,30 8-9 * * *", 4), ["2024-02-01T08:00:00Z", "2024-02-01T08:30:00Z", "2024-02-01T09:00:00Z", "2024-02-01T09:30:00Z"])
        XCTAssertEqual(try next("10-20/5 * * * *", 4), ["2024-01-31T12:10:00Z", "2024-01-31T12:15:00Z", "2024-01-31T12:20:00Z", "2024-01-31T13:10:00Z"])
    }

    func testTimeZoneAcrossDST() throws {
        // New York switched to DST on 2024-03-10: 09:00 local is 14:00Z before and 13:00Z after.
        let from = Date(timeIntervalSince1970: 1_710_000_000)   // 2024-03-09T16:00:00Z
        XCTAssertEqual(try next("0 9 * * *", 3, zone: "America/New_York", after: from),
                       ["2024-03-10T13:00:00Z", "2024-03-11T13:00:00Z", "2024-03-12T13:00:00Z"])
        XCTAssertEqual(try next("0 9 * * *", 2, zone: "America/New_York"), ["2024-01-31T14:00:00Z", "2024-02-01T14:00:00Z"])   // 12:00Z is 07:00 EST, so 09:00 EST is still today
    }

    // MARK: Quartz

    func testQuartzSeconds() throws {
        XCTAssertEqual(try next("*/20 * * * * ?", 3), ["2024-01-31T12:00:20Z", "2024-01-31T12:00:40Z", "2024-01-31T12:01:00Z"])
    }

    func testQuartzLastDayOfMonth() throws {
        XCTAssertEqual(try next("0 15 10 L * ?", 3), ["2024-02-29T10:15:00Z", "2024-03-31T10:15:00Z", "2024-04-30T10:15:00Z"])
    }

    func testQuartzNearestWeekday() throws {
        XCTAssertEqual(try next("0 0 12 15W * ?", 4), ["2024-02-15T12:00:00Z", "2024-03-15T12:00:00Z", "2024-04-15T12:00:00Z", "2024-05-15T12:00:00Z"])
        // 15 June 2024 is a Saturday -> Friday the 14th.
        XCTAssertEqual(try next("0 0 12 15W 6 ?", 1), ["2024-06-14T12:00:00Z"])
        // 1 June 2024 is a Saturday; the nearest weekday must stay inside the month -> Monday the 3rd.
        XCTAssertEqual(try next("0 0 0 1W 6 ?", 1), ["2024-06-03T00:00:00Z"])
        // 16 Feb 2025 is a Sunday -> Monday the 17th.
        XCTAssertEqual(try next("0 0 12 16W 2 ?", 1, after: Date(timeIntervalSince1970: 1_733_011_200)), ["2025-02-17T12:00:00Z"])
    }

    func testQuartzLastWeekdayOfMonth() throws {
        XCTAssertEqual(try next("0 0 12 LW * ?", 3), ["2024-02-29T12:00:00Z", "2024-03-29T12:00:00Z", "2024-04-30T12:00:00Z"])
    }

    func testQuartzNthWeekday() throws {
        // Quartz numbers weekdays 1=SUN … 7=SAT, so 6 is Friday. Third Fridays of Feb/Mar/Apr 2024.
        XCTAssertEqual(try next("0 0 12 ? * 6#3", 3), ["2024-02-16T12:00:00Z", "2024-03-15T12:00:00Z", "2024-04-19T12:00:00Z"])
        XCTAssertEqual(try next("0 0 12 ? * FRI#3", 3), ["2024-02-16T12:00:00Z", "2024-03-15T12:00:00Z", "2024-04-19T12:00:00Z"])
    }

    func testQuartzLastNamedWeekday() throws {
        // 2L = last Monday.
        XCTAssertEqual(try next("0 0 12 ? * 2L", 3), ["2024-02-26T12:00:00Z", "2024-03-25T12:00:00Z", "2024-04-29T12:00:00Z"])
    }

    func testQuartzQuestionMarkRules() {
        XCTAssertThrowsError(try CronExpression.parse("0 0 12 1 * 2", syntax: "quartz"))
        XCTAssertNoThrow(try CronExpression.parse("0 0 12 ? * 2", syntax: "quartz"))
    }

    func testQuartzWithYear() throws {
        XCTAssertEqual(try next("0 0 0 1 1 ? 2026", 2), ["2026-01-01T00:00:00Z"])
    }

    // MARK: EventBridge

    func testEventBridgeWeekdays() throws {
        XCTAssertEqual(try next("0 12 ? * MON-FRI *", 3), ["2024-02-01T12:00:00Z", "2024-02-02T12:00:00Z", "2024-02-05T12:00:00Z"])
        XCTAssertEqual(try next("cron(0 12 ? * MON-FRI *)", 1), ["2024-02-01T12:00:00Z"])
    }

    func testEventBridgeLastFriday() throws {
        XCTAssertEqual(try next("15 10 ? * 6L *", 3, syntax: "eventbridge"), ["2024-02-23T10:15:00Z", "2024-03-29T10:15:00Z", "2024-04-26T10:15:00Z"])
    }

    func testEventBridgeNeedsSixFields() {
        XCTAssertThrowsError(try CronExpression.parse("0 12 ? * MON-FRI", syntax: "eventbridge"))
    }

    // MARK: errors, tool

    func testInvalidExpressions() {
        for bad in ["61 * * * *", "* * * *", "* 24 * * *", "* * 32 * *", "* * * 13 *", "*/0 * * * *", "5-1 * * * *", "@reboot", "hello world"] {
            XCTAssertThrowsError(try CronExpression.parse(bad), bad)
        }
    }

    func testToolDescriptionAndCount() async throws {
        let out = try await TT.run("cron.parse", "30 9 * * 1-5", ["count": .int(3), "timeZone": .string("UTC")])
        let text = out.metadata.map { $0.label + " " + $0.value }.joined(separator: "\n") + out.text
        XCTAssertTrue(text.contains("09:30") || text.contains("9:30"), text)
        XCTAssertTrue(text.lowercased().contains("monday") || text.lowercased().contains("weekday"), text)
        do { _ = try await TT.run("cron.parse", "61 * * * *"); XCTFail("expected error") } catch { XCTAssertTrue(error is ToolError) }
    }

    func testDetect() {
        XCTAssertNotNil(CronTool.detect("*/5 * * * *"))
        XCTAssertNotNil(CronTool.detect("0 0/5 14,18 * * ?"))
        XCTAssertNil(CronTool.detect("hello world foo bar baz"))
    }
}
