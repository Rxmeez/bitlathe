import XCTest
import BitlatheCore
@testable import BitlatheTools

private let dec: OptionValues = ["mode": .string("decode")]

final class Base64Tests: XCTestCase {
    /// RFC 4648 section 10 test vectors.
    func testRFC4648Vectors() async throws {
        let v = [("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"), ("foob", "Zm9vYg=="), ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy")]
        for (plain, enc) in v {
            let e = try await T.text(Base64TextTool.self, plain)
            XCTAssertEqual(e, enc)
            let d = try await T.text(Base64TextTool.self, enc, dec)
            XCTAssertEqual(d, plain)
        }
    }

    func testUnpaddedAndURLSafe() async throws {
        // 0xFB 0xFF 0xBF => "+/+/" in standard, "-_-_" in URL-safe (computed with Python).
        let url = try await T.text(Base64TextTool.self, "Zg", ["mode": .string("decode"), "variant": .string("url")])
        XCTAssertEqual(url, "f")
        try await AEq(try await T.text(Base64TextTool.self, "f", ["padding": .bool(false)]), "Zg")
        let out = try await AnyTool(Base64TextTool.self).run(ToolInput(.data(Data([0xFB, 0xFF, 0xBF]))), options: ["variant": .string("url")])
        XCTAssertEqual(out.text, "-_-_")
        let std = try await AnyTool(Base64TextTool.self).run(ToolInput(.data(Data([0xFB, 0xFF, 0xBF]))))
        XCTAssertEqual(std.text, "+/+/")
    }

    func testUnicodeRoundTrip() async throws {
        let e = try await T.text(Base64TextTool.self, "Hello, Bitlathe! 👋")
        XCTAssertEqual(e, "SGVsbG8sIEJpdGxhdGhlISDwn5GL")
        try await AEq(try await T.text(Base64TextTool.self, e, dec), "Hello, Bitlathe! 👋")
        let u = try await T.text(Base64TextTool.self, unicodeSample)
        try await AEq(try await T.text(Base64TextTool.self, u, dec), unicodeSample)
    }

    func testWrapAt76() async throws {
        let long = String(repeating: "abcdefghij", count: 20)
        let e = try await T.text(Base64TextTool.self, long, ["wrap": .bool(true)])
        let lines = e.split(separator: "\n")
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines.dropLast().allSatisfy { $0.count == 76 })
        try await AEq(try await T.text(Base64TextTool.self, e, dec), long)
    }

    func testDecodeIgnoresWhitespaceAndDataURI() async throws {
        try await AEq(try await T.text(Base64TextTool.self, "Zm9v\nYmFy\n", dec), "foobar")
        try await AEq(try await T.text(Base64TextTool.self, "data:text/plain;base64,Zm9vYmFy", dec), "foobar")
    }

    func testErrors() async throws {
        let e1 = await T.error(Base64TextTool.self, "", [:])
        XCTAssertEqual(e1, .emptyInput)
        let e2 = await T.error(Base64TextTool.self, "", dec)
        XCTAssertEqual(e2, .emptyInput)
        let e3 = await T.error(Base64TextTool.self, "Zm9v!!!", dec)
        XCTAssertTrue(e3?.message.contains("Invalid Base64 character") == true, e3?.message ?? "")
    }

    func testHugeRoundTrip() async throws {
        let blob = pseudoRandomBytes(3_000_000)
        let enc = try await AnyTool(Base64TextTool.self).run(ToolInput(.data(blob)))
        XCTAssertEqual(enc.text, blob.base64EncodedString())
        let back = try await AnyTool(Base64TextTool.self).run(text: enc.text, options: dec)
        guard case .data(let d) = back.payload else { return XCTFail("expected binary payload") }
        XCTAssertEqual(d, blob)
    }
}

final class Base32Tests: XCTestCase {
    func testRFC4648Vectors() async throws {
        let std = [("f", "MY======"), ("fo", "MZXQ===="), ("foo", "MZXW6==="), ("foob", "MZXW6YQ="), ("fooba", "MZXW6YTB"), ("foobar", "MZXW6YTBOI======")]
        let hex = [("f", "CO======"), ("fo", "CPNG===="), ("foo", "CPNMU==="), ("foob", "CPNMUOG="), ("fooba", "CPNMUOJ1"), ("foobar", "CPNMUOJ1E8======")]
        for (p, e) in std {
            try await AEq(try await T.text(Base32Tool.self, p), e)
            try await AEq(try await T.text(Base32Tool.self, e, dec), p)
        }
        for (p, e) in hex {
            try await AEq(try await T.text(Base32Tool.self, p, ["alphabet": .string("hex")]), e)
            try await AEq(try await T.text(Base32Tool.self, e, ["alphabet": .string("hex"), "mode": .string("decode")]), p)
        }
    }

