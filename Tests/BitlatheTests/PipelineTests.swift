import XCTest
import BitlatheCore
@testable import BitlatheTools

final class PipelineTests: XCTestCase {
    private let lookup: @Sendable (String) -> AnyTool? = { id in ToolCatalog.all.first { $0.id == id } }

    // MARK: parse

    func testParseExpression() throws {
        let p = try Pipeline.parse(expression: "base64.text mode=decode | compress.text mode=decompress level=9 | json.format sortKeys=true")
        XCTAssertEqual(p.steps.map(\.toolID), ["base64.text", "compress.text", "json.format"])
        XCTAssertEqual(p.steps[0].options, ["mode": .string("decode")])
        XCTAssertEqual(p.steps[1].options, ["mode": .string("decompress"), "level": .int(9)])
        XCTAssertEqual(p.steps[2].options, ["sortKeys": .bool(true)])
        XCTAssertTrue(p.steps.allSatisfy(\.enabled))
    }

    func testParseValueTypesAndFlags() throws {
        let p = try Pipeline.parse(expression: "a.b --verbose x=1 y=2.5 z=false w=hello")
        XCTAssertEqual(p.steps[0].options, ["verbose": .bool(true), "x": .int(1), "y": .double(2.5), "z": .bool(false), "w": .string("hello")])
        let loose = try Pipeline.parse(expression: "  one   |two|   three  x=1  ")
        XCTAssertEqual(loose.steps.map(\.toolID), ["one", "two", "three"])
        XCTAssertEqual(try Pipeline.parse(expression: "a | | b").steps.map(\.toolID), ["a", "b"], "empty segments are skipped")
    }

    func testParseErrorsAndName() {
        for bad in ["", "   ", " | | "] { XCTAssertThrowsError(try Pipeline.parse(expression: bad), "'\(bad)'") { XCTAssertTrue($0 is ToolError) } }
        XCTAssertEqual(try Pipeline.parse(expression: "a", name: "Mine").name, "Mine")
    }

    func testExpressionRoundTripSkipsDisabledSteps() throws {
        var p = try Pipeline.parse(expression: "a.b x=1 | c.d | e.f mode=z")
        XCTAssertEqual(p.expression, "a.b x=1 | c.d | e.f mode=z")
        p.steps[1].enabled = false
        XCTAssertEqual(p.expression, "a.b x=1 | e.f mode=z")
        XCTAssertEqual(try Pipeline.parse(expression: p.expression).steps.map(\.toolID), ["a.b", "e.f"])
    }

    func testSlugAndToolID() {
        XCTAssertEqual(Pipeline(name: "My  Cool Pipeline!").slug, "my-cool-pipeline")
        XCTAssertEqual(Pipeline(name: "Décode → JSON").toolID, "pipeline.décode-json")
    }

    func testExportImportJSON() throws {
        var p = try Pipeline.parse(expression: "base64.text mode=decode | json.format indent=4", name: "Decode JSON")
        p.hotkey = "⌃⌥J"; p.summary = "decode then pretty print"
        let back = try Pipeline.importJSON(p.exportJSON())
        XCTAssertNotEqual(back.id, p.id, "import assigns a fresh id")
        XCTAssertEqual(back.name, p.name); XCTAssertEqual(back.hotkey, "⌃⌥J"); XCTAssertEqual(back.summary, p.summary)
        XCTAssertEqual(back.steps.map(\.toolID), p.steps.map(\.toolID)); XCTAssertEqual(back.steps.map(\.options), p.steps.map(\.options))
        XCTAssertThrowsError(try Pipeline.importJSON(Data("{}".utf8)))
    }

    // MARK: engine

    func testIntermediateOutputsAreRecorded() async throws {
        let p = try Pipeline.parse(expression: "base64.text | base64.text mode=decode | json.format mode=minify")
        let run = await PipelineEngine.run(p, input: ToolInput(text: "{ \"a\" : [1, 2] }"), tools: lookup)
        XCTAssertNil(run.error)
        XCTAssertEqual(run.steps.count, 3)
        let encoded = try XCTUnwrap(run.steps[0].output?.text)
        XCTAssertEqual(encoded, Data("{ \"a\" : [1, 2] }".utf8).base64EncodedString())
        XCTAssertEqual(run.steps[1].output?.text, "{ \"a\" : [1, 2] }")
        XCTAssertEqual(run.steps[2].output?.text, "{\"a\":[1,2]}")
        XCTAssertEqual(run.finalOutput?.text, "{\"a\":[1,2]}")
        XCTAssertEqual(run.steps.map(\.tool?.id), ["base64.text", "base64.text", "json.format"])
        XCTAssertTrue(run.steps.allSatisfy { !$0.skipped && $0.error == nil })
        XCTAssertGreaterThan(run.duration, .zero)
    }

