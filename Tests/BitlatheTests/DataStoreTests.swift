import XCTest
import BitlatheCore

final class DataStoreTests: XCTestCase {
    private func store() throws -> DataStore { try DataStore.inMemory() }

    // MARK: history

    func testAddAndListHistoryNewestFirst() async throws {
        let s = try store()
        try await s.addHistory(toolID: "json.format", input: "{\"a\":1}", options: ["mode": .string("minify"), "indent": .int(4), "sortKeys": .bool(true), "x": .double(1.5)])
        try await s.addHistory(toolID: "json.format", input: "[1,2]", options: [:])
        try await s.addHistory(toolID: "base64.text", input: "hello", options: [:])
        let json = try await s.history(toolID: "json.format")
        XCTAssertEqual(json.map(\.input), ["[1,2]", "{\"a\":1}"])
        XCTAssertEqual(json[1].options, ["mode": .string("minify"), "indent": .int(4), "sortKeys": .bool(true), "x": .double(1.5)])
        XCTAssertEqual(json[0].toolID, "json.format")
        let v1 = try await s.history(toolID: nil).count
        XCTAssertEqual(v1, 3)
        let v2 = try await s.history(toolID: "base64.text").map(\.input)
        XCTAssertEqual(v2, ["hello"])
        let v3 = try await s.recentInputs(limit: 2).count
        XCTAssertEqual(v3, 2)
        XCTAssertEqual(json[0].createdAt.timeIntervalSinceNow, 0, accuracy: 5)
    }

    func testDuplicateInputsCollapseAndMoveToTop() async throws {
        let s = try store()
        try await s.addHistory(toolID: "t", input: "one", options: ["v": .int(1)])
        try await s.addHistory(toolID: "t", input: "two", options: [:])
        try await s.addHistory(toolID: "t", input: "one", options: ["v": .int(2)])
        let h = try await s.history(toolID: "t")
        XCTAssertEqual(h.map(\.input), ["one", "two"])
        XCTAssertEqual(h[0].options, ["v": .int(2)], "latest options replace the old ones")
        try await s.addHistory(toolID: "other", input: "one", options: [:])
        let v4 = try await s.history(toolID: nil).count
        XCTAssertEqual(v4, 3, "the same input under another tool is a separate entry")
    }

    func testBlankAndOversizedInputsAreIgnored() async throws {
        let s = try store()
        try await s.addHistory(toolID: "t", input: "   \n", options: [:])
        try await s.addHistory(toolID: "t", input: String(repeating: "x", count: 512 * 1024), options: [:])
        try await s.addHistory(toolID: "t", input: String(repeating: "x", count: 512 * 1024 - 1), options: [:])
        let h = try await s.history(toolID: "t")
        XCTAssertEqual(h.count, 1)
    }

    func testPerToolLimitKeepsNewestAndPinned() async throws {
        let s = try store()
        for i in 1...6 { try await s.addHistory(toolID: "t", input: "item \(i)", options: [:], maxPerTool: 3) }
        let v5 = try await s.history(toolID: "t").map(\.input)
        XCTAssertEqual(v5, ["item 6", "item 5", "item 4"])
        let v6 = try await s.history(toolID: "t").last
        let oldest = try XCTUnwrap(v6)
        try await s.setPinned(oldest.id, true)
        for i in 7...9 { try await s.addHistory(toolID: "t", input: "item \(i)", options: [:], maxPerTool: 3) }
        let h = try await s.history(toolID: "t")
        XCTAssertTrue(h.contains { $0.input == "item 4" && $0.pinned }, "pinned entries survive pruning")
        XCTAssertEqual(h.filter { !$0.pinned }.map(\.input), ["item 9", "item 8", "item 7"])
        try await s.addHistory(toolID: "other", input: "untouched", options: [:], maxPerTool: 3)
        let v7 = try await s.history(toolID: "other").count
        XCTAssertEqual(v7, 1, "limits apply per tool")
    }