    func testUnpaddedAndLowercaseDecode() async throws {
        try await AEq(try await T.text(Base32Tool.self, "foobar", ["padding": .bool(false)]), "MZXW6YTBOI")
        try await AEq(try await T.text(Base32Tool.self, "MZXW6YTBOI", dec), "foobar")
        try await AEq(try await T.text(Base32Tool.self, "mzxw6ytboi======", dec), "foobar")
    }

    func testCrockfordAndUnicodeRoundTrip() async throws {
        for alpha in ["rfc", "hex", "crockford"] {
            let e = try await T.text(Base32Tool.self, unicodeSample, ["alphabet": .string(alpha)])
            let d = try await T.text(Base32Tool.self, e, ["alphabet": .string(alpha), "mode": .string("decode")])
            XCTAssertEqual(d, unicodeSample, alpha)
        }
    }

    func testErrors() async throws {
        let e0 = await T.error(Base32Tool.self, "")
        XCTAssertEqual(e0, .emptyInput)
        let e = await T.error(Base32Tool.self, "MZXW1!!", dec)   // '1', '!' are not in the RFC alphabet
        XCTAssertNotNil(e)
    }

    func testBinaryRoundTrip() async throws {
        let blob = pseudoRandomBytes(1_000_003)
        let enc = try await AnyTool(Base32Tool.self).run(ToolInput(.data(blob)))
        let back = try await AnyTool(Base32Tool.self).run(text: enc.text, options: dec)
        if case .data(let d) = back.payload { XCTAssertEqual(d, blob) } else if let s = back.payload.text { XCTAssertEqual(Data(s.utf8), blob) }
    }
}

final class Base58Tests: XCTestCase {
    func testKnownVectors() async throws {
        // Vectors from the Bitcoin base58 test suite.
        try await AEq(try await T.text(Base58Tool.self, "Hello World!"), "2NEpo7TZRRrLZSi2U")
        try await AEq(try await T.text(Base58Tool.self, "The quick brown fox jumps over the lazy dog."), "USm3fpXnKG5EUBx2ndxBDMPVciP5hGey2Jh4NDv6gmeo1LkMeiKrLJUUBk6Z")
        try await AEq(try await T.text(Base58Tool.self, "73696d706c792061206c6f6e6720737472696e67", ["inputHex": .bool(true)]), "2cFupjhnEsSn59qHXstmK2ffpLv2")
        try await AEq(try await T.text(Base58Tool.self, "0000287fb4cd", ["inputHex": .bool(true)]), "11233QC4")
        try await AEq(try await T.text(Base58Tool.self, "2NEpo7TZRRrLZSi2U", dec), "Hello World!")
    }

    func testCheckRoundTrip() async throws {
        let enc = try await T.text(Base58Tool.self, "00f54a5851e9372b87810a8e60cdd2e7cfd80b6e31", ["inputHex": .bool(true), "check": .bool(true)])
        // Known Bitcoin address for hash160 f54a5851e9372b87810a8e60cdd2e7cfd80b6e31.
        XCTAssertEqual(enc, "1PMycacnJaSqwwJqjawXBErnLsZ7RkXUAs")
        let out = try await AnyTool(Base58Tool.self).run(text: enc, options: ["mode": .string("decode"), "check": .bool(true)])
        XCTAssertTrue(out.metadata.map { "\($0.label) \($0.value)" }.joined().isEmpty == false)
        // Corrupt a character => checksum failure.
        let bad = String(enc.dropLast()) + "t"
        let e = await T.error(Base58Tool.self, bad, ["mode": .string("decode"), "check": .bool(true)])
        XCTAssertNotNil(e)
    }

    func testErrorsAndUnicode() async throws {
        let e0 = await T.error(Base58Tool.self, "")
        XCTAssertEqual(e0, .emptyInput)
        let e = await T.error(Base58Tool.self, "0OIl", dec)   // excluded characters
        XCTAssertNotNil(e)
        let enc = try await T.text(Base58Tool.self, unicodeSample)
        try await AEq(try await T.text(Base58Tool.self, enc, dec), unicodeSample)
    }

