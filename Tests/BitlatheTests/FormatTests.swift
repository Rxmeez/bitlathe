import XCTest
import BitlatheCore
@testable import BitlatheTools

final class JSONFormatTests: XCTestCase {
    func testFormatDefaultsAndIndent() async throws {
        let src = #"{"b":[1,2,{"c":null}],"a":"x"}"#
        try await AEq(try await T.text(JSONFormatTool.self, src),
                      "{\n  \"b\": [\n    1,\n    2,\n    {\n      \"c\": null\n    }\n  ],\n  \"a\": \"x\"\n}")
        let four = try await T.text(JSONFormatTool.self, #"{"a":[1]}"#, ["indent": .string("4")])
        XCTAssertEqual(four, "{\n    \"a\": [\n        1\n    ]\n}")
        let tab = try await T.text(JSONFormatTool.self, #"{"a":1}"#, ["indent": .string("tab")])
        XCTAssertEqual(tab, "{\n\t\"a\": 1\n}")
    }

    func testMinifyAndSortKeys() async throws {
        try await AEq(try await T.text(JSONFormatTool.self, "{ \"b\" : 1 ,\n \"a\" : [ 1 , 2 ] }", ["mode": .string("minify")]), #"{"b":1,"a":[1,2]}"#)
        try await AEq(try await T.text(JSONFormatTool.self, #"{"b":1,"a":{"d":1,"c":2}}"#, ["sortKeys": .bool(true), "mode": .string("minify")]), #"{"a":{"c":2,"d":1},"b":1}"#)
    }

    func testPreservesNumberLexemesAndKeyOrder() async throws {
        // Big integers and exponent forms must survive untouched (no Double round trip).
        let out = try await T.text(JSONFormatTool.self, #"{"z":12345678901234567890123,"a":1.0,"e":1E+2,"neg":-0.0}"#, ["mode": .string("minify")])
        XCTAssertEqual(out, #"{"z":12345678901234567890123,"a":1.0,"e":1E+2,"neg":-0.0}"#)
    }

    func testUnicodeAndEscaping() async throws {
        let src = #"{"k":"é😀é \"q\" \\ \n"}"#
        let v = try JSONParser.parse(src)
        let out = try await T.text(JSONFormatTool.self, src, ["mode": .string("minify")])
        XCTAssertEqual(try JSONParser.parse(out), v)
        XCTAssertTrue(out.contains("é😀"))
        let esc = try await T.text(JSONFormatTool.self, #"{"a":"é😀/"}"#, ["escapeNonASCII": .bool(true), "escapeSlashes": .bool(true), "mode": .string("minify")])
        XCTAssertEqual(esc, "{\"a\":\"\\u00e9\\ud83d\\ude00\\/\"}")
        XCTAssertEqual(try JSONParser.parse(esc), try JSONParser.parse(#"{"a":"é😀/"}"#))
    }

    func testJSON5AndJSONC() async throws {
        let j5 = try await T.text(JSONFormatTool.self, "// c\n{a:'x', hex: 0xFF, trailing: [1,2,],}", ["inputMode": .string("json5")])
        let v = try JSONParser.parse(j5)
        XCTAssertEqual(v, try JSONParser.parse(#"{"a":"x","hex":255,"trailing":[1,2]}"#))
        let jc = try await T.text(JSONFormatTool.self, "/* c */ {\"a\": 1, // x\n \"b\": [1,],}", ["inputMode": .string("jsonc")])
        XCTAssertEqual(try JSONParser.parse(jc), try JSONParser.parse(#"{"a":1,"b":[1]}"#))
    }

    func testErrorsHaveLineAndColumn() async throws {
        let e1 = await T.error(JSONFormatTool.self, #"{"a": 1, "b": [1,2,], "c": tru}"#)
        XCTAssertEqual(e1?.line, 1); XCTAssertEqual(e1?.column, 20)
        XCTAssertTrue(e1?.message.contains("Trailing comma") == true, e1?.message ?? "")
        let e2 = await T.error(JSONFormatTool.self, "{\n  \"a\": 1,\n  \"b\": [1,\n  2\n  oops]\n}")
        XCTAssertEqual(e2?.line, 5); XCTAssertEqual(e2?.column, 3)
        let e3 = await T.error(JSONFormatTool.self, #"{"a":1}x"#)
        XCTAssertEqual(e3?.line, 1); XCTAssertEqual(e3?.column, 8)
        let e4 = await T.error(JSONFormatTool.self, #"{"a": "unterminated"#)
        XCTAssertNotNil(e4?.line)
        let e5 = await T.error(JSONFormatTool.self, "  \n ")
        XCTAssertEqual(e5, .emptyInput)
        let e6 = await T.error(JSONFormatTool.self, "{'a':1}")
        XCTAssertNotNil(e6)
        XCTAssertTrue(e6?.hint?.contains("JSON5") == true, "hint should point to JSON5: \(e6?.hint ?? "nil")")
    }

    func testQueryAndSchema() async throws {
        let q = try await T.run(JSONFormatTool.self, #"{"a":[{"id":1},{"id":2}]}"#, ["query": .string("$.a[*].id")])
        XCTAssertEqual(try JSONParser.parse(q.text), try JSONParser.parse("[1,2]"))
        XCTAssertTrue(q.metadata.contains { $0.label == "Matches" && $0.value == "2" })
        let schema = #"{"type":"object","properties":{"a":{"type":"string"}},"required":["a","b"]}"#
        let bad = try await T.run(JSONFormatTool.self, #"{"a":1}"#, ["schema": .string(schema)])
        XCTAssertEqual(bad.isValid, false)
        XCTAssertFalse(bad.warnings.isEmpty)
        let ok = try await T.run(JSONFormatTool.self, #"{"a":"s","b":1}"#, ["schema": .string(schema)])
        XCTAssertEqual(ok.isValid, true)
        XCTAssertTrue(ok.warnings.isEmpty)
        let brokenSchema = await T.error(JSONFormatTool.self, "{}", ["schema": .string("{")])
        XCTAssertTrue(brokenSchema?.message.hasPrefix("Schema:") == true)
    }

    func testValidateModeKeepsInput() async throws {
        let src = "{ \"a\":   1 }"
        let out = try await T.run(JSONFormatTool.self, src, ["mode": .string("validate")])
        XCTAssertEqual(out.text, src)
        XCTAssertEqual(out.isValid, true)
    }

    func testScalarsAndDeepNesting() async throws {
        for s in ["1", "\"x\"", "null", "true", "[]", "{}"] {
            try await AEq(try await T.text(JSONFormatTool.self, s), s)
        }
        let deep = String(repeating: "[", count: 100) + String(repeating: "]", count: 100)
        let out = try await T.text(JSONFormatTool.self, deep, ["mode": .string("minify")])
        XCTAssertEqual(out, deep)
    }

    func testHugeDocument() async throws {
        let rows = (0..<25_000).map { #"{"id":\#($0),"name":"user \#($0) é😀","tags":["a","b"],"score":\#($0).5,"ok":true,"n":null}"# }
        let src = "[" + rows.joined(separator: ",") + "]"
        XCTAssertGreaterThan(src.utf8.count, 1_900_000)
        let pretty = try await T.text(JSONFormatTool.self, src)
        let mini = try await T.text(JSONFormatTool.self, pretty, ["mode": .string("minify")])
        XCTAssertEqual(mini, src)
    }
}

final class YAMLTOMLXMLFormatTests: XCTestCase {
    func testYAMLFormat() async throws {
        let out = try await T.text(YAMLFormatTool.self, "a:   1\nb:\n    - x\n    - {c: d}\n")
        XCTAssertEqual(out, "a: 1\nb:\n- x\n- c: d")
        let multi = try await T.text(YAMLFormatTool.self, "a: 1\n---\nz: 2")
        XCTAssertEqual(multi, "---\na: 1\n---\nz: 2")
        let sorted = try await T.text(YAMLFormatTool.self, "b: 1\na: 2", ["sortKeys": .bool(true)])
        XCTAssertEqual(sorted, "a: 2\nb: 1")
        let idem = try await T.text(YAMLFormatTool.self, out)
        XCTAssertEqual(idem, out)
    }

    func testYAMLUnicodeAndQuoting() async throws {
        let src = "name: \"日本語 😀\"\nversion: \"1.0\"\nflag: \"true\"\nempty: ''\nmulti: |\n  line1\n  line2\n"
        let out = try await T.text(YAMLFormatTool.self, src)
        let a = try YAMLBridge.parseOne(src), b = try YAMLBridge.parseOne(out)
        XCTAssertEqual(a, b)
        XCTAssertTrue(out.contains("日本語"))   // libyaml may escape astral characters, which is still valid YAML (checked by the equality above)
    }

    /// Regression: Yams' sequence swallows errors; invalid YAML used to produce empty output instead of an error.
    func testYAMLErrorsHaveLocation() async throws {
        let e = await T.error(YAMLFormatTool.self, "a: [1\nb: 2")
        XCTAssertNotNil(e?.line)
        let e2 = await T.error(YAMLFormatTool.self, "a: 1\n b: 2\n")
        XCTAssertNotNil(e2)
        let e3 = await T.error(YAMLFormatTool.self, "a: &x 1\nb: *y")
        XCTAssertNotNil(e3)
        let e4 = await T.error(YAMLFormatTool.self, "  \n")
        XCTAssertEqual(e4, .emptyInput)
        let e5 = await T.error(YAMLFormatTool.self, "key: [unclosed\n  - x: {")
        XCTAssertNotNil(e5?.line)
    }

    func testTOMLFormat() async throws {
        let out = try await T.text(TOMLFormatTool.self, "[package]\nname=\"x\"\nv = 1\n[dependencies]\nserde = { version = \"1\" }")
        XCTAssertTrue(out.contains("[package]"))
        XCTAssertEqual(try TOMLBridge.parse(out), try TOMLBridge.parse("[package]\nname=\"x\"\nv = 1\n[dependencies]\nserde = { version = \"1\" }"))
        let e = await T.error(TOMLFormatTool.self, "a = \nb = 2")
        XCTAssertEqual(e?.line, 1)
        XCTAssertEqual(e?.column, 5)
        let e2 = await T.error(TOMLFormatTool.self, "a = 1\na = 2")
        XCTAssertNotNil(e2)
        let e3 = await T.error(TOMLFormatTool.self, "")
        XCTAssertEqual(e3, .emptyInput)
    }

    func testXMLFormatAndMinify() async throws {
        let src = "<a x='1'><b>t</b><c/></a>"
        let out = try await T.text(XMLFormatTool.self, src)
        XCTAssertEqual(out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<a x=\"1\">\n  <b>t</b>\n  <c/>\n</a>")
        let mini = try await T.text(XMLFormatTool.self, out, ["mode": .string("minify")])
        XCTAssertFalse(mini.contains("\n"))
        XCTAssertTrue(mini.hasSuffix("<a x=\"1\"><b>t</b><c/></a>"), mini)
        let noDecl = try await T.text(XMLFormatTool.self, src, ["declaration": .bool(false), "indent": .string("4")])
        XCTAssertEqual(noDecl, "<a x=\"1\">\n    <b>t</b>\n    <c/>\n</a>")
    }

    func testXMLUnicodeAndEntities() async throws {
        let out = try await T.text(XMLFormatTool.self, "<r><t>日本 😀 &amp; &lt;x&gt;</t></r>")
        XCTAssertTrue(out.contains("日本 😀 &amp; &lt;x&gt;"))
    }

    func testXMLErrors() async throws {
        let e = await T.error(XMLFormatTool.self, "<a><b></a>")
        XCTAssertEqual(e?.line, 1)
        XCTAssertTrue(e?.message.contains("mismatch") == true, e?.message ?? "")
        let e2 = await T.error(XMLFormatTool.self, "<a>\n<b>\n</c>\n</a>")
        // libxml names the unclosed element's line (2) in its message; the closing tag is on line 3.
        XCTAssertTrue([2, 3].contains(e2?.line ?? 0), "line \(e2?.line.map(String.init) ?? "nil")")
        let e3 = await T.error(XMLFormatTool.self, "")
        XCTAssertEqual(e3, .emptyInput)
    }
}

final class WebFormatTests: XCTestCase {
    func testCSS() async throws {
        let out = try await T.text(CSSFormatTool.self, ".a{color:red;margin:0 auto}@media (max-width:1px){.b{x:y}}")
        XCTAssertEqual(out.trimmingCharacters(in: .newlines), ".a {\n  color: red;\n  margin: 0 auto;\n}\n@media (max-width: 1px) {\n  .b {\n    x: y;\n  }\n}")
        let mini = try await T.text(CSSFormatTool.self, ".a { color : red ; }", ["mode": .string("minify")])
        XCTAssertEqual(mini, ".a{color:red}")
        let again = try await T.text(CSSFormatTool.self, out)
        XCTAssertEqual(again, out)
        let u = try await T.text(CSSFormatTool.self, ".ü::after{content:\"日本 😀\"}")
        XCTAssertTrue(u.contains("\"日本 😀\""))
        let e = await T.error(CSSFormatTool.self, ".a{color:red")
        XCTAssertEqual(e?.line, 1)
    }

    func testSCSSAndLESS() async throws {
        let s = try await T.text(SCSSFormatTool.self, "$c:#333;.a{&:hover{color:$c}}")
        XCTAssertEqual(s.trimmingCharacters(in: .newlines), "$c: #333;\n.a {\n  &:hover {\n    color: $c;\n  }\n}")
        let l = try await T.text(LESSFormatTool.self, "@c:#333;.a{.b{color:@c}}")
        XCTAssertEqual(l.trimmingCharacters(in: .newlines), "@c: #333;\n.a {\n  .b {\n    color: @c;\n  }\n}")
    }

    func testJavaScriptAndTypeScript() async throws {
        let js = try await T.text(JavaScriptFormatTool.self, "const a=1;function f(x){return x+1}")
        XCTAssertEqual(js.trimmingCharacters(in: .newlines), "const a = 1;\nfunction f(x) {\n  return x + 1;\n}")
        let again = try await T.text(JavaScriptFormatTool.self, js)
        XCTAssertEqual(again, js)
        let mini = try await T.text(JavaScriptFormatTool.self, js, ["mode": .string("minify")])
        XCTAssertLessThan(mini.count, js.count)
        XCTAssertFalse(mini.contains("\n"))
        let ts = try await T.text(TypeScriptFormatTool.self, "interface A{x:number}")
        XCTAssertEqual(ts.trimmingCharacters(in: .newlines), "interface A {\n  x: number;\n}")
        let e = await T.error(JavaScriptFormatTool.self, "function(){")
        XCTAssertEqual(e?.line, 1)
        let u = try await T.text(JavaScriptFormatTool.self, "const s='日本 😀 é'")
        XCTAssertTrue(u.contains("日本 😀 é"))
    }

    func testHTMLAndERB() async throws {
        let h = try await T.text(HTMLFormatTool.self, "<ul><li>a</li><li>b</li></ul><p>hi <b>x</b></p>")
        XCTAssertEqual(h.trimmingCharacters(in: .newlines), "<ul>\n  <li>a</li>\n  <li>b</li>\n</ul>\n<p>hi <b>x</b></p>")
        let mini = try await T.text(HTMLFormatTool.self, "<ul>\n  <li>a</li>\n</ul>", ["mode": .string("minify")])
        XCTAssertEqual(mini, "<ul><li>a</li></ul>")
        let erb = try await T.text(ERBFormatTool.self, "<div><% if x %><p><%= y %></p><% end %></div>")
        XCTAssertTrue(erb.contains("<% if x %>") && erb.contains("<%= y %>") && erb.contains("<% end %>"))
        let big = String(repeating: "<div class=\"r\"><span>日本 😀</span></div>", count: 2_000)
        let out = try await T.text(HTMLFormatTool.self, big)
        XCTAssertTrue(out.contains("日本 😀"))
    }

    func testGraphQL() async throws {
        let g = try await T.text(GraphQLFormatTool.self, "query Q($id:ID!){user(id:$id){id name}}")
        XCTAssertEqual(g.trimmingCharacters(in: .newlines), "query Q($id: ID!) {\n  user(id: $id) {\n    id\n    name\n  }\n}")
        let e = await T.error(GraphQLFormatTool.self, "query { a ")
        XCTAssertEqual(e?.line, 1)
        XCTAssertEqual(e?.column, 11)
    }

    func testEmptyInputsRejected() async throws {
        let e1 = await T.error(CSSFormatTool.self, "")
        XCTAssertNotNil(e1)
        let e2 = await T.error(HTMLFormatTool.self, "")
        XCTAssertNotNil(e2)
        let e3 = await T.error(JavaScriptFormatTool.self, "   ")
        XCTAssertNotNil(e3)
    }
}

final class SQLAndLineToolsTests: XCTestCase {
    func testSQL() async throws {
        let out = try await T.text(SQLFormatTool.self, "select a,b from t where x=1 and y=2")
        XCTAssertEqual(out, "SELECT\n  a,\n  b\nFROM\n  t\nWHERE\n  x = 1\n  AND y = 2")
        let lower = try await T.text(SQLFormatTool.self, "SELECT a FROM t", ["keywordCase": .string("lower")])
        XCTAssertTrue(lower.contains("select") && lower.contains("from"))
        let two = try await T.text(SQLFormatTool.self, "select 1; select 2")
        XCTAssertEqual(two.components(separatedBy: "SELECT").count - 1, 2)
        let u = try await T.text(SQLFormatTool.self, "select '日本 😀 it''s' as x")
        XCTAssertTrue(u.contains("'日本 😀 it''s'"))
        let e = await T.error(SQLFormatTool.self, "")
        XCTAssertNotNil(e)
    }

    func testLineTools() async throws {
        try await AEq(try await T.text(LineToolsTool.self, "b\na\nb"), "a\nb\nb")
        try await AEq(try await T.text(LineToolsTool.self, "b\na\nb", ["operation": .string("dedupe")]), "b\na")
        try await AEq(try await T.text(LineToolsTool.self, "b\na\nb", ["operation": .string("reverse")]), "b\na\nb")
        try await AEq(try await T.text(LineToolsTool.self, "b\na\nb", ["operation": .string("number")]), "1  b\n2  a\n3  b")
        try await AEq(try await T.text(LineToolsTool.self, "b\na\nb", ["operation": .string("join")]), "b, a, b")
        // natural sort puts file2 before file10
        let nat = try await T.text(LineToolsTool.self, "file10\nfile2\nfile1", ["sortMode": .string("natural")])
        XCTAssertEqual(nat, "file1\nfile2\nfile10")
    }

    func testLineToolsLarge() async throws {
        let lines = (0..<200_000).map { "line \($0 % 5000) é" }.joined(separator: "\n")
        let out = try await T.text(LineToolsTool.self, lines, ["operation": .string("dedupe")])
        XCTAssertEqual(out.split(separator: "\n").count, 5000)
    }
}