    func testSearchHistory() async throws {
        let s = try store()
        try await s.addHistory(toolID: "t", input: "The Quick brown fox", options: [:])
        try await s.addHistory(toolID: "t", input: "lazy dog", options: [:])
        let v8 = try await s.history(toolID: "t", query: "quick").map(\.input)
        XCTAssertEqual(v8, ["The Quick brown fox"], "case-insensitive substring")
        let v9 = try await s.history(toolID: nil, query: "zzz").count
        XCTAssertEqual(v9, 0)
        // Regression: `%` and `_` typed by the user must be literal, not SQL wildcards.
        try await s.addHistory(toolID: "t", input: "50% off", options: [:])
        try await s.addHistory(toolID: "t", input: "50 apples", options: [:])
        try await s.addHistory(toolID: "t", input: "snake_case", options: [:])
        try await s.addHistory(toolID: "t", input: "snakeXcase", options: [:])
        let v10 = try await s.history(toolID: "t", query: "50%").map(\.input)
        XCTAssertEqual(v10, ["50% off"])
        let v11 = try await s.history(toolID: "t", query: "snake_case").map(\.input)
        XCTAssertEqual(v11, ["snake_case"])
        let v12 = try await s.history(toolID: "t", query: "%").map(\.input)
        XCTAssertEqual(v12, ["50% off"])
    }

    func testPinnedEntriesTitlesAndOrdering() async throws {
        let s = try store()
        try await s.addHistory(toolID: "a", input: "first", options: [:])
        try await s.addHistory(toolID: "b", input: "second", options: [:])
        try await s.addHistory(toolID: "a", input: "third", options: [:])
        let v13 = try await s.history(toolID: "a").last
        let first = try XCTUnwrap(v13)
        try await s.setPinned(first.id, true, title: "Important")
        let v14 = try await s.pinned().map(\.input)
        XCTAssertEqual(v14, ["first"])
        let v15 = try await s.pinned().first?.title
        XCTAssertEqual(v15, "Important")
        let v16 = try await s.pinned(toolID: "b").count
        XCTAssertEqual(v16, 0)
        let v17 = try await s.pinned(toolID: "a").count
        XCTAssertEqual(v17, 1)
        let v18 = try await s.history(toolID: nil).first?.input
        XCTAssertEqual(v18, "first", "pinned entries sort first")
        try await s.setPinned(first.id, true)   // re-pinning without a title keeps the existing title
        let v19 = try await s.pinned().first?.title
        XCTAssertEqual(v19, "Important")
        let v20 = try await s.history(toolID: nil, query: "Important").count
        XCTAssertEqual(v20, 1, "titles are searchable")
        try await s.setPinned(first.id, false)
        let v21 = try await s.pinned().isEmpty
        XCTAssertTrue(v21)
    }

    func testDeleteAndClear() async throws {
        let s = try store()
        for i in 1...4 { try await s.addHistory(toolID: i % 2 == 0 ? "even" : "odd", input: "v\(i)", options: [:]) }
        let all = try await s.history(toolID: nil)
        try await s.setPinned(all[0].id, true)
        try await s.deleteHistory(id: all[1].id)
        let v22 = try await s.history(toolID: nil).count
        XCTAssertEqual(v22, 3)
        try await s.clearHistory(toolID: all[0].toolID)
        let v23 = try await s.history(toolID: all[0].toolID).contains { $0.id == all[0].id }
        XCTAssertTrue(v23, "pinned survive a normal clear")
        try await s.clearHistory()
        let v24 = try await s.history(toolID: nil).map(\.id)
        XCTAssertEqual(v24, [all[0].id])
        try await s.clearHistory(includePinned: true)
        let v25 = try await s.history(toolID: nil).isEmpty
        XCTAssertTrue(v25)
    }

    func testPruneByAge() async throws {
        let s = try store()
        try await s.addHistory(toolID: "t", input: "recent", options: [:])
        try await s.addClipboard(content: "clip", toolID: nil, sourceApp: nil)
        try await s.pruneHistory(olderThan: 30)
        let v26 = try await s.history(toolID: "t").count
        XCTAssertEqual(v26, 1, "nothing is older than 30 days")
        let v27 = try await s.clipboard().count
        XCTAssertEqual(v27, 1)
        try await s.pruneHistory(olderThan: -1)   // cutoff in the future: everything is "old"
        let v28 = try await s.history(toolID: "t").isEmpty
        XCTAssertTrue(v28)
        let v29 = try await s.clipboard().isEmpty
        XCTAssertTrue(v29)
    }