    func testRoundTripBinary() async throws {
        let blob = Data([0, 0, 0]) + pseudoRandomBytes(3000)
        let enc = try await AnyTool(Base58Tool.self).run(ToolInput(.data(blob)))
        XCTAssertTrue(enc.text.hasPrefix("111"))
        XCTAssertEqual(try BaseN.base58Decode(enc.text), blob)
    }
}

final class Base85Tests: XCTestCase {
    func testAscii85Vectors() async throws {
        try await AEq(try await T.text(Base85Tool.self, "Man ", ["delimiters": .bool(false)]), "9jqo^")
        try await AEq(try await T.text(Base85Tool.self, "Man "), "<~9jqo^~>")
        try await AEq(try await T.text(Base85Tool.self, "9jqo^", dec), "Man ")
        try await AEq(try await T.text(Base85Tool.self, "<~9jqo^~>", dec), "Man ")
        try await AEq(try await T.text(Base85Tool.self, "Hello, Bitlathe! 👋", ["delimiters": .bool(false)]), "87cURD_*\"tBln0\"FD,5/+Rl\"cMZ")
        try await AEq(try await T.text(Base85Tool.self, "abc", ["delimiters": .bool(false)]), "@:E^")
    }

    func testRFC1924AlphabetMatchesPython() async throws {
        let e = try await T.text(Base85Tool.self, "Hello, Bitlathe! 👋", ["variant": .string("rfc1924")])
        XCTAssertEqual(e, "NM&qnZ!91}X>@F1bZBKEAn>1&iv")
        try await AEq(try await T.text(Base85Tool.self, e, ["variant": .string("rfc1924"), "mode": .string("decode")]), "Hello, Bitlathe! 👋")
    }

    func testZ85SpecVector() async throws {
        // ZeroMQ RFC 32 test vector: 86 4F D2 6F B5 59 F7 5B <-> "HelloWorld".
        let bytes = Data([0x86, 0x4F, 0xD2, 0x6F, 0xB5, 0x59, 0xF7, 0x5B])
        let enc = try await AnyTool(Base85Tool.self).run(ToolInput(.data(bytes)), options: ["variant": .string("z85")])
        XCTAssertEqual(enc.text, "HelloWorld")
        XCTAssertEqual(try BaseN.base85Decode("HelloWorld", alphabet: BaseN.z85Alphabet), bytes)
    }

    func testAllVariantsRoundTrip() async throws {
        for variant in ["ascii85", "z85", "rfc1924"] {
            for len in [1, 2, 3, 4, 5, 7, 64, 1001] {
                let blob = pseudoRandomBytes(len, seed: UInt64(len))
                let enc = try await AnyTool(Base85Tool.self).run(ToolInput(.data(blob)), options: ["variant": .string(variant)])
                let dc = try await AnyTool(Base85Tool.self).run(text: enc.text, options: ["variant": .string(variant), "mode": .string("decode")])
                let got: Data = { if case .data(let d) = dc.payload { return d }; return Data(dc.text.utf8) }()
                XCTAssertEqual(got, blob, "\(variant) len \(len)")
            }
            let u = try await T.text(Base85Tool.self, unicodeSample, ["variant": .string(variant)])
            try await AEq(try await T.text(Base85Tool.self, u, ["variant": .string(variant), "mode": .string("decode")]), unicodeSample)
        }
    }

    func testZeroGroupAndErrors() async throws {
        let z = try await AnyTool(Base85Tool.self).run(ToolInput(.data(Data(repeating: 0, count: 4))), options: ["delimiters": .bool(false)])
        XCTAssertEqual(z.text, "z")
        let e0 = await T.error(Base85Tool.self, "")
        XCTAssertEqual(e0, .emptyInput)
        let e = await T.error(Base85Tool.self, "9jq\u{7F}^", dec)
        XCTAssertNotNil(e)
    }
}

final class URLEncodeTests: XCTestCase {
    func testComponentMatchesPython() async throws {
        // Python urllib.parse.quote(s, safe="") reference output.
        let e = try await T.text(URLEncodeTool.self, "café au lait/&=+ ~*'()!")
        XCTAssertEqual(e, "caf%C3%A9%20au%20lait%2F%26%3D%2B%20~%2A%27%28%29%21")
    }

