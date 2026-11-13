import XCTest
@testable import BitlatheCore

final class DeepLinkTests: XCTestCase {
    private func parse(_ s: String) throws -> DeepLink { try DeepLink.parse(URL(string: s)!) }

    func testToolWithInputAndDefaults() throws {
        let l = try parse("bitlathe://tool/json.format?input=%7B%22a%22:1%7D")
        XCTAssertEqual(l.target, .tool("json.format"))
        XCTAssertEqual(l.input, "{\"a\":1}")
        XCTAssertEqual(l.action, .open)
        XCTAssertTrue(l.rawOptions.isEmpty)
    }

    func testActionsAndOptions() throws {
        let l = try parse("bitlathe://tool/json.format?input=x&action=copy&indent=4&sortKeys=true")
        XCTAssertEqual(l.action, .copy)
        XCTAssertEqual(l.rawOptions.map(\.key), ["indent", "sortKeys"])
        XCTAssertEqual(try parse("bitlathe://tool/a?action=REPLACE").action, .replace)
    }

    func testBase64Input() throws {
        XCTAssertEqual(try parse("bitlathe://tool/a?input64=aGVsbG8").input, "hello")
        let std = Data("hi??>>".utf8).base64EncodedString()
        XCTAssertEqual(DeepLink.decodeBase64(std.replacingOccurrences(of: "+", with: " ")), "hi??>>")
        XCTAssertNil(DeepLink.decodeBase64("!!!"))
        XCTAssertThrowsError(try parse("bitlathe://tool/a?input64=!!!"))
    }

    func testPipelineAndDetect() throws {
        XCTAssertEqual(try parse("bitlathe://pipeline/My%20Pipe?input=a").target, .pipeline("My Pipe"))
        XCTAssertEqual(try parse("bitlathe://pipeline/my-pipe").target, .pipeline("my-pipe"))
        let d = try parse("bitlathe://detect?input=eyJhIjoxfQ%3D%3D")
        XCTAssertEqual(d.target, .detect)
        XCTAssertEqual(d.input, "eyJhIjoxfQ==")
    }

    func testErrors() {
        XCTAssertThrowsError(try parse("https://tool/x"))
        XCTAssertThrowsError(try parse("bitlathe://"))
        XCTAssertThrowsError(try parse("bitlathe://tool"))
        XCTAssertThrowsError(try parse("bitlathe://nope/x"))
        XCTAssertThrowsError(try parse("bitlathe://tool/x?action=explode"))
    }

    func testResolveOptions() throws {
        let fields = [
            OptionField("indent", "Indent", .stepper(min: 0, max: 8, step: 1), default: .int(2)),
            OptionField("sortKeys", "Sort", .toggle, default: .bool(false)),
            OptionField("mode", "Mode", .picker([OptionChoice("a"), OptionChoice("b")]), default: .string("a")),
        ]
        let o = try parse("bitlathe://tool/x?indent=4&sortKeys=true&mode=b").resolveOptions(for: fields)
        XCTAssertEqual(o["indent"], .int(4))
        XCTAssertEqual(o["sortKeys"], .bool(true))
        XCTAssertEqual(o["mode"], .string("b"))
        XCTAssertThrowsError(try parse("bitlathe://tool/x?bogus=1").resolveOptions(for: fields))
    }

    func testRoundTrip() throws {
        let l = DeepLink(target: .tool("json.format"), input: "{\"a\": 1}&x", action: .copy, rawOptions: [.init("indent", "4")])
        let back = try DeepLink.parse(try XCTUnwrap(l.url()))
        XCTAssertEqual(back, l)
    }
}