    // MARK: favourites and usage

    func testFavouritesOrderAndReorder() async throws {
        let s = try store()
        let v30 = try await s.favourites().isEmpty
        XCTAssertTrue(v30)
        for id in ["json.format", "base64.text", "hash.generate"] { try await s.setFavourite(id, true) }
        try await s.setFavourite("base64.text", true)   // idempotent
        let v31 = try await s.favourites()
        XCTAssertEqual(v31, ["json.format", "base64.text", "hash.generate"])
        try await s.reorderFavourites(["hash.generate", "json.format", "base64.text"])
        let v32 = try await s.favourites()
        XCTAssertEqual(v32, ["hash.generate", "json.format", "base64.text"])
        try await s.setFavourite("json.format", false)
        let v33 = try await s.favourites()
        XCTAssertEqual(v33, ["hash.generate", "base64.text"])
        try await s.setFavourite("cron.parse", true)
        let v34 = try await s.favourites().last
        XCTAssertEqual(v34, "cron.parse", "new favourites are appended")
        try await s.setFavourite("never.added", false)   // removing a non-favourite is harmless
        let v35 = try await s.favourites().count
        XCTAssertEqual(v35, 3)
    }

    func testUsageFrequencyAndRecency() async throws {
        let s = try store()
        for id in ["a", "b", "b", "c", "c", "c"] { try await s.recordUse(id) }
        let v36 = try await s.frequentlyUsed()
        XCTAssertEqual(v36, ["c", "b", "a"])
        let v37 = try await s.frequentlyUsed(limit: 2)
        XCTAssertEqual(v37, ["c", "b"])
        let v38 = try await s.recentlyUsed().first
        XCTAssertEqual(v38, "c")
        try await s.recordUse("a")
        let v39 = try await s.recentlyUsed().first
        XCTAssertEqual(v39, "a")
        let v40 = try await s.recentlyUsed(limit: 1)
        XCTAssertEqual(v40, ["a"])
        try await s.recordUse("b"); try await s.recordUse("b")
        let v41 = try await s.frequentlyUsed().first
        XCTAssertEqual(v41, "b", "b now has 4 uses")
    }

    // MARK: pipelines