    func testFormScope() async throws {
        try await AEq(try await T.text(URLEncodeTool.self, "a b&c=d é", ["scope": .string("form")]), "a+b%26c%3Dd+%C3%A9")
        try await AEq(try await T.text(URLEncodeTool.self, "a+b%26c%3Dd+%C3%A9", ["scope": .string("form"), "mode": .string("decode")]), "a b&c=d é")
    }

    func testFullURLKeepsStructure() async throws {
        let e = try await T.text(URLEncodeTool.self, "https://example.com/a b/ü?q=1 2&x=é#frag", ["scope": .string("full")])
        XCTAssertEqual(e, "https://example.com/a%20b/%C3%BC?q=1%202&x=%C3%A9#frag")
    }

    func testAllScopeEncodesEverything() async throws {
        try await AEq(try await T.text(URLEncodeTool.self, "ab-", ["scope": .string("all")]), "%61%62%2D")
    }

    func testRoundTripUnicodeAllScopes() async throws {
        for scope in ["component", "form", "all"] {
            let e = try await T.text(URLEncodeTool.self, unicodeSample, ["scope": .string(scope)])
            XCTAssertFalse(e.unicodeScalars.contains { $0.value > 127 }, scope)
            try await AEq(try await T.text(URLEncodeTool.self, e, ["scope": .string(scope), "mode": .string("decode")]), unicodeSample, scope)
        }
    }

    func testDecodeErrorsAndEmpty() async throws {
        let e0 = await T.error(URLEncodeTool.self, "")
        XCTAssertEqual(e0, .emptyInput)
        let bad = await T.error(URLEncodeTool.self, "%E0%A4%A", dec)
        XCTAssertNotNil(bad)
        let invalidUTF8 = await T.error(URLEncodeTool.self, "%FF%FE", dec)
        XCTAssertNotNil(invalidUTF8)
    }

    func testPerLine() async throws {
        let e = try await T.text(URLEncodeTool.self, "a b\nc d")
        XCTAssertEqual(e, "a%20b\nc%20d")
    }

    func testHugeRoundTrip() async throws {
        let big = String(repeating: "naïve café & more=stuff 日本 ", count: 60_000)   // ~2 MB
        let e = try await T.text(URLEncodeTool.self, big)
        try await AEq(try await T.text(URLEncodeTool.self, e, dec), big)
    }
}

final class HTMLEntitiesTests: XCTestCase {
    func testNamedEncodeAndDecode() async throws {
        let e = try await T.text(HTMLEntitiesTool.self, "<a href=\"x\">Tom & Jerry's café</a> © 2026")
        XCTAssertTrue(e.contains("&lt;a href=&quot;x&quot;&gt;"))
        XCTAssertTrue(e.contains("Tom &amp; Jerry"))
        XCTAssertTrue(e.contains("caf&eacute;"))
        XCTAssertTrue(e.contains("&copy;"))
        try await AEq(try await T.text(HTMLEntitiesTool.self, "&lt;p&gt;Caf&eacute; &amp; cr&#232;me &#x2014; &copy;&lt;/p&gt;", dec), "<p>Café & crème — ©</p>")
    }

    func testNumericStylesRoundTrip() async throws {
        try await AEq(try await T.text(HTMLEntitiesTool.self, "é<", ["style": .string("decimal")]), "&#233;&#60;")
        try await AEq(try await T.text(HTMLEntitiesTool.self, "é<", ["style": .string("hex")]).uppercased(), "&#XE9;&#X3C;")
        for style in ["named", "decimal", "hex"] {
            for scope in ["special", "nonascii", "all"] {
                let o: OptionValues = ["style": .string(style), "scope": .string(scope)]
                let e = try await T.text(HTMLEntitiesTool.self, unicodeSample + " <&>\"'", o)
                try await AEq(try await T.text(HTMLEntitiesTool.self, e, dec), unicodeSample + " <&>\"'", "\(style)/\(scope)")
            }
        }
    }

    func testEmojiAsSingleScalarEntity() async throws {
        try await AEq(try await T.text(HTMLEntitiesTool.self, "😀", ["style": .string("decimal")]), "&#128512;")
        try await AEq(try await T.text(HTMLEntitiesTool.self, "&#x1F600; &#128512;", dec), "😀 😀")
    }

    func testUnknownEntityLeftAlone() async throws {
        try await AEq(try await T.text(HTMLEntitiesTool.self, "&notanentity; & &amp", dec), "&notanentity; & &amp")
    }

    func testEmptyInput() async throws {
        let e = await T.error(HTMLEntitiesTool.self, "")
        XCTAssertNotNil(e)
    }
}

