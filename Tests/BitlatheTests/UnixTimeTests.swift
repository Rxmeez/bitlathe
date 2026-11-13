import XCTest
import BitlatheCore
@testable import BitlatheTools

final class UnixTimeTests: XCTestCase {
    /// 2023-11-14T22:13:20Z
    private let ref = 1_700_000_000.0

    private func seconds(_ s: String, unit: String = "auto") -> Double? {
        UnixTimeTool.parse(s, unit: unit)?.date.timeIntervalSince1970
    }

    func testUnitAutoDetection() {
        let cases: [(String, String)] = [
            ("1700000000", "Unix seconds"), ("1700000000000", "Unix milliseconds"),
            ("1700000000000000", "Unix microseconds"), ("1700000000000000000", "Unix nanoseconds"),
            ("1700000000.5", "Unix seconds"), ("0", "Unix seconds"), ("-86400", "Unix seconds"),
        ]
        for (input, source) in cases { XCTAssertEqual(UnixTimeTool.parse(input)?.source, source, input) }
        XCTAssertEqual(seconds("1700000000"), ref)
        XCTAssertEqual(seconds("1700000000000"), ref)
        XCTAssertEqual(seconds("1700000000000000"), ref)
        XCTAssertEqual(seconds("1700000000000000000"), ref)
        XCTAssertEqual(seconds("1700000000.5") ?? 0, ref + 0.5, accuracy: 1e-6)
        XCTAssertEqual(seconds("-86400"), -86_400)
        XCTAssertEqual(seconds("1,700,000,000"), ref, "thousands separators are accepted")
        XCTAssertEqual(seconds("1_700_000_000"), ref)
    }

    func testBoundaryBetweenSecondsAndMilliseconds() {
        // 99,999,999,999 s is the year 5138; 100,000,000,000 is treated as milliseconds (1973).
        XCTAssertEqual(UnixTimeTool.parse("99999999999")?.source, "Unix seconds")
        XCTAssertEqual(UnixTimeTool.parse("100000000000")?.source, "Unix milliseconds")
        XCTAssertEqual(seconds("100000000000"), 100_000_000)
    }

    func testExplicitUnitOverridesDetection() {
        XCTAssertEqual(seconds("1700000000", unit: "ms"), 1_700_000)
        XCTAssertEqual(seconds("1700000000", unit: "us"), 1_700)
        XCTAssertEqual(seconds("1700000000", unit: "ns") ?? 0, 1.7, accuracy: 1e-6)   // Date stores offsets from 2001 as Double
        XCTAssertEqual(seconds("1700000000000", unit: "s"), 1_700_000_000_000)
    }

    func testISO8601Parsing() {
        XCTAssertEqual(seconds("2023-11-14T22:13:20Z"), ref)
        XCTAssertEqual(seconds("2023-11-14T22:13:20.500Z") ?? 0, ref + 0.5, accuracy: 1e-6)
        XCTAssertEqual(seconds("2023-11-14T23:13:20+01:00"), ref)
        XCTAssertEqual(seconds("2023-11-14T17:13:20-05:00"), ref)
        XCTAssertEqual(seconds("2023-11-15T03:43:20+05:30"), ref)
        XCTAssertEqual(UnixTimeTool.parse("2023-11-14T22:13:20Z")?.source, "ISO 8601")
        XCTAssertEqual(seconds("2023-11-14"), 1_699_920_000, "date-only strings are read as UTC midnight")
    }

    func testRFC2822Parsing() {
        XCTAssertEqual(seconds("Tue, 14 Nov 2023 22:13:20 +0000"), ref)
        XCTAssertEqual(seconds("Tue, 14 Nov 2023 23:13:20 +0100"), ref)
        XCTAssertEqual(UnixTimeTool.parse("Tue, 14 Nov 2023 22:13:20 +0000")?.source, "RFC 2822")
    }

    func testNowAndGarbage() {
        XCTAssertEqual(seconds("now") ?? 0, Date().timeIntervalSince1970, accuracy: 2)
        XCTAssertNil(UnixTimeTool.parse(""))
        XCTAssertNil(UnixTimeTool.parse("banana"))
    }

