import XCTest
import BitlatheCore
@testable import BitlatheTools

final class IDGeneratorTests: XCTestCase {
    private let uuidRegex = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

    private func lines(_ o: ToolOutput) -> [String] { o.text.split(separator: "\n").map(String.init) }

    private func gen(_ kind: String, count: Int = 5, _ extra: OptionValues = [:]) async throws -> [String] {
        var opts: OptionValues = ["kind": .string(kind), "count": .int(count)]
        for (k, v) in extra { opts[k] = v }
        return lines(try await TT.run("id.generate", "", opts))
    }

    // MARK: named UUIDs (deterministic)

    func testUUIDv5DNSExampleCom() async throws {
        let out = try await TT.run("id.generate", "example.com", ["kind": .string("uuid5")])
        XCTAssertEqual(out.text, "cfbff0d1-9375-5685-968c-48ce8b15ae17")
        let viaOption = try await TT.run("id.generate", "", ["kind": .string("uuid5"), "nameValue": .string("example.com")])
        XCTAssertEqual(viaOption.text, "cfbff0d1-9375-5685-968c-48ce8b15ae17")
    }

    func testNamedUUIDsAgainstPython() async throws {
        // Reference values from Python's uuid module.
        let v3 = try await TT.run("id.generate", "python.org", ["kind": .string("uuid3")])
        XCTAssertEqual(v3.text, "6fa459ea-ee8a-3ca4-894e-db77e160355e")
        let v5 = try await TT.run("id.generate", "python.org", ["kind": .string("uuid5")])
        XCTAssertEqual(v5.text, "886313e1-3b8a-5372-9b90-0c9aee199e5d")
        let url = try await TT.run("id.generate", "http://example.com/", ["kind": .string("uuid5"), "namespace": .string("url")])
        XCTAssertEqual(url.text, "0a300ee9-f9e4-5697-a51a-efc7fafaba67")
        let custom = try await TT.run("id.generate", "a", ["kind": .string("uuid5"), "namespace": .string("custom"), "customNamespace": .string("6ba7b811-9dad-11d1-80b4-00c04fd430c8")])
        XCTAssertEqual(custom.text, "e1407479-3136-56c0-9908-bb02fb0339e2")
        let urlA = try await TT.run("id.generate", "a", ["kind": .string("uuid5"), "namespace": .string("url")])
        XCTAssertEqual(custom.text, urlA.text, "custom namespace equal to the URL namespace must agree")
    }

    func testNamedUUIDsAreStableAndFormatted() async throws {
        let a = try await TT.run("id.generate", "x", ["kind": .string("uuid5"), "count": .int(5)])
        XCTAssertEqual(lines(a).count, 1, "name-based UUIDs are deterministic so only one is produced")
        XCTAssertTrue(a.text.range(of: uuidRegex, options: .regularExpression) != nil)
        XCTAssertEqual(Array(a.text)[14], "5"); XCTAssertTrue("89ab".contains(Array(a.text)[19]))
        do { _ = try await TT.run("id.generate", "", ["kind": .string("uuid5")]); XCTFail("expected error") } catch { XCTAssertTrue(error is ToolError) }
    }

    // MARK: random / time based

    func testUUIDv4Format() async throws {
        let ids = try await gen("uuid4", count: 50)
        XCTAssertEqual(ids.count, 50); XCTAssertEqual(Set(ids).count, 50)
        for id in ids {
            XCTAssertNotNil(id.range(of: uuidRegex, options: .regularExpression), id)
            XCTAssertEqual(Array(id)[14], "4", id)
            XCTAssertTrue("89ab".contains(Array(id)[19]), id)
        }
    }

    func testUUIDv7FormatAndOrdering() throws {
        let t0 = Date(timeIntervalSince1970: 1_645_557_742)
        let ids = (0..<20).map { TT.hex(Data(IDGeneratorTool.uuidV7(time: t0.addingTimeInterval(Double($0) * 0.5)))) }
        for id in ids { XCTAssertEqual(Array(id)[12], "7"); XCTAssertTrue("89ab".contains(Array(id)[16])) }
        XCTAssertEqual(ids, ids.sorted(), "v7 sorts by creation time")
        let first = IDGeneratorTool.uuidV7(time: t0)
        let ms = first[0..<6].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        XCTAssertEqual(ms, 1_645_557_742_000)
    }

