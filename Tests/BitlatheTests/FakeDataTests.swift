import XCTest
import BitlatheCore
@testable import BitlatheTools

final class FakeDataTests: XCTestCase {
    private func run(_ fields: String, count: Int = 20, seed: Int = 42, format: String = "json", locale: String = "en", table: String = "users") async throws -> ToolOutput {
        try await TT.run("fake.data", "", ["fields": .string(fields), "count": .int(count), "seed": .int(seed), "format": .string(format), "locale": .string(locale), "table": .string(table)])
    }

    private func rows(_ out: ToolOutput) throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.text.utf8)) as? [[String: Any]])
    }

    private var allTypes: [String] { FakeDataTool.fieldChoices.map(\.0) }

    // MARK: determinism

    func testSameSeedSameDataForEveryFieldTypeAndLocale() async throws {
        for locale in ["en", "de", "fr", "es", "jp"] {
            for type in allTypes {
                let a = try await run(type, count: 15, seed: 1234, locale: locale)
                let b = try await run(type, count: 15, seed: 1234, locale: locale)
                XCTAssertEqual(a.text, b.text, "field \(type) locale \(locale) must be reproducible from the seed")
            }
        }
    }

    func testDifferentSeedsDiffer() async throws {
        let a = try await run("fullName, email, iban", seed: 1)
        let b = try await run("fullName, email, iban", seed: 2)
        XCTAssertNotEqual(a.text, b.text)
    }

    func testPrefixStability() async throws {
        // The first N rows of a longer run equal a shorter run with the same seed.
        let short = try rows(try await run("fullName, email, city", count: 5, seed: 9))
        let long = try rows(try await run("fullName, email, city", count: 25, seed: 9))
        XCTAssertEqual(short.count, 5); XCTAssertEqual(long.count, 25)
        for i in 0..<5 { XCTAssertEqual(short[i] as NSDictionary, long[i] as NSDictionary) }
    }

    func testPostcodeIsSeeded() async throws {
        // Regression: postcodes were drawn from the system RNG, so the same seed gave different output.
        for locale in ["en", "de", "fr", "es", "jp"] {
            let a = try await run("postcode", count: 10, seed: 5, locale: locale), b = try await run("postcode", count: 10, seed: 5, locale: locale)
            XCTAssertEqual(a.text, b.text, locale)
        }
    }

    // MARK: value validity

    func testFieldFormats() async throws {
        let r = try rows(try await run("id, uuid, email, ipv4, ipv6, macAddress, colorHex, latitude, longitude, age, boolean, price, phone, cardExpiry, date, dateTime, url, slug, countryCode, birthdate", count: 60, seed: 7))
        XCTAssertEqual(r.count, 60)
        for (i, row) in r.enumerated() {
            XCTAssertEqual(row["id"] as? Int, i + 1)
            XCTAssertNotNil((row["uuid"] as? String)?.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression))
            XCTAssertNotNil((row["email"] as? String)?.range(of: "^[a-z0-9.-]+@[a-z0-9.]+\\.[a-z]+$", options: .regularExpression), "\(row["email"] ?? "")")
            let ip = (row["ipv4"] as? String ?? "").split(separator: ".").compactMap { Int($0) }
            XCTAssertEqual(ip.count, 4); XCTAssertTrue(ip.allSatisfy { (0...255).contains($0) })
            XCTAssertNotNil((row["ipv6"] as? String)?.range(of: "^2001:db8(:[0-9a-f]{1,4}){6}$", options: .regularExpression))
            XCTAssertNotNil((row["macAddress"] as? String)?.range(of: "^([0-9a-f]{2}:){5}[0-9a-f]{2}$", options: .regularExpression))
            XCTAssertNotNil((row["colorHex"] as? String)?.range(of: "^#[0-9A-F]{6}$", options: .regularExpression))
            XCTAssertTrue((-90.0...90.0).contains(row["latitude"] as? Double ?? 999)); XCTAssertTrue((-180.0...180.0).contains(row["longitude"] as? Double ?? 999))
            XCTAssertTrue((18...80).contains(row["age"] as? Int ?? 0))
            XCTAssertNotNil(row["boolean"] as? Bool)
            XCTAssertNotNil((row["cardExpiry"] as? String)?.range(of: "^(0[1-9]|1[0-2])/\\d{2}$", options: .regularExpression))
            XCTAssertNotNil((row["date"] as? String)?.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression))
            XCTAssertNotNil((row["dateTime"] as? String)?.range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", options: .regularExpression))
            XCTAssertTrue((row["url"] as? String ?? "").hasPrefix("https://"))
            XCTAssertNotNil((row["slug"] as? String)?.range(of: "^[a-z]+-[a-z]+-\\d+$", options: .regularExpression), "\(row["slug"] ?? "")")
        }
        XCTAssertEqual(Set(r.compactMap { $0["uuid"] as? String }).count, 60, "uuids are unique")
    }

    func testIBANsHaveValidMod97() async throws {
        let r = try rows(try await run("iban", count: 200, seed: 3))
        for row in r {
            let iban = try XCTUnwrap(row["iban"] as? String)
            let lengths = ["GB": 22, "DE": 22, "FR": 27, "NL": 18, "ES": 24]
            XCTAssertEqual(iban.count, lengths[String(iban.prefix(2))], iban)
            let rearranged = iban.dropFirst(4) + iban.prefix(4)
            var remainder = 0
            for ch in rearranged {
                let digits = ch.isNumber ? String(ch) : String(ch.asciiValue! - 55)
                for d in digits { remainder = (remainder * 10 + Int(String(d))!) % 97 }
            }
            XCTAssertEqual(remainder, 1, "IBAN mod 97 for \(iban)")
        }
    }

    func testCardNumbersPassLuhn() async throws {
        let r = try rows(try await run("creditCard", count: 200, seed: 11))
        for row in r {
            let number = try XCTUnwrap(row["creditCard"] as? String)
            XCTAssertTrue([15, 16].contains(number.count), number)
            var sum = 0
            for (i, ch) in number.reversed().enumerated() {
                var d = ch.wholeNumberValue!
                if i % 2 == 1 { d *= 2; if d > 9 { d -= 9 } }
                sum += d
            }
            XCTAssertEqual(sum % 10, 0, "Luhn for \(number)")
        }
    }

    func testKnownChecksumHelpers() {
        // Public examples: Visa test number 4111 1111 1111 1111; IBAN GB82 WEST 1234 5698 7654 32.
        XCTAssertEqual(FakeDataTool.luhn("411111111111111"), "4111111111111111")
        XCTAssertEqual(FakeDataTool.luhn("7992739871"), "79927398713")
        XCTAssertEqual(FakeDataTool.ibanChecksum("GB", "WEST12345698765432"), "82")
        XCTAssertEqual(FakeDataTool.ibanChecksum("DE", "370400440532013000"), "89")
    }

    func testLocalesProduceLocalNames() async throws {
        let de = try rows(try await run("lastName, country", count: 40, seed: 2, locale: "de"))
        let germanSurnames = Set(FakeDataTool.de.last)
        XCTAssertTrue(de.allSatisfy { germanSurnames.contains($0["lastName"] as? String ?? "") })
        XCTAssertTrue(de.allSatisfy { ["Deutschland", "Österreich", "Schweiz"].contains($0["country"] as? String ?? "") })
        let en = try await run("postcode", count: 1, seed: 2, locale: "en")
        XCTAssertNotNil(en.text.range(of: "\"[A-Z]{1,2}\\d{1,2} \\d[A-Z]{2}\"", options: .regularExpression), en.text)
    }

    // MARK: formats and options

    func testRenamingAndOutputFormats() async throws {
        let csv = try await run("id, who:fullName, mail:email", count: 3, seed: 1, format: "csv")
        let lines = csv.text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4); XCTAssertEqual(lines[0], "id,who,mail")
        XCTAssertTrue(lines[1].hasPrefix("1,"))
        let nd = try await run("id, name:fullName", count: 3, seed: 1, format: "ndjson")
        let ndLines = nd.text.split(separator: "\n")
        XCTAssertEqual(ndLines.count, 3)
        for l in ndLines { XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any]) }
        let sql = try await run("id, name:fullName, ok:boolean", count: 2, seed: 1, format: "sql", table: "people")
        XCTAssertTrue(sql.text.hasPrefix("INSERT INTO people (\"id\", \"name\", \"ok\") VALUES\n(1, '"), sql.text)
        XCTAssertTrue(sql.text.hasSuffix(");"))
        XCTAssertTrue(sql.text.contains("TRUE") || sql.text.contains("FALSE"))
        let apostrophe = try await run("lastName", count: 400, seed: 4, format: "sql")
        XCTAssertFalse(apostrophe.text.contains("''''"), "quotes are escaped by doubling")
        XCTAssertEqual(TT.meta(csv, "Rows"), "3")
    }

    func testErrors() async {
        do { _ = try await run("nonsense"); XCTFail("expected error") } catch let e as ToolError { XCTAssertTrue(e.message.contains("Unknown field type")) } catch { XCTFail("\(error)") }
        do { _ = try await run(" , "); XCTFail("expected error") } catch { XCTAssertTrue(error is ToolError) }
    }

    func testLargeRunIsFast() async throws {
        let start = Date()
        let out = try await run("id, fullName, email, iban, dateTime", count: 5000, seed: 8, format: "ndjson")
        XCTAssertEqual(out.text.split(separator: "\n").count, 5000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
