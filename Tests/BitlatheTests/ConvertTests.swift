import XCTest
import BitlatheCore
@testable import BitlatheTools

private func opt(_ k: String, _ v: String) -> OptionValues { [k: .string(v)] }

private let sampleDoc = #"{"name":"Bitlathe 日本語 😀","version":1.5,"count":42,"neg":-7,"ok":true,"off":false,"tags":["mac","dev",""],"nested":{"a":{"b":[1,2,{"c":"d"}]}},"empty_obj":{},"empty_arr":[],"quote":"He said \"hi\"\nnew line\ttab"}"#

final class StructuredRoundTripTests: XCTestCase {
    private func json(_ s: String) throws -> JSONValue { try JSONParser.parse(s) }
    /// Key-order-insensitive comparison (TOML tables and plist dictionaries do not preserve order).
    private func assertSame(_ a: String, _ b: String, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try json(a).sortedKeys(), try json(b).sortedKeys(), msg, file: file, line: line)
    }

    func testJSONYAMLJSON() async throws {
        for indent in ["2", "4"] {
            for sort in [false, true] {
                let yaml = try await T.text(YAMLJSONTool.self, sampleDoc, ["direction": .string("json2yaml"), "indent": .string(indent), "sortKeys": .bool(sort)])
                let back = try await T.text(YAMLJSONTool.self, yaml, opt("direction", "yaml2json"))
                let expected = try json(sampleDoc)
                XCTAssertEqual(try json(back), sort ? expected.sortedKeys() : expected, "indent \(indent) sort \(sort)\n\(yaml)")
            }
        }
    }

    func testYAMLTrickyStringsSurvive() async throws {
        let tricky = ##"{"a":"true","b":"null","c":"123","d":"1.5","e":"yes","f":"","g":" lead","h":"colon: inside","i":"# hash","j":"- dash","k":"*star","l":"@at","m":"0x1F","n":"line1\nline2\n","o":"[x]","p":"{y}","q":"~"}"##
        let yaml = try await T.text(YAMLJSONTool.self, tricky, opt("direction", "json2yaml"))
        let back = try await T.text(YAMLJSONTool.self, yaml, opt("direction", "yaml2json"))
        XCTAssertEqual(try json(back), try json(tricky), yaml)
    }

    func testYAMLToJSONKnownMapping() async throws {
        let y = "name: Bitlathe\nfeatures:\n  - fast\n  - offline\nversion: 1.0\nstable: true\nnothing: ~\nanchors: &a\n  x: 1\n"
        let out = try await T.text(YAMLJSONTool.self, y, opt("direction", "yaml2json"))
        let v = try json(out)
        XCTAssertEqual(v["name"], .string("Bitlathe"))
        XCTAssertEqual(v["features"], try json(#"["fast","offline"]"#))
        XCTAssertEqual(v["stable"], .bool(true))
        XCTAssertEqual(v["nothing"], .null)
        let multi = try await T.text(YAMLJSONTool.self, "a: 1\n---\nb: 2", opt("direction", "yaml2json"))
        XCTAssertEqual(try json(multi), try json(#"[{"a":1},{"b":2}]"#))
    }

    func testYAMLErrors() async throws {
        let e = await T.error(YAMLJSONTool.self, "a: [1\nb: 2", opt("direction", "yaml2json"))
        XCTAssertNotNil(e?.line)
        let e2 = await T.error(YAMLJSONTool.self, "{\"a\": }", opt("direction", "json2yaml"))
        XCTAssertNotNil(e2?.line)
        let e3 = await T.error(YAMLJSONTool.self, "")
        XCTAssertEqual(e3, .emptyInput)
    }

    func testJSONTOMLJSON() async throws {
        // TOML has no null: use a null-free document.
        let doc = #"{"title":"TOML 日本語 😀","count":42,"pi":3.14,"neg":-1,"ok":true,"tags":["a","b"],"owner":{"name":"Tom","dob":"1979-05-27"},"db":{"ports":[8000,8001],"conn":{"max":5}},"quote":"a \"b\"\nc\\d"}"#
        let toml = try await T.text(JSONTOMLTool.self, doc, opt("direction", "json2toml"))
        let back = try await T.text(JSONTOMLTool.self, toml, opt("direction", "toml2json"))
        try assertSame(back, doc, toml)
    }

    func testTOMLToJSONSpecSample() async throws {
        let toml = "# comment\ntitle = \"TOML Example\"\n\n[owner]\nname = \"Tom\"\n\n[database]\nenabled = true\nports = [ 8000, 8001, 8002 ]\ndata = [ [\"delta\", \"phi\"], [3.14] ]\n\n[[products]]\nname = \"Hammer\"\n\n[[products]]\nname = \"Nail\"\n"
        let out = try await T.text(JSONTOMLTool.self, toml, opt("direction", "toml2json"))
        let expected = #"{"title":"TOML Example","owner":{"name":"Tom"},"database":{"enabled":true,"ports":[8000,8001,8002],"data":[["delta","phi"],[3.14]]},"products":[{"name":"Hammer"},{"name":"Nail"}]}"#
        try assertSame(out, expected)
    }

    func testTOMLErrors() async throws {
        let e = await T.error(JSONTOMLTool.self, "a = \nb = 2", opt("direction", "toml2json"))
        XCTAssertEqual(e?.line, 1)
        // TOML has no null: the key is omitted and the user is told.
        let nullOut = try await T.run(JSONTOMLTool.self, #"{"a":null,"b":[1,{"c":null}],"d":1}"#, opt("direction", "json2toml"))
        XCTAssertFalse(nullOut.text.contains("a ="))
        XCTAssertEqual(nullOut.warnings.count, 1)
        XCTAssertTrue(nullOut.warnings[0].contains("2 null values"), nullOut.warnings[0])
        let e3 = await T.error(JSONTOMLTool.self, "")
        XCTAssertEqual(e3, .emptyInput)
    }

    func testJSONXMLJSON() async throws {
        let doc = ##"{"note":{"@priority":"high","to":"Ada 日本語 😀","body":"a < b & c > d","items":{"item":["x","y","z"]},"meta":{"@k":"v","#text":"hi"}}}"##
        let xml = try await T.text(JSONXMLTool.self, doc, opt("direction", "json2xml"))
        XCTAssertTrue(xml.contains("&lt;") && xml.contains("&amp;"), xml)
        let back = try await T.text(JSONXMLTool.self, xml, opt("direction", "xml2json"))
        XCTAssertEqual(try json(back), try json(doc), xml)
    }

    func testXMLToJSONSample() async throws {
        let xml = "<library name=\"Main\"><book id=\"1\"><title>Dune</title><year>1965</year></book><book id=\"2\"><title>Emma</title></book></library>"
        let v = try json(try await T.text(JSONXMLTool.self, xml, opt("direction", "xml2json")))
        XCTAssertEqual(v["library"]?["@name"], .string("Main"))
        XCTAssertEqual(v["library"]?["book"]?.arrayValue?.count, 2)
        XCTAssertEqual(v["library"]?["book"]?.arrayValue?[1]["title"], .string("Emma"))
    }

    func testXMLErrors() async throws {
        let e = await T.error(JSONXMLTool.self, "<a><b></a>", opt("direction", "xml2json"))
        XCTAssertEqual(e?.line, 1)
        let e2 = await T.error(JSONXMLTool.self, "{bad", opt("direction", "json2xml"))
        XCTAssertNotNil(e2?.line)
    }

    func testJSONPlistJSON() async throws {
        let doc = #"{"CFBundleName":"Bitlathe 日本語 😀","Version":1,"Pi":1.5,"Sandboxed":true,"Off":false,"Features":["a","b"],"Nested":{"k":{"z":[1,2]}}}"#
        for fmt in ["xml", "binary"] {
            let out = try await AnyTool(JSONPlistTool.self).run(text: doc, options: ["direction": .string("json2plist"), "format": .string(fmt)])
            let back: ToolOutput
            if fmt == "binary" {
                guard case .data(let d) = out.payload else { return XCTFail("binary plist should be data") }
                XCTAssertTrue(d.starts(with: Array("bplist".utf8)))
                back = try await AnyTool(JSONPlistTool.self).run(ToolInput(.data(d)))
            } else {
                XCTAssertTrue(out.text.contains("<plist version=\"1.0\">"))
                back = try await AnyTool(JSONPlistTool.self).run(text: out.text, options: opt("direction", "plist2json"))
            }
            try assertSame(back.text, doc, fmt)
        }
    }

    func testPlistErrors() async throws {
        let nullErr = await T.error(JSONPlistTool.self, #"{"a":null}"#, opt("direction", "json2plist"))
        XCTAssertNotNil(nullErr)
        let bad = await T.error(JSONPlistTool.self, "<plist><dict><key>a</key></plist>", opt("direction", "plist2json"))
        XCTAssertNotNil(bad)
        let e = await T.error(JSONPlistTool.self, "")
        XCTAssertNotNil(e)
    }

    func testJSONQueryRoundTrip() async throws {
        let doc = #"{"page":2,"sort":"name","filter":{"status":"active","n":{"deep":true}},"tags":["a","b"],"q":"hello world & café 日本 😀 = ?","ratio":1.5}"#
        let q = try await T.text(JSONQueryStringTool.self, doc, opt("direction", "json2query"))
        XCTAssertFalse(q.contains(" "))
        let back = try await T.text(JSONQueryStringTool.self, q, opt("direction", "query2json"))
        try assertSame(back, doc, q)
    }

    func testQueryKnownVectors() async throws {
        let q = "page=2&sort=name&filter[status]=active&tags[]=a&tags[]=b&q=hello%20world&plus=a+b"
        let v = try json(try await T.text(JSONQueryStringTool.self, q, opt("direction", "query2json")))
        XCTAssertEqual(v["page"], .number("2"))
        XCTAssertEqual(v["filter"]?["status"], .string("active"))
        XCTAssertEqual(v["tags"], try json(#"["a","b"]"#))
        XCTAssertEqual(v["q"], .string("hello world"))
        XCTAssertEqual(v["plus"], .string("a b"))
        let untyped = try json(try await T.text(JSONQueryStringTool.self, "a=1&b=true", ["direction": .string("query2json"), "typed": .bool(false)]))
        XCTAssertEqual(untyped["a"], .string("1"))
        XCTAssertEqual(untyped["b"], .string("true"))
        let leading = try json(try await T.text(JSONQueryStringTool.self, "https://x.y/z?a=1&b=2#frag", opt("direction", "query2json")))
        XCTAssertEqual(leading["a"], .number("1"))
    }

    func testPHPArrayRoundTrip() async throws {
        let doc = #"{"name":"O'Reilly \\ 日本語 😀","count":3,"f":1.5,"t":true,"n":null,"list":[1,2,[3]],"map":{"k":{"z":"y"}},"e":[],"eo":[]}"#
        for syntax in ["short", "long"] {
            let php = try await T.text(PHPArrayJSONTool.self, doc, ["direction": .string("json2php"), "syntax": .string(syntax)])
            XCTAssertTrue(php.hasSuffix(";"))
            XCTAssertEqual(php.contains("array("), syntax == "long")
            let back = try await T.text(PHPArrayJSONTool.self, php, opt("direction", "php2json"))
            XCTAssertEqual(try json(back), try json(doc), php)
        }
    }

    func testPHPArrayKnownInput() async throws {
        let src = "<?php\n$cfg = [\n  'name' => 'Bitlathe',\n  \"tags\" => array('mac', 'dev'),\n  'meta' => array('version' => 1.5, 'stable' => TRUE, 'next' => NULL),\n  7 => 'seven', // comment\n];"
        let v = try json(try await T.text(PHPArrayJSONTool.self, src, opt("direction", "php2json")))
        XCTAssertEqual(v["name"], .string("Bitlathe"))
        XCTAssertEqual(v["tags"], try json(#"["mac","dev"]"#))
        XCTAssertEqual(v["meta"]?["stable"], .bool(true))
        XCTAssertEqual(v["meta"]?["next"], .null)
        let e = await T.error(PHPArrayJSONTool.self, "['a' => ", opt("direction", "php2json"))
        XCTAssertNotNil(e)
    }

    func testPHPSerializeKnownVectorsAndRoundTrip() async throws {
        // Reference strings produced by PHP's serialize().
        try await AEq(try await T.text(PHPSerializeTool.self, "\"héllo\"", opt("mode", "serialize")), "s:6:\"héllo\";")
        try await AEq(try await T.text(PHPSerializeTool.self, "[1,2]", opt("mode", "serialize")), "a:2:{i:0;i:1;i:1;i:2;}")
        try await AEq(try await T.text(PHPSerializeTool.self, "true", opt("mode", "serialize")), "b:1;")
        try await AEq(try await T.text(PHPSerializeTool.self, "null", opt("mode", "serialize")), "N;")
        try await AEq(try await T.text(PHPSerializeTool.self, "1.5", opt("mode", "serialize")), "d:1.5;")
        let doc = #"{"name":"Bitlathe 日本語 😀","ok":true,"ratio":0.5,"items":[1,2,{"k":null}],"nested":{"x":{"y":"z"}},"neg":-3}"#
        let ser = try await T.text(PHPSerializeTool.self, doc, opt("mode", "serialize"))
        let back = try await T.text(PHPSerializeTool.self, ser, opt("mode", "unserialize"))
        XCTAssertEqual(try json(back), try json(doc), ser)
        let obj = try json(try await T.text(PHPSerializeTool.self, #"O:8:"stdClass":2:{s:1:"a";i:1;s:1:"b";s:2:"hi";}"#, opt("mode", "unserialize")))
        XCTAssertEqual(obj["a"], .number("1"))
    }

    func testPHPSerializeErrors() async throws {
        let e = await T.error(PHPSerializeTool.self, "a:2:{i:0;i:1;}", opt("mode", "unserialize"))
        XCTAssertNotNil(e)
        let e2 = await T.error(PHPSerializeTool.self, "s:10:\"short\";", opt("mode", "unserialize"))
        XCTAssertNotNil(e2)
        let e3 = await T.error(PHPSerializeTool.self, "")
        XCTAssertEqual(e3, .emptyInput)
    }

    func testJSONCSVRoundTrip() async throws {
        let doc = #"[{"id":1,"name":"Ada, \"The\" Countess","note":"line1\nline2","uni":"日本語 😀","score":1.5,"ok":true},{"id":2,"name":"Linus","note":"x","uni":"é","score":2,"ok":false}]"#
        for delim in [",", ";", "\t", "|"] {
            let csv = try await T.text(JSONCSVTool.self, doc, ["direction": .string("json2csv"), "delimiter": .string(delim)])
            XCTAssertTrue(csv.hasPrefix("id\(delim)name"))
            let back = try await T.text(JSONCSVTool.self, csv, ["direction": .string("csv2json"), "delimiter": .string(delim)])
            XCTAssertEqual(try json(back), try json(doc), "delimiter \(delim)\n\(csv)")
        }
    }

    func testCSVKnownBehaviour() async throws {
        let v = try json(try await T.text(JSONCSVTool.self, "id,name,active\n1,Ada,true\n2,\"Smith, John\",false\n", opt("direction", "csv2json")))
        XCTAssertEqual(v, try json(#"[{"id":1,"name":"Ada","active":true},{"id":2,"name":"Smith, John","active":false}]"#))
        let untyped = try json(try await T.text(JSONCSVTool.self, "a,b\n1,true\n", ["direction": .string("csv2json"), "typed": .bool(false)]))
        XCTAssertEqual(untyped, try json(#"[{"a":"1","b":"true"}]"#))
        let crlf = try json(try await T.text(JSONCSVTool.self, "a,b\r\n1,2\r\n3,4\r\n", opt("direction", "csv2json")))
        XCTAssertEqual(crlf.arrayValue?.count, 2)
        let flat = try await T.text(JSONCSVTool.self, #"[{"id":1,"address":{"city":"Portland","zip":"97201"}}]"#, opt("direction", "json2csv"))
        XCTAssertEqual(flat, "id,address.city,address.zip\n1,Portland,97201")
        let missing = try await T.text(JSONCSVTool.self, #"[{"a":1},{"b":2}]"#, opt("direction", "json2csv"))
        XCTAssertEqual(missing, "a,b\n1,\n,2")
        let emptyCell = try json(try await T.text(JSONCSVTool.self, "a,b\n1,\n", ["direction": .string("csv2json"), "typed": .bool(false)]))
        XCTAssertEqual(emptyCell, try json(#"[{"a":"1","b":""}]"#))
        let hdrless = try json(try await T.text(JSONCSVTool.self, "1,2\n3,4", ["direction": .string("csv2json"), "header": .bool(false)]))
        XCTAssertEqual(hdrless.arrayValue?.count, 2)
    }

    func testCSVErrorsAndHuge() async throws {
        let e = await T.error(JSONCSVTool.self, "\"unterminated,1\n2,3", opt("direction", "csv2json"))
        XCTAssertNotNil(e)
        let e2 = await T.error(JSONCSVTool.self, "5", opt("direction", "json2csv"))
        XCTAssertNotNil(e2)
        let e3 = await T.error(JSONCSVTool.self, "")
        XCTAssertEqual(e3, .emptyInput)
        let rows = (0..<40_000).map { #"{"id":\#($0),"name":"user \#($0), é","v":\#($0).25}"# }.joined(separator: ",")
        let csv = try await T.text(JSONCSVTool.self, "[\(rows)]", opt("direction", "json2csv"))
        let back = try json(try await T.text(JSONCSVTool.self, csv, opt("direction", "csv2json")))
        XCTAssertEqual(back.arrayValue?.count, 40_000)
        XCTAssertEqual(back.arrayValue?[39_999]["name"], .string("user 39999, é"))
    }

    func testDirectionAutoDetect() async throws {
        let y = try await T.text(YAMLJSONTool.self, #"{"a":[1,2]}"#)
        XCTAssertEqual(y, "a:\n- 1\n- 2")
        let j = try await T.text(YAMLJSONTool.self, "a:\n- 1\n- 2")
        XCTAssertEqual(try json(j), try json(#"{"a":[1,2]}"#))
        let c = try await T.text(JSONCSVTool.self, #"[{"a":1}]"#)
        XCTAssertEqual(c, "a\n1")
    }
}

private extension JSONValue {
    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o.first { $0.key == key }?.value }
        return nil
    }
}

final class MiscConverterTests: XCTestCase {
    func testCaseConverterVariants() async throws {
        let out = try await T.run(CaseConverterTool.self, "userProfileImageURL")
        func facet(_ t: String) -> String? { out.facets.first { $0.title == t }?.payload.text }
        XCTAssertEqual(facet("camelCase"), "userProfileImageUrl")
        XCTAssertEqual(facet("PascalCase"), "UserProfileImageUrl")
        XCTAssertEqual(facet("snake_case"), "user_profile_image_url")
        XCTAssertEqual(facet("kebab-case"), "user-profile-image-url")
        XCTAssertEqual(facet("CONSTANT_CASE"), "USER_PROFILE_IMAGE_URL")
        XCTAssertEqual(facet("dot.case"), "user.profile.image.url")
        try await AEq(try await T.text(CaseConverterTool.self, "HTTP server_error-code now", ["target": .string("snake")]), "http_server_error_code_now")
        let multi = try await T.text(CaseConverterTool.self, "fooBar\nbaz_qux", ["target": .string("kebab")])
        XCTAssertEqual(multi, "foo-bar\nbaz-qux")
        let u = try await T.text(CaseConverterTool.self, "héllo wörld 日本", ["target": .string("pascal")])
        XCTAssertTrue(u.hasPrefix("HéLlo") || u.hasPrefix("Héllo"), u)
        let e = await T.error(CaseConverterTool.self, "")
        XCTAssertNotNil(e)
    }

    func testNumberBase() async throws {
        let out = try await T.run(NumberBaseTool.self, "255")
        func facet(_ t: String) -> String? { out.facets.first { $0.title == t }?.payload.text }
        XCTAssertEqual(facet("Hex"), "FF"); XCTAssertEqual(facet("Binary"), "11111111")
        XCTAssertEqual(facet("Octal"), "377"); XCTAssertEqual(facet("Decimal"), "255")
        let hex = try await T.run(NumberBaseTool.self, "0xDEADBEEF")
        XCTAssertEqual(hex.facets.first { $0.title == "Decimal" }?.payload.text, "3735928559")
        let neg = try await T.run(NumberBaseTool.self, "-42")
        XCTAssertEqual(neg.facets.first { $0.title == "Hex" }?.payload.text, "-2A")
        XCTAssertTrue(neg.metadata.contains { $0.label.contains("Two") && $0.value.contains("FFD6") })
        let bin = try await T.run(NumberBaseTool.self, "0b1010_1010")
        XCTAssertEqual(bin.facets.first { $0.title == "Decimal" }?.payload.text, "170")
        let big = try await T.run(NumberBaseTool.self, "ffffffffffffffff", ["inputBase": .string("16")])
        XCTAssertEqual(big.facets.first { $0.title == "Decimal" }?.payload.text, "18446744073709551615")
        let b36 = try await T.run(NumberBaseTool.self, "zz", ["inputBase": .string("36")])
        XCTAssertEqual(b36.facets.first { $0.title == "Decimal" }?.payload.text, "1295")
        let e = await T.error(NumberBaseTool.self, "zz", ["inputBase": .string("10")])
        XCTAssertTrue(e?.message.contains("not a valid digit") == true)
        let e2 = await T.error(NumberBaseTool.self, "")
        XCTAssertNotNil(e2)
    }

    func testHexTextRoundTrips() async throws {
        try await AEq(try await T.text(HexTextTool.self, "Hi é"), "48 69 20 c3 a9")
        try await AEq(try await T.text(HexTextTool.self, "48 69 20 c3 a9", ["mode": .string("decode")]), "Hi é")
        try await AEq(try await T.text(HexTextTool.self, "Hi", ["uppercase": .bool(true), "separator": .string("colon")]), "48:69")
        try await AEq(try await T.text(HexTextTool.self, "Hi", ["separator": .string("comma")]), "0x48, 0x69")
        try await AEq(try await T.text(HexTextTool.self, "Hi", ["separator": .string("escape")]), "\\x48\\x69")
        try await AEq(try await T.text(HexTextTool.self, "01001000 01101001", ["mode": .string("decode"), "format": .string("binary")]), "Hi")
        for fmt in ["hex", "binary", "decimal", "octal"] {
            for enc in ["utf8", "utf16", "utf16le"] {
                let o: OptionValues = ["format": .string(fmt), "encoding": .string(enc)]
                let e = try await T.text(HexTextTool.self, unicodeSample, o)
                var d = o; d["mode"] = .string("decode")
                try await AEq(try await T.text(HexTextTool.self, e, d), unicodeSample, "\(fmt)/\(enc)")
            }
        }
        let bad = await T.error(HexTextTool.self, "4g", ["mode": .string("decode")])
        XCTAssertNotNil(bad)
    }

    func testByteSizeAndUnits() async throws {
        let g = try await T.run(ByteSizeTool.self, "1.5 GB")
        func m(_ o: ToolOutput, _ k: String) -> String? { o.metadata.first { $0.label == k }?.value }
        XCTAssertEqual(m(g, "Bytes"), "1500000000")
        XCTAssertEqual(m(g, "Human (binary)"), "1.4 GiB")
        let mi = try await T.run(ByteSizeTool.self, "512 MiB")
        XCTAssertEqual(m(mi, "Bytes"), "536870912")
        XCTAssertEqual(m(mi, "GiB"), "0.5")
        let plain = try await T.run(ByteSizeTool.self, "1073741824")
        XCTAssertEqual(m(plain, "GiB"), "1")
        let d = try await T.run(UnitConverterTool.self, "90061001 ms")
        XCTAssertEqual(m(d, "ISO 8601"), "P1DT1H1M1S")
        XCTAssertEqual(m(d, "HH:MM:SS"), "25:01:01.001")
        let css = try await T.run(UnitConverterTool.self, "24px", ["kind": .string("css")])
        XCTAssertEqual(m(css, "pt"), "18")
        XCTAssertEqual(m(css, "rem (base 16)"), "1.5")
        let bad = await T.error(ByteSizeTool.self, "12 zorkbytes")
        XCTAssertNotNil(bad)
        let e = await T.error(UnitConverterTool.self, "")
        XCTAssertNotNil(e)
    }

    func testMarkdownHTML() async throws {
        let html = try await T.text(MarkdownHTMLTool.self, "# Hi\n\n**b** *i* `c`\n\n- a\n- b", opt("direction", "md2html"))
        XCTAssertEqual(html.trimmingCharacters(in: .whitespacesAndNewlines), "<h1>Hi</h1>\n<p><strong>b</strong> <em>i</em> <code>c</code></p>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>")
        let md = try await T.text(MarkdownHTMLTool.self, "<h2>T</h2><p>x <em>y</em></p>", opt("direction", "html2md"))
        XCTAssertEqual(md.trimmingCharacters(in: .whitespacesAndNewlines), "## T\n\nx *y*")
        let esc = try await T.text(MarkdownHTMLTool.self, "a < b & c 日本 😀", opt("direction", "md2html"))
        XCTAssertTrue(esc.contains("&lt;") && esc.contains("&amp;") && esc.contains("日本 😀"))
        let full = try await T.text(MarkdownHTMLTool.self, "# T", ["direction": .string("md2html"), "fullDocument": .bool(true)])
        XCTAssertTrue(full.contains("<html") && full.contains("<h1>T</h1>"))
        let e = await T.error(MarkdownHTMLTool.self, "")
        XCTAssertNotNil(e)
    }

    func testHTMLToJSX() async throws {
        let out = try await T.text(HTMLToJSXTool.self, "<div class=\"a\" style=\"color: red\"><input disabled><br></div>", ["component": .bool(false)])
        XCTAssertEqual(out, "<div className=\"a\" style={{color: 'red'}}>\n  <input disabled />\n  <br />\n</div>")
        let comp = try await T.text(HTMLToJSXTool.self, "<label for=\"x\" tabindex=\"1\">Hi</label>", ["name": .string("Foo"), "typescript": .bool(true)])
        XCTAssertTrue(comp.contains("Foo") && comp.contains("htmlFor=\"x\"") && comp.contains("tabIndex"), comp)
        let e = await T.error(HTMLToJSXTool.self, "")
        XCTAssertNotNil(e)
    }

    func testJSONToCode() async throws {
        let src = #"{"id":1,"name":"a","tags":["x"],"n":null,"nested":{"k":1.5}}"#
        let ts = try await T.text(JSONToCodeTool.self, src)
        XCTAssertTrue(ts.contains("export interface Root {") && ts.contains("id: number;") && ts.contains("tags: string[];") && ts.contains("nested: Nested;"), ts)
        for lang in ["swift", "go", "kotlin", "rust", "java", "python", "csharp", "typescript"] {
            let o = try await T.text(JSONToCodeTool.self, src, ["language": .string(lang)])
            XCTAssertTrue(o.contains("Nested"), "\(lang): \(o)")
        }
        let sw = try await T.text(JSONToCodeTool.self, src, ["language": .string("swift"), "naming": .string("camel")])
        XCTAssertTrue(sw.contains("struct Root: Codable") && sw.contains("let id: Int"))
        let e = await T.error(JSONToCodeTool.self, "{bad")
        XCTAssertNotNil(e?.line)
    }

    func testCurlConversions() async throws {
        let py = try await T.text(CurlToCodeTool.self, "curl -X POST https://a.b/c -H 'X-A: 1' -d 'q=1'", ["target": .string("python")])
        XCTAssertTrue(py.contains("requests.post(url") && py.contains("\"X-A\": \"1\"") && py.contains("https://a.b/c"))
        let curl = try await T.text(CodeToCurlTool.self, "POST /v1 HTTP/1.1\nHost: a.b\nContent-Type: text/plain\n\nhi")
        XCTAssertEqual(curl, "curl \\\n  -X POST \\\n  -H 'Content-Type: text/plain' \\\n  -d hi \\\n  https://a.b/v1")
        let e = await T.error(CurlToCodeTool.self, "not a curl command")
        XCTAssertNotNil(e)
        let e2 = await T.error(CurlToCodeTool.self, "")
        XCTAssertNotNil(e2)
    }

    func testSVGConversions() async throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0\"/></svg>"
        let css = try await T.text(SVGToCSSTool.self, svg)
        XCTAssertTrue(css.hasPrefix(".icon {\n  background-image: url(\"data:image/svg+xml,%3Csvg"))
        let b64 = try await T.text(SVGToCSSTool.self, svg, ["encoding": .string("base64"), "output": .string("uri")])
        XCTAssertTrue(b64.hasPrefix("data:image/svg+xml;base64,"))
        let payload = String(b64.dropFirst("data:image/svg+xml;base64,".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"')\n;"))
        XCTAssertEqual(String(data: Data(base64Encoded: payload) ?? Data(), encoding: .utf8), svg)
        let sw = try await T.text(SVGToCodeTool.self, "<svg viewBox=\"0 0 24 24\"><rect x=\"2\" y=\"2\" width=\"20\" height=\"20\"/></svg>")
        XCTAssertTrue(sw.contains("Shape"))
        let e = await T.error(SVGToCSSTool.self, "<div>not svg</div>")
        XCTAssertEqual(e?.message, "Input is not an SVG")
        let e2 = await T.error(SVGToCodeTool.self, "<svg><path></svg>")
        XCTAssertNotNil(e2?.line)
    }

    func testCSVViewer() async throws {
        let out = try await T.run(CSVViewerTool.self, "a,b\n1,\"x,y\"\n2,\"multi\nline\"\n")
        XCTAssertTrue(out.metadata.contains { $0.label == "Rows" && $0.value == "2" })
        XCTAssertTrue(out.metadata.contains { $0.label == "Columns" && $0.value == "2" })
        let semi = try await T.run(CSVViewerTool.self, "a;b\n1;2\n")
        XCTAssertTrue(semi.metadata.contains { $0.label == "Delimiter" && $0.value == ";" })
        let big = "id,v\n" + (0..<100_000).map { "\($0),\($0 * 2)" }.joined(separator: "\n")
        let bigOut = try await T.run(CSVViewerTool.self, big)
        XCTAssertTrue(bigOut.metadata.contains { $0.label == "Rows" && $0.value == "100000" })
        let e = await T.error(CSVViewerTool.self, "")
        XCTAssertNotNil(e)
    }
}