    func testOutputOfOneStepIsTheInputOfTheNext() async throws {
        // hash of the Base64 of the input, computed independently with the hashing support code.
        let p = try Pipeline.parse(expression: "base64.text | hash.generate algorithm=sha256")
        let run = await PipelineEngine.run(p, input: ToolInput(text: "abc"), tools: lookup)
        let b64 = Data("abc".utf8).base64EncodedString()
        XCTAssertEqual(run.finalOutput?.text, TT.hex(Hashing.sha256(Data(b64.utf8))))
    }

    func testDisabledStepIsSkipped() async throws {
        var p = try Pipeline.parse(expression: "base64.text | json.format mode=minify | base64.text")
        p.steps[1].enabled = false
        let run = await PipelineEngine.run(p, input: ToolInput(text: "hi"), tools: lookup)
        XCTAssertNil(run.error)
        XCTAssertTrue(run.steps[1].skipped); XCTAssertNil(run.steps[1].output)
        // base64(base64("hi")): the disabled JSON step did not touch the data.
        XCTAssertEqual(run.finalOutput?.text, Data(Data("hi".utf8).base64EncodedString().utf8).base64EncodedString())
        XCTAssertFalse(run.steps[0].skipped); XCTAssertFalse(run.steps[2].skipped)
    }

    func testFailingStepStopsThePipeline() async throws {
        let p = try Pipeline.parse(expression: "base64.text mode=decode | json.format | base64.text")
        // "{{{" is not valid Base64, so step 1 fails.
        let run = await PipelineEngine.run(p, input: ToolInput(text: "{{{"), tools: lookup)
        XCTAssertNotNil(run.error)
        XCTAssertNil(run.finalOutput)
        XCTAssertEqual(run.steps.count, 3)
        XCTAssertNotNil(run.steps[0].error)
        XCTAssertTrue(run.steps[1].skipped); XCTAssertTrue(run.steps[2].skipped)
        XCTAssertNil(run.steps[1].output); XCTAssertNil(run.steps[2].output)
    }

    func testFailureInTheMiddleKeepsEarlierOutputs() async throws {
        let p = try Pipeline.parse(expression: "base64.text | json.format | base64.text mode=decode")
        let run = await PipelineEngine.run(p, input: ToolInput(text: "this is not json"), tools: lookup)
        XCTAssertNotNil(run.steps[0].output); XCTAssertNil(run.steps[0].error)
        XCTAssertNotNil(run.steps[1].error)   // Base64 text is not JSON
        XCTAssertTrue(run.steps[2].skipped)
        XCTAssertNil(run.finalOutput)
        XCTAssertEqual(run.error, run.steps[1].error)
    }

    func testUnknownToolStopsThePipeline() async throws {
        let p = try Pipeline.parse(expression: "base64.text | no.such.tool | base64.text")
        let run = await PipelineEngine.run(p, input: ToolInput(text: "x"), tools: lookup)
        XCTAssertEqual(run.error?.message, "Unknown tool \"no.such.tool\"")
        XCTAssertNil(run.finalOutput)
        XCTAssertEqual(run.steps.count, 2, "nothing after the unknown tool is attempted")
    }

    func testEmptyPipelineHasNoOutput() async {
        let run = await PipelineEngine.run(Pipeline(name: "empty"), input: ToolInput(text: "x"), tools: lookup)
        XCTAssertNil(run.finalOutput); XCTAssertTrue(run.steps.isEmpty); XCTAssertNil(run.error)
    }

    func testAllStepsDisabledGivesNoOutput() async throws {
        var p = try Pipeline.parse(expression: "base64.text | base64.text")
        for i in p.steps.indices { p.steps[i].enabled = false }
        let run = await PipelineEngine.run(p, input: ToolInput(text: "x"), tools: lookup)
        XCTAssertNil(run.finalOutput); XCTAssertTrue(run.steps.allSatisfy(\.skipped))
    }

    func testPipelineWrappedAsTool() async throws {
        let p = try Pipeline.parse(expression: "base64.text | base64.text mode=decode", name: "Round Trip")
        let tool = PipelineEngine.asTool(p, tools: lookup)
        XCTAssertEqual(tool.id, "pipeline.round-trip"); XCTAssertEqual(tool.kind, .pipeline); XCTAssertEqual(tool.category, .scripting)
        XCTAssertEqual(tool.summary, p.expression)
        XCTAssertTrue(tool.keywords.contains("base64.text"))
        let out = try await tool.run(text: "hello")
        XCTAssertEqual(out.text, "hello")
        let failing = PipelineEngine.asTool(try Pipeline.parse(expression: "base64.text mode=decode"), tools: lookup)
        do { _ = try await failing.run(text: "***"); XCTFail("expected the step error to propagate") } catch { XCTAssertTrue(error is ToolError) }
    }

    func testCancellationStopsBetweenSteps() async throws {
        let p = try Pipeline.parse(expression: "base64.text | base64.text | base64.text")
        let find = lookup
        let task = Task { () -> PipelineRun in
            withUnsafeCurrentTask { $0?.cancel() }
            return await PipelineEngine.run(p, input: ToolInput(text: "x"), tools: find)
        }
        let run = await task.value
        XCTAssertTrue(run.steps.isEmpty)
        XCTAssertNil(run.finalOutput)
    }
}