    func testUUIDv1FormatAndTimestamp() throws {
        let b = IDGeneratorTool.uuidV1()
        XCTAssertEqual(b[6] >> 4, 1); XCTAssertEqual(b[8] >> 6, 0b10)
        XCTAssertEqual(b[10] & 1, 1, "random node uses the multicast bit, never a real MAC")
        let timeLow = UInt64(b[0]) << 24 | UInt64(b[1]) << 16 | UInt64(b[2]) << 8 | UInt64(b[3])
        let ts = (UInt64(b[6] & 0x0F) << 8 | UInt64(b[7])) << 48 | (UInt64(b[4]) << 8 | UInt64(b[5])) << 32 | timeLow
        let unix = Double(ts) / 1e7 - 12_219_292_800
        XCTAssertEqual(unix, Date().timeIntervalSince1970, accuracy: 5)
    }

    func testFormattingOptions() async throws {
        let plain = try await gen("uuid4", count: 1, ["hyphens": .bool(false)])
        XCTAssertEqual(plain[0].count, 32); XCTAssertFalse(plain[0].contains("-"))
        let up = try await gen("uuid4", count: 1, ["uppercase": .bool(true)])
        XCTAssertEqual(up[0], up[0].uppercased())
        let braces = try await gen("uuid4", count: 1, ["braces": .bool(true)])
        XCTAssertTrue(braces[0].hasPrefix("{") && braces[0].hasSuffix("}"))
        let nilIDs = try await gen("nil")
        XCTAssertEqual(nilIDs, ["00000000-0000-0000-0000-000000000000", "ffffffff-ffff-ffff-ffff-ffffffffffff"])
    }

    // MARK: ULID, ObjectId, Nano ID

    func testULIDFormatAndKnownDecode() async throws {
        let ids = try await gen("ulid", count: 20)
        for id in ids { XCTAssertNotNil(id.range(of: "^[0-7][0-9A-HJKMNP-TV-Z]{25}$", options: .regularExpression), id) }
        XCTAssertEqual(Set(ids).count, 20)
        // Timestamp portion is the current time.
        var ms: UInt64 = 0
        for c in ids[0].prefix(10) { ms = ms * 32 + UInt64(IDGeneratorTool.crockford.firstIndex(of: c)!) }
        XCTAssertEqual(Double(ms) / 1000, Date().timeIntervalSince1970, accuracy: 5)
        // Time-ordered: a later timestamp sorts later.
        XCTAssertLessThan(IDGeneratorTool.ulid(time: Date(timeIntervalSince1970: 1_000_000_000)), IDGeneratorTool.ulid(time: Date(timeIntervalSince1970: 1_000_000_001)))
        // Example from the ULID spec README; timestamp value computed independently from the Crockford digits.
        let spec = try await TT.run("id.generate", "01ARZ3NDEKTSV4RRFFQ69G5FAV", ["mode": .string("decode")])
        XCTAssertTrue(spec.metadata.contains { $0.value.contains("1469922850259 ms") }, "\(spec.metadata)")
        XCTAssertTrue(spec.metadata.contains { $0.label == "01ARZ3NDEKTSV4RRFFQ69G5FAV" && $0.value == "ULID" })
        XCTAssertTrue(spec.metadata.contains { $0.value.contains("TSV4RRFFQ69G5FAV") })
    }

    func testULIDEncodesKnownTimestamp() {
        let s = IDGeneratorTool.ulid(time: Date(timeIntervalSince1970: 1_469_918_176.385))
        XCTAssertTrue(s.hasPrefix("01ARYZ6S41"), s)   // ulid README: ulid(1469918176385) = 01ARYZ6S41…
    }