    func testPipelinesRoundTripAndReplace() async throws {
        let s = try store()
        var p = try Pipeline.parse(expression: "base64.text mode=decode | json.format indent=4", name: "Zed")
        p.hotkey = "⌃⌥Z"; p.summary = "sum"; p.steps[1].enabled = false
        let other = try Pipeline.parse(expression: "hash.generate algorithm=md5", name: "Alpha")
        try await s.save(p); try await s.save(other)
        let list = try await s.pipelines()
        XCTAssertEqual(list.map(\.name), ["Alpha", "Zed"], "sorted by name")
        let loaded = try XCTUnwrap(list.last)
        XCTAssertEqual(loaded.id, p.id); XCTAssertEqual(loaded.hotkey, "⌃⌥Z"); XCTAssertEqual(loaded.summary, "sum")
        XCTAssertEqual(loaded.steps.map(\.toolID), ["base64.text", "json.format"])
        XCTAssertEqual(loaded.steps.map(\.options), p.steps.map(\.options))
        XCTAssertEqual(loaded.steps.map(\.enabled), [true, false])
        XCTAssertEqual(loaded.steps.map(\.id), p.steps.map(\.id))
        // Saving again with the same id replaces rather than duplicates, and bumps updatedAt.
        p.name = "Zed renamed"; p.steps.removeLast()
        try await s.save(p)
        let after = try await s.pipelines()
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.first { $0.id == p.id }?.name, "Zed renamed")
        XCTAssertEqual(after.first { $0.id == p.id }?.steps.count, 1)
        XCTAssertGreaterThan(after.first { $0.id == p.id }!.updatedAt, p.createdAt.addingTimeInterval(-1))
        try await s.deletePipeline(id: p.id)
        let v42 = try await s.pipelines().map(\.name)
        XCTAssertEqual(v42, ["Alpha"])
    }

    // MARK: clipboard

    func testClipboardHistory() async throws {
        let s = try store()
        try await s.addClipboard(content: "one", toolID: "json.format", sourceApp: "Xcode")
        try await s.addClipboard(content: "one", toolID: nil, sourceApp: nil)       // consecutive duplicate is dropped
        try await s.addClipboard(content: "two", toolID: nil, sourceApp: nil)
        try await s.addClipboard(content: "one", toolID: nil, sourceApp: nil)       // not consecutive any more
        let c = try await s.clipboard()
        XCTAssertEqual(c.map(\.content), ["one", "two", "one"])
        XCTAssertEqual(c[2].detectedToolID, "json.format"); XCTAssertEqual(c[2].sourceApp, "Xcode")
        XCTAssertNil(c[0].detectedToolID)
        let v43 = try await s.clipboard(query: "tw").map(\.content)
        XCTAssertEqual(v43, ["two"])
        let v44 = try await s.clipboard(limit: 1).count
        XCTAssertEqual(v44, 1)
        try await s.addClipboard(content: "50% done", toolID: nil, sourceApp: nil)
        try await s.addClipboard(content: "50 done", toolID: nil, sourceApp: nil)
        let v45 = try await s.clipboard(query: "50%").map(\.content)
        XCTAssertEqual(v45, ["50% done"], "% is literal")
        try await s.clearClipboard()
        let v46 = try await s.clipboard().isEmpty
        XCTAssertTrue(v46)
    }

    func testClipboardCapacity() async throws {
        let s = try store()
        for i in 1...10 { try await s.addClipboard(content: "c\(i)", toolID: nil, sourceApp: nil, max: 4) }
        let v47 = try await s.clipboard().map(\.content)
        XCTAssertEqual(v47, ["c10", "c9", "c8", "c7"])
    }

    // MARK: custom groups and wipe

    func testCustomGroups() async throws {
        let s = try store()
        try await s.save(group: .init(id: "g2", name: "Second", toolIDs: ["a", "b"]), order: 2)
        try await s.save(group: .init(id: "g1", name: "First", toolIDs: ["x"]), order: 1)
        var groups = try await s.customGroups()
        XCTAssertEqual(groups.map(\.id), ["g1", "g2"])
        XCTAssertEqual(groups[1].toolIDs, ["a", "b"])
        try await s.save(group: .init(id: "g1", name: "First!", toolIDs: []), order: 3)
        groups = try await s.customGroups()
        XCTAssertEqual(groups.map(\.name), ["Second", "First!"])
        XCTAssertEqual(groups[1].toolIDs, [])
        try await s.deleteGroup(id: "g2")
        let v48 = try await s.customGroups().map(\.id)
        XCTAssertEqual(v48, ["g1"])
    }

    func testWipeEverything() async throws {
        let s = try store()
        try await s.addHistory(toolID: "t", input: "x", options: [:])
        try await s.setFavourite("t", true); try await s.recordUse("t")
        try await s.addClipboard(content: "c", toolID: nil, sourceApp: nil)
        try await s.save(group: .init(id: "g", name: "G", toolIDs: ["t"]), order: 0)
        try await s.wipeEverything()
        let v49 = try await s.history(toolID: nil).isEmpty
        XCTAssertTrue(v49)
        let v50 = try await s.favourites().isEmpty
        XCTAssertTrue(v50)
        let v51 = try await s.frequentlyUsed().isEmpty
        XCTAssertTrue(v51)
        let v52 = try await s.clipboard().isEmpty
        XCTAssertTrue(v52)
        let v53 = try await s.customGroups().isEmpty
        XCTAssertTrue(v53)
    }

    func testSeparateInMemoryStoresAreIsolated() async throws {
        let a = try store(), b = try store()
        try await a.setFavourite("only.in.a", true)
        let v54 = try await b.favourites().isEmpty
        XCTAssertTrue(v54)
    }

    func testOnDiskStorePersistsAcrossInstances() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bitlathe-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try DataStore(database: Database(url: url))
        try await first.addHistory(toolID: "t", input: "persisted", options: ["k": .string("v")])
        try await first.setFavourite("t", true)
        let second = try DataStore(database: Database(url: url))
        let v55 = try await second.history(toolID: "t").map(\.input)
        XCTAssertEqual(v55, ["persisted"])
        let v56 = try await second.favourites()
        XCTAssertEqual(v56, ["t"])
    }
}