final class BackslashTests: XCTestCase {
    func testEscapeBasic() async throws {
        try await AEq(try await T.text(BackslashTool.self, "a\nb\t\"c\" \\"), "a\\nb\\t\\\"c\\\" \\\\")
        try await AEq(try await T.text(BackslashTool.self, "\"q\"", ["escapeQuotes": .bool(false)]), "\"q\"")
    }

    func testUnescapeSequences() async throws {
        let u = try await T.text(BackslashTool.self, "Hello\\nWorld\\t\\\"quoted\\\" \\u00e9 \\x41", ["mode": .string("unescape")])
        XCTAssertEqual(u, "Hello\nWorld\t\"quoted\" é A")
    }

    func testRoundTrips() async throws {
        let src = "line1\nline2\r\n\ttab \"quote\" 'single' \\ back \u{08}\u{0C}\u{0B}\u{00}" + unicodeSample
        for uni in [false, true] {
            let e = try await T.text(BackslashTool.self, src, ["escapeUnicode": .bool(uni)])
            if uni { XCTAssertFalse(e.unicodeScalars.contains { $0.value > 127 }) }
            try await AEq(try await T.text(BackslashTool.self, e, ["mode": .string("unescape")]), src, "escapeUnicode=\(uni)")
        }
    }

    func testEscapeUnicodeNonBMP() async throws {
        let e = try await T.text(BackslashTool.self, "😀", ["escapeUnicode": .bool(true)])
        XCTAssertEqual(e, "\\U0001f600")
        try await AEq(try await T.text(BackslashTool.self, "\\U0001f600", ["mode": .string("unescape")]), "😀")
        try await AEq(try await T.text(BackslashTool.self, "\\ud83d\\ude00", ["mode": .string("unescape")]), "😀")
    }

    func testEmpty() async throws {
        let e = await T.error(BackslashTool.self, "")
        XCTAssertNotNil(e)
    }
}

final class UnicodeEscapeTests: XCTestCase {
    func testFormatsKnownOutput() async throws {
        func enc(_ s: String, _ f: String, _ scope: String = "nonascii") async throws -> String {
            try await T.text(UnicodeEscapeTool.self, s, ["format": .string(f), "scope": .string(scope)])
        }
        try await AEq(try await enc("é😀", "js").lowercased(), "\\u00e9\\ud83d\\ude00")
        try await AEq(try await enc("é😀", "es6").uppercased(), "\\U{E9}\\U{1F600}")
        try await AEq(try await enc("é😀", "python").lowercased(), "\\u00e9\\u0001f600")
        try await AEq(try await enc("é😀", "decimal"), "&#233;&#128512;")
        try await AEq(try await enc("é", "percent"), "%C3%A9")
        try await AEq(try await enc("é", "bytes").lowercased(), "\\xc3\\xa9")
        try await AEq(try await enc("é😀", "codepoint").uppercased(), "U+00E9U+1F600")
        try await AEq(try await enc("ab", "js", "all").lowercased(), "\\u0061\\u0062")
    }

    func testAllFormatsRoundTrip() async throws {
        for f in ["js", "es6", "python", "decimal", "hex", "percent", "codepoint", "bytes", "css"] {
            for scope in ["nonascii", "all"] {
                let src = "Abc é ✓ 😀 日本"
                let e = try await T.text(UnicodeEscapeTool.self, src, ["format": .string(f), "scope": .string(scope)])
                let d = try await T.text(UnicodeEscapeTool.self, e, ["mode": .string("decode")])
                XCTAssertEqual(d, src, "\(f)/\(scope): \(e)")
            }
        }
    }

    func testDecodeMixedSample() async throws {
        let d = try await T.text(UnicodeEscapeTool.self, "Caf\\u00e9 \\u{2713} \\ud83d\\udc4b &#8212; na%C3%AFve U+1F600", dec)
        XCTAssertEqual(d, "Café ✓ 👋 — naïve 😀")
    }

    func testEmpty() async throws {
        let e = await T.error(UnicodeEscapeTool.self, "")
        XCTAssertNotNil(e)
    }
}