    func testRowsForKnownInstant() async throws {
        let out = try await TT.run("time.unix", "1700000000", ["timeZone": .string("UTC")])
        XCTAssertEqual(TT.meta(out, "Interpreted as"), "Unix seconds")
        XCTAssertEqual(TT.meta(out, "ISO 8601 (UTC)"), "2023-11-14T22:13:20.000Z")
        XCTAssertEqual(TT.meta(out, "RFC 2822"), "Tue, 14 Nov 2023 22:13:20 +0000")
        XCTAssertEqual(TT.meta(out, "Unix seconds"), "1700000000")
        XCTAssertEqual(TT.meta(out, "Unix milliseconds"), "1700000000000")
        XCTAssertEqual(TT.meta(out, "Unix microseconds"), "1700000000000000")
        XCTAssertEqual(TT.meta(out, "Unix nanoseconds"), "1700000000000000000")
        XCTAssertEqual(TT.meta(out, "UTC offset"), "UTC+00:00")
        XCTAssertTrue(TT.meta(out, "Day")?.hasPrefix("Tuesday, day 318 of the year, ISO week 46 of 2023") == true, TT.meta(out, "Day") ?? "")
        XCTAssertEqual(TT.meta(out, "Excel serial"), "45244.925926")
        XCTAssertEqual(TT.meta(out, "Julian day"), "2460263.42593")
        XCTAssertEqual(TT.meta(out, "Mac absolute time"), "721692800.000")
        XCTAssertEqual(TT.facet(out, "ISO 8601"), "2023-11-14T22:13:20Z")
        XCTAssertEqual(TT.facet(out, "Unix seconds"), "1700000000")
    }

    func testTimeZonesAndCities() async throws {
        let ny = try await TT.run("time.unix", "1700000000", ["timeZone": .string("America/New_York")])
        XCTAssertEqual(TT.meta(ny, "ISO 8601 (local)"), "2023-11-14T17:13:20.000-05:00")
        XCTAssertEqual(TT.meta(ny, "UTC offset"), "UTC-05:00")
        let summer = try await TT.run("time.unix", "1720000000", ["timeZone": .string("Europe/Berlin")])   // 2024-07-03T09:46:40Z
        XCTAssertEqual(TT.meta(summer, "UTC offset"), "UTC+02:00 (DST)")
        let kolkata = try await TT.run("time.unix", "1700000000", ["timeZone": .string("Asia/Kolkata")])
        XCTAssertEqual(TT.meta(kolkata, "UTC offset"), "UTC+05:30")
        XCTAssertNotNil(TT.meta(kolkata, "🌍 Tokyo"))
        XCTAssertTrue(TT.meta(kolkata, "🌍 Tokyo")?.hasSuffix("UTC+09:00") == true)
        do { _ = try await TT.run("time.unix", "1700000000", ["timeZone": .string("Mars/Olympus")]); XCTFail("expected error") } catch { XCTAssertTrue(error is ToolError) }
    }

    func testBatchMode() async throws {
        let out = try await TT.run("time.unix", "1700000000\n1700000000000\nnope", ["timeZone": .string("UTC")])
        let lines = out.text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("2023-11-14T22:13:20Z")); XCTAssertTrue(lines[1].contains("2023-11-14T22:13:20Z"))
        XCTAssertTrue(lines[2].hasSuffix("?"))
    }

    func testRelativeAndOffsetHelpers() {
        let now = Date()
        XCTAssertEqual(UnixTimeTool.relative(now.addingTimeInterval(1), to: now), "just now")
        XCTAssertTrue(UnixTimeTool.relative(now.addingTimeInterval(-7200), to: now).contains("2 hours ago"))
        XCTAssertTrue(UnixTimeTool.relative(now.addingTimeInterval(86_400 * 3), to: now).contains("in 3 days"))
        XCTAssertEqual(UnixTimeTool.offset(TimeZone(identifier: "Asia/Kathmandu")!, Date(timeIntervalSince1970: ref)), "UTC+05:45")
    }

    func testDetect() {
        XCTAssertEqual(UnixTimeTool.detect("1700000000")?.reason, "Unix timestamp (seconds)")
        XCTAssertEqual(UnixTimeTool.detect("1700000000000")?.reason, "Unix timestamp (milliseconds)")
        XCTAssertEqual(UnixTimeTool.detect("1700000000000000")?.reason, "Unix timestamp (microseconds)")
        XCTAssertEqual(UnixTimeTool.detect("1700000000000000000")?.reason, "Unix timestamp (nanoseconds)")
        XCTAssertNotNil(UnixTimeTool.detect("2023-11-14T22:13:20Z"))
        XCTAssertNotNil(UnixTimeTool.detect("Tue, 14 Nov 2023 22:13:20 +0000"))
        XCTAssertNil(UnixTimeTool.detect("12345"))
    }
}