    func testObjectId() async throws {
        let ids = try await gen("objectid", count: 5)
        for id in ids { XCTAssertNotNil(id.range(of: "^[0-9a-f]{24}$", options: .regularExpression)) }
        XCTAssertEqual(UInt32(ids[0].prefix(8), radix: 16).map(Double.init) ?? 0, Date().timeIntervalSince1970, accuracy: 5)
        let dec = try await TT.run("id.generate", "507f1f77bcf86cd799439011", ["mode": .string("decode")])
        XCTAssertTrue(dec.metadata.contains { $0.label == "507f1f77bcf86cd799439011" && $0.value == "MongoDB ObjectId" })
        XCTAssertTrue(dec.metadata.contains { $0.label == "  Counter" && $0.value == String(0x439011) })
    }

    func testNanoID() async throws {
        let ids = try await gen("nanoid", count: 10, ["nanoLength": .int(30)])
        for id in ids {
            XCTAssertEqual(id.count, 30)
            XCTAssertNotNil(id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression))
        }
        let custom = try await gen("nanoid", count: 3, ["nanoLength": .int(8), "nanoAlphabet": .string("ab")])
        for id in custom { XCTAssertEqual(id.count, 8); XCTAssertNotNil(id.range(of: "^[ab]+$", options: .regularExpression)) }
    }

    // MARK: decoding

    func testDecodeUUIDVersions() async throws {
        // RFC 9562 appendix B examples.
        let v1 = try await TT.run("id.generate", "C232AB00-9414-11EC-B3C8-9E6BDECED846", ["mode": .string("decode")])
        XCTAssertTrue(v1.metadata.contains { $0.value.hasPrefix("UUID v1") })
        XCTAssertTrue(v1.metadata.contains { $0.label == "  Timestamp" && $0.value.contains("2022") })
        XCTAssertTrue(v1.metadata.contains { $0.label == "  Clock seq" && $0.value == "0x33c8" })
        XCTAssertTrue(v1.metadata.contains { $0.label == "  Node" && $0.value.hasPrefix("9e:6b:de:ce:d8:46") })
        let v7 = try await TT.run("id.generate", "017F22E2-79B0-7CC3-98C4-DC0C0C07398F", ["mode": .string("decode")])
        XCTAssertTrue(v7.metadata.contains { $0.value.hasPrefix("UUID v7") })
        XCTAssertTrue(v7.metadata.contains { $0.label == "  Timestamp" && $0.value.contains("1645557742000 ms") })
        let v5 = try await TT.run("id.generate", "cfbff0d1-9375-5685-968c-48ce8b15ae17", ["mode": .string("decode")])
        XCTAssertTrue(v5.metadata.contains { $0.value.hasPrefix("UUID v5") })
        let v4 = try await TT.run("id.generate", "{F81D4FAE-7DEC-41D0-A765-00A0C91E6BF6}", ["mode": .string("decode")])
        XCTAssertTrue(v4.metadata.contains { $0.value.hasPrefix("UUID v4") })
        XCTAssertTrue(v4.metadata.contains { $0.label == "  URN" && $0.value == "urn:uuid:f81d4fae-7dec-41d0-a765-00a0c91e6bf6" })
        let zero = try await TT.run("id.generate", "00000000-0000-0000-0000-000000000000", ["mode": .string("decode")])
        XCTAssertTrue(zero.metadata.contains { $0.value == "Nil UUID" })
        let bad = try await TT.run("id.generate", "not-an-id", ["mode": .string("decode")])
        XCTAssertTrue(bad.metadata.contains { $0.value.contains("Not a recognised ID") })
    }

    func testDetect() {
        XCTAssertNotNil(IDGeneratorTool.detect("cfbff0d1-9375-5685-968c-48ce8b15ae17"))
        XCTAssertNotNil(IDGeneratorTool.detect("01ARZ3NDEKTSV4RRFFQ69G5FAV"))
        XCTAssertNotNil(IDGeneratorTool.detect("507f1f77bcf86cd799439011"))
        XCTAssertNil(IDGeneratorTool.detect("hello"))
    }

    func testRFCParseAndFormatRoundTrip() {
        let s = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
        XCTAssertEqual(IDGeneratorTool.format(IDGeneratorTool.parseUUID(s)!), s)
        XCTAssertEqual(IDGeneratorTool.format(IDGeneratorTool.parseUUID("urn:uuid:" + s.uppercased())!), s)
        XCTAssertNil(IDGeneratorTool.parseUUID("6ba7b810-9dad-11d1-80b4-00c04fd430c"))
    }
}