final class PunycodeTests: XCTestCase {
    /// RFC 3492 section 7.1 sample strings (reference computed with Python's punycode codec).
    func testRFC3492Samples() async throws {
        let samples = [("ليهمابتكلموشعربي؟", "egbpdaj6bu4bxfgehfvwxn"),
                       ("他们为什么不说中文", "ihqwcrb4cv8a8dqg056pqjye"),
                       ("3年B組金八先生", "3B-ww4c5e180e575a65lsy2b"),
                       ("Pročprostěnemluvíčesky", "Proprostnemluvesky-uyb24dma41a"),
                       ("münchen", "mnchen-3ya"), ("bücher", "bcher-kva"), ("日本語", "wgv71a119e"), ("😀", "e28h")]
        for (u, p) in samples {
            try await AEq(try await T.text(PunycodeTool.self, u, ["rawPunycode": .bool(true)]), p, u)
            try await AEq(try await T.text(PunycodeTool.self, p, ["rawPunycode": .bool(true), "mode": .string("decode")]), u, p)
        }
    }

    func testDomains() async throws {
        try await AEq(try await T.text(PunycodeTool.self, "münchen.de"), "xn--mnchen-3ya.de")
        try await AEq(try await T.text(PunycodeTool.self, "xn--mnchen-3ya.de", dec), "münchen.de")
        try await AEq(try await T.text(PunycodeTool.self, "例え.テスト"), "xn--r8jz45g.xn--zckzah")
        try await AEq(try await T.text(PunycodeTool.self, "plain.example.com"), "plain.example.com")
        let multi = try await T.text(PunycodeTool.self, "münchen.de\nbücher.example")
        XCTAssertEqual(multi, "xn--mnchen-3ya.de\nxn--bcher-kva.example")
    }

    func testRoundTripEmojiDomain() async throws {
        let e = try await T.text(PunycodeTool.self, "😀.example")
        XCTAssertTrue(e.hasPrefix("xn--"))
        try await AEq(try await T.text(PunycodeTool.self, e, dec), "😀.example")
    }

    func testErrors() async throws {
        let e0 = await T.error(PunycodeTool.self, "")
        XCTAssertNotNil(e0)
        let bad = await T.error(PunycodeTool.self, "xn--!!!.com", dec)
        XCTAssertNotNil(bad)
    }
}

final class QuotedPrintableTests: XCTestCase {
    func testKnownEncoding() async throws {
        try await AEq(try await T.text(QuotedPrintableTool.self, "Grüße = ok"), "Gr=C3=BC=C3=9Fe =3D ok")
        try await AEq(try await T.text(QuotedPrintableTool.self, "Gr=C3=BC=C3=9Fe =3D ok", dec), "Grüße = ok")
    }

    func testSoftBreaksAndLineLength() async throws {
        let src = String(repeating: "x", count: 100) + "é"
        let e = try await T.text(QuotedPrintableTool.self, src)
        XCTAssertTrue(e.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy { $0.count <= 76 })
        try await AEq(try await T.text(QuotedPrintableTool.self, e, dec), src)
        try await AEq(try await T.text(QuotedPrintableTool.self, "soft=\nline break", dec), "softline break")
    }

    func testRoundTripUnicodeAndTrailingSpace() async throws {
        for src in [unicodeSample, "trailing space \nnext\t\nend ", "= signs == and =41", String(repeating: "日本語 ", count: 500)] {
            let e = try await T.text(QuotedPrintableTool.self, src)
            try await AEq(try await T.text(QuotedPrintableTool.self, e, dec), src)
        }
    }

    func testEmpty() async throws {
        let e = await T.error(QuotedPrintableTool.self, "")
        XCTAssertNotNil(e)
    }
}

final class CompressTests: XCTestCase {
    private let algos = ["gzip", "deflate", "zlib", "brotli", "lzfse", "lz4", "lzma"]

    func testEveryAlgorithmRoundTripsEveryWrap() async throws {
        let src = String(repeating: "Bitlathe compresses repeated text very well. ", count: 40) + unicodeSample
        for a in algos {
            for wrap in ["base64", "hex"] {
                let c = try await T.text(CompressTool.self, src, ["algorithm": .string(a), "wrap": .string(wrap)])
                XCTAssertFalse(c.isEmpty, a)
                let d = try await T.text(CompressTool.self, c, ["mode": .string("decompress"), "algorithm": .string(a), "wrap": .string(wrap)])
                XCTAssertEqual(d, src, "\(a)/\(wrap)")
            }
        }
    }

    func testAutoDetectGzipZlib() async throws {
        let src = String(repeating: "auto detect me ", count: 30)
        for a in ["gzip", "zlib", "lzfse", "lz4"] {
            let c = try await T.text(CompressTool.self, src, ["algorithm": .string(a)])
            let d = try await T.text(CompressTool.self, c, ["mode": .string("decompress"), "algorithm": .string("auto")])
            XCTAssertEqual(d, src, a)
        }
    }

    func testKnownGzipSample() async throws {
        let d = try await T.text(CompressTool.self, "H4sIAAAAAAAC/3PKLMlJLMlIVUjOzy0oSi0uTi1WKEmtKNFTcMIlAwDtprcnMwAAAA==", ["mode": .string("decompress")])
        XCTAssertEqual(d, "Bitlathe compresses text. Bitlathe compresses text.")
    }

    func testZlibMatchesPythonBytes() async throws {
        // Python zlib.decompress of this stream yields "hello hello hello hello"
        let d = try await T.text(CompressTool.self, "78dacb48cdc9c957c8402701680308b1", ["mode": .string("decompress"), "algorithm": .string("zlib"), "wrap": .string("hex")])
        XCTAssertEqual(d, "hello hello hello hello")
    }

    func testHugeInputRoundTrip() async throws {
        let big = String(repeating: "0123456789abcdef lorem ipsum dolor sit amet\n", count: 50_000)   // ~2.2 MB
        for a in ["gzip", "zlib", "deflate", "lzfse", "lz4", "brotli"] {
            let c = try await T.text(CompressTool.self, big, ["algorithm": .string(a)])
            XCTAssertLessThan(c.count, big.count / 4, a)
            let d = try await T.text(CompressTool.self, c, ["mode": .string("decompress"), "algorithm": .string(a)])
            XCTAssertEqual(d, big, a)
        }
    }

    func testBinaryRoundTrip() async throws {
        let blob = pseudoRandomBytes(200_000)
        for a in algos {
            let c = try await AnyTool(CompressTool.self).run(ToolInput(.data(blob)), options: ["algorithm": .string(a), "wrap": .string("raw")])
            guard case .data(let cd) = c.payload else { return XCTFail("raw wrap should give data") }
            let d = try await AnyTool(CompressTool.self).run(ToolInput(.data(cd)), options: ["mode": .string("decompress"), "algorithm": .string(a)])
            guard case .data(let dd) = d.payload else { return XCTFail("random bytes should come back binary (\(a))") }
            XCTAssertEqual(dd, blob, a)
        }
    }

    func testErrors() async throws {
        let e0 = await T.error(CompressTool.self, "")
        XCTAssertEqual(e0, .emptyInput)
        let e = await T.error(CompressTool.self, "this is not compressed data at all", ["mode": .string("decompress"), "algorithm": .string("gzip")])
        XCTAssertNotNil(e)
        let e2 = await T.error(CompressTool.self, "AAAAAAAA", ["mode": .string("decompress"), "algorithm": .string("auto")])
        XCTAssertNotNil(e2)
    }
}

final class BinaryDecodeTests: XCTestCase {
    func testMessagePackKnownBytes() async throws {
        // {"name":"Bitlathe","tags":["mac","dev"]}
        let hex = "82 a4 6e 61 6d 65 a8 42 69 74 6c 61 74 68 65 a4 74 61 67 73 92 a3 6d 61 63 a3 64 65 76"
        let j = try await T.text(BinaryDecodeTool.self, hex, ["format": .string("msgpack")])
        let v = try JSONParser.parse(j)
        XCTAssertEqual(JSONSerializer.string(v, options: .minified).filter { !$0.isWhitespace }, #"{"name":"Bitlathe","tags":["mac","dev"]}"#)
    }

    func testCBORRFC8949Appendix() async throws {
        // RFC 8949 Appendix A: 1000000 = 1a000f4240, "IETF" = 6449455446, [1,2,3] = 83010203, {"a":1,"b":[2,3]} = a26161016162820203
        func dec(_ h: String) async throws -> String { try await T.text(BinaryDecodeTool.self, h, ["format": .string("cbor")]).filter { !$0.isWhitespace } }
        try await AEq(try await dec("a26161016162820203"), #"{"a":1,"b":[2,3]}"#)
        try await AEq(try await dec("83010203"), "[1,2,3]")
        try await AEq(try await dec("6449455446"), #""IETF""#)
        try await AEq(try await dec("1a000f4240"), "1000000")
    }

    func testEncodeDecodeRoundTrip() async throws {
        let json = #"{"id":7,"name":"Ada ✓ 😀","ok":true,"nil":null,"pi":3.5,"neg":-129,"big":70000,"list":[1,[2,[3]],{"k":"v"}],"empty":{},"es":[]}"#
        for fmt in ["msgpack", "cbor"] {
            for wrap in ["hex", "base64"] {
                let enc = try await T.text(BinaryDecodeTool.self, json, ["mode": .string("encode"), "format": .string(fmt), "wrap": .string(wrap)])
                let back = try await T.text(BinaryDecodeTool.self, enc, ["format": .string(fmt), "wrap": .string(wrap)])
                XCTAssertEqual(try JSONParser.parse(back), try JSONParser.parse(json), "\(fmt)/\(wrap)")
            }
        }
    }

    func testLargeRoundTrip() async throws {
        let items = (0..<20_000).map { #"{"i":\#($0),"s":"item \#($0) é"}"# }.joined(separator: ",")
        let json = "[\(items)]"
        for fmt in ["msgpack", "cbor"] {
            let enc = try await T.text(BinaryDecodeTool.self, json, ["mode": .string("encode"), "format": .string(fmt), "wrap": .string("hex")])
            let back = try await T.text(BinaryDecodeTool.self, enc, ["format": .string(fmt), "wrap": .string("hex")])
            XCTAssertEqual(try JSONParser.parse(back), try JSONParser.parse(json))
        }
    }

    func testProtobufSchemaless() async throws {
        let out = try await T.text(BinaryDecodeTool.self, "0a03416461 10 2a 1a 05 68656c6c6f", ["format": .string("protobuf")])
        XCTAssertTrue(out.contains("Ada"))
        XCTAssertTrue(out.contains("42"))
    }

    func testErrors() async throws {
        let e0 = await T.error(BinaryDecodeTool.self, "")
        XCTAssertEqual(e0, .emptyInput)
        let trunc = await T.error(BinaryDecodeTool.self, "82a46e616d65", ["format": .string("msgpack")])
        XCTAssertNotNil(trunc)
        let notHex = await T.error(BinaryDecodeTool.self, "zzzz!!", [:])
        XCTAssertNotNil(notHex)
        let badJSON = await T.error(BinaryDecodeTool.self, "{\"a\": }", ["mode": .string("encode")])
        XCTAssertNotNil(badJSON?.line)
        let pb = await T.error(BinaryDecodeTool.self, "{}", ["mode": .string("encode"), "format": .string("protobuf")])
        XCTAssertNotNil(pb)
    }
}

final class StringEscapeTests: XCTestCase {
    func testLanguagesEscapeAndUnescape() async throws {
        let src = "She said \"hi\" — it's a C:\\path\nwith a newline"
        for lang in ["json", "swift", "javascript", "python", "go", "java", "c"] {
            let e = try await T.text(StringEscapeTool.self, src, ["language": .string(lang)])
            XCTAssertFalse(e.contains("\n"), "\(lang) should escape newline")
            let back = try await T.text(StringEscapeTool.self, e, ["mode": .string("unescape"), "language": .string(lang)])
            XCTAssertEqual(back, src, lang)
        }
    }

    func testJSONMatchesSerializer() async throws {
        let src = "a\"b\\c\n\t/é😀"
        let e = try await T.text(StringEscapeTool.self, src, ["language": .string("json")])
        let parsed = try JSONParser.parse(e)
        XCTAssertEqual(parsed, .string(src))
        try await AEq(try await T.text(StringEscapeTool.self, "a\"b", ["language": .string("json"), "quotes": .bool(false)]), "a\\\"b")
    }

    func testSQLAndShellQuoting() async throws {
        try await AEq(try await T.text(StringEscapeTool.self, "it's", ["language": .string("sql")]), "'it''s'")
        let sh = try await T.text(StringEscapeTool.self, "it's $x", ["language": .string("shell")])
        XCTAssertEqual(sh, "'it'\\''s $x'")
    }

    func testAllLanguagesRunOnUnicode() async throws {
        let langs = ["json", "swift", "javascript", "python", "go", "java", "c", "sql", "shell", "powershell", "regex", "csv", "html", "xml", "yaml", "php"]
        for l in langs {
            let e = try await T.text(StringEscapeTool.self, unicodeSample + "\n\"'<&>$\\", ["language": .string(l)])
            XCTAssertFalse(e.isEmpty, l)
        }
    }

    func testEmpty() async throws {
        let e = await T.error(StringEscapeTool.self, "")
        XCTAssertNotNil(e)
    }
}
