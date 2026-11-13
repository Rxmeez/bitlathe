import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BitlatheCore
import BitlatheUI

/// Saved pipelines: persistence, registry registration, seeding and the per-pipeline editors.
@MainActor
@Observable
final class PipelineLibrary {
    private(set) var pipelines: [Pipeline] = []
    @ObservationIgnored private var editors: [UUID: PipelineEditor] = [:]
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let seededKey = "pipelines.seeded"

    static let fileType = UTType(filenameExtension: "bitlathe-pipeline", conformingTo: .json) ?? .json

    // MARK: Lifecycle

    func bootstrap(model: AppModel) async {
        self.model = model
        var list = (try? await DataStore.shared.pipelines()) ?? []
        if list.isEmpty, !UserDefaults.standard.bool(forKey: seededKey) {
            for seed in PipelineSeeds.make() {
                try? await DataStore.shared.save(seed.pipeline)
                PipelineEditor.storeInput(seed.sampleInput, for: seed.pipeline.id)
            }
            UserDefaults.standard.set(true, forKey: seededKey)
            list = (try? await DataStore.shared.pipelines()) ?? []
        }
        pipelines = sorted(list)
        register()
        // Restore a pipeline that was open at last quit (it was not in the registry when AppModel initialised).
        let last = model.settings.lastToolID
        if !model.isHome, let p = pipelines.first(where: { $0.toolID == last }) { model.selectedToolID = p.toolID } // smartbox: launch stays home
        #if DEBUG
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "BLPipeline"), let p = pipelines.first(where: { $0.name == name || $0.slug == name }) {
            model.selectedToolID = p.toolID
            let editor = self.editor(for: p)
            if let text = defaults.string(forKey: "BLPipelineInput") {
                editor.persistsInput = false
                editor.input = text.replacingOccurrences(of: "\\n", with: "\n")
            }
            if defaults.bool(forKey: "BLPipelineExpand") { for s in p.steps { editor.expanded[s.id] = true } }
            if defaults.bool(forKey: "BLPipelinePicker") { editor.debugShowPicker = true }
        }
        #endif
    }

    // MARK: Lookup

    func pipeline(forToolID id: String) -> Pipeline? { pipelines.first { $0.toolID == id } }

    func editor(forToolID id: String) -> PipelineEditor? { pipeline(forToolID: id).map(editor(for:)) }

    func editor(for pipeline: Pipeline) -> PipelineEditor {
        if let e = editors[pipeline.id] { return e }
        let e = PipelineEditor(pipeline: pipeline)
        editors[pipeline.id] = e
        return e
    }

    // MARK: Registry

    private func sorted(_ list: [Pipeline]) -> [Pipeline] {
        list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Re-registers every saved pipeline as a tool so it appears in the palette, URL scheme and Shortcuts.
    func register() {
        let registry = ToolRegistry.shared
        registry.unregister(kind: .pipeline)
        for p in pipelines { registry.register(PipelineEngine.asTool(p, tools: { Self.lookupTool($0) })) }
    }

    /// Registry lookup that is safe from any executor (pipelines run off the main actor).
    nonisolated static func lookupTool(_ id: String) -> AnyTool? {
        if Thread.isMainThread { return MainActor.assumeIsolated { ToolRegistry.shared.tool(id) } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { ToolRegistry.shared.tool(id) } }
    }

    // MARK: Actions

    func uniqueName(_ base: String, excluding id: UUID?) -> String {
        let taken = Set(pipelines.filter { $0.id != id }.map { $0.slug })
        var name = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Untitled Pipeline" }
        var candidate = name
        var n = 2
        while taken.contains(Pipeline(name: candidate).slug) { candidate = "\(name) \(n)"; n += 1 }
        return candidate
    }

    private func upsert(_ p: Pipeline) {
        if let i = pipelines.firstIndex(where: { $0.id == p.id }) { pipelines[i] = p } else { pipelines.append(p) }
        pipelines = sorted(pipelines)
        register()
    }

    func create() {
        Task { await add(Pipeline(name: uniqueName("Untitled Pipeline", excluding: nil))) }
    }

    func duplicate(_ editor: PipelineEditor) {
        var copy = editor.draft
        copy.id = UUID()
        copy.name = uniqueName(copy.name + " Copy", excluding: nil)
        copy.createdAt = .now
        Task {
            await add(copy)
            PipelineEditor.storeInput(editor.input, for: copy.id)
            self.editors[copy.id]?.input = editor.input
        }
    }

    private func add(_ p: Pipeline) async {
        do {
            try await DataStore.shared.save(p)
            upsert(p)
            model?.selectedToolID = p.toolID
        } catch {
            ToastCenter.shared.show("Could not save: \(error.localizedDescription)", symbol: "xmark.octagon.fill")
        }
    }

    func save(_ editor: PipelineEditor) async {
        var p = editor.draft
        p.name = uniqueName(p.name, excluding: p.id)
        p.updatedAt = .now
        let wasSelected = model?.selectedToolID == editor.saved.toolID
        do { try await DataStore.shared.save(p) } catch {
            ToastCenter.shared.show("Could not save: \(error.localizedDescription)", symbol: "xmark.octagon.fill")
            return
        }
        editor.didSave(p)
        upsert(p)
        if wasSelected { model?.selectedToolID = p.toolID }
        ToastCenter.shared.show("Saved “\(p.name)”")
    }

    func delete(_ editor: PipelineEditor) {
        let id = editor.pipelineID
        Task {
            do { try await DataStore.shared.deletePipeline(id: id) } catch {
                ToastCenter.shared.show("Could not delete: \(error.localizedDescription)", symbol: "xmark.octagon.fill")
                return
            }
            pipelines.removeAll { $0.id == id }
            editors[id] = nil
            PipelineEditor.storeInput("", for: id)
            register()
            if let m = model, m.selectedTool == nil || m.selectedToolID == editor.saved.toolID {
                m.selectedToolID = pipelines.first?.toolID ?? m.registry.native.first?.id
            }
            ToastCenter.shared.show("Deleted pipeline", symbol: "trash.fill")
        }
    }

    func exportPipeline(_ editor: PipelineEditor) {
        do {
            let data = try editor.draft.exportJSON()
            FilePanels.save(data, suggestedName: "\(editor.draft.slug).bitlathe-pipeline", type: Self.fileType)
        } catch {
            ToastCenter.shared.show("Could not export: \(error.localizedDescription)", symbol: "xmark.octagon.fill")
        }
    }

    func importPipeline() {
        guard let url = FilePanels.open(types: [Self.fileType, .json]).first else { return }
        do {
            var p = try Pipeline.importJSON(Data(contentsOf: url))
            p.name = uniqueName(p.name, excluding: nil)
            p.createdAt = .now
            Task {
                await add(p)
                ToastCenter.shared.show("Imported “\(p.name)”", symbol: "square.and.arrow.down.fill")
            }
        } catch {
            ToastCenter.shared.show("Not a valid pipeline file", symbol: "xmark.octagon.fill")
        }
    }
}

// MARK: - Seeds

enum PipelineSeeds {
    struct Seed { let pipeline: Pipeline; let sampleInput: String }

    static func make() -> [Seed] {
        [
            Seed(pipeline: Pipeline(name: "Decode gzip JSON", summary: "Base64 → gunzip → pretty-printed JSON", symbol: "archivebox", steps: [
                PipelineStep(toolID: "base64.text", options: ["mode": .string("decode")]),
                PipelineStep(toolID: "compress.text", options: ["mode": .string("decompress"), "algorithm": .string("auto")]),
                PipelineStep(toolID: "json.format"),
            ]), sampleInput: "H4sIAAAAAAAAAx3LOwqAMBBF0a3Iq6cSq3T27kAshmSQgfyIMYXi3o22l3NvnIcUmBvqYKaREDkIDGbHw5KaeLYCQkleDpgV7ILGHsRpTQXbQ2BbtfWnllMIlfcfZs3iNX7zfmnu8gUK/TqXbAAAAA=="),
            Seed(pipeline: Pipeline(name: "JWT payload to YAML", summary: "Base64URL claims segment → JSON → YAML", symbol: "key.horizontal", steps: [
                PipelineStep(toolID: "base64.text", options: ["mode": .string("decode"), "variant": .string("url")]),
                PipelineStep(toolID: "json.format", options: ["sortKeys": .bool(true)]),
                PipelineStep(toolID: "convert.yaml-json", options: ["direction": .string("json2yaml")]),
            ]), sampleInput: "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkFkYSBMb3ZlbGFjZSIsImFkbWluIjp0cnVlLCJpYXQiOjE3MDAwMDAwMDAsInNjb3BlcyI6WyJyZWFkIiwid3JpdGUiXX0"),
        ]
    }
}

// MARK: - Editor model

@MainActor
@Observable
final class PipelineEditor {
    let pipelineID: UUID
    var draft: Pipeline { didSet { if oldValue.steps != draft.steps { scheduleRun() } } }
    private(set) var saved: Pipeline
    var input: String {
        didSet {
            guard input != oldValue else { return }
            if persistsInput { Self.storeInput(input, for: pipelineID) }
            scheduleRun()
        }
    }
    /// Off for screenshot-harness input, so a debug launch never overwrites the user's saved pipeline input.
    var persistsInput = true
    private(set) var run: PipelineRun?
    private(set) var running = false
    /// Explicit expand/collapse of a step's output; absent means "expanded only when it failed".
    var expanded: [UUID: Bool] = [:]
    var debugShowPicker = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(pipeline: Pipeline) {
        pipelineID = pipeline.id
        draft = pipeline
        saved = pipeline
        input = Self.loadInput(for: pipeline.id)
        scheduleRun()
    }

    var isDirty: Bool { draft != saved }

    func didSave(_ p: Pipeline) { saved = p; draft = p }

    // MARK: Persistence of the input text (UI state, not part of the pipeline JSON)

    nonisolated static func inputKey(_ id: UUID) -> String { "pipeline.input.\(id.uuidString)" }
    nonisolated static func storeInput(_ text: String, for id: UUID) {
        if text.isEmpty || text.utf8.count > 500_000 { UserDefaults.standard.removeObject(forKey: inputKey(id)) }
        else { UserDefaults.standard.set(text, forKey: inputKey(id)) }
    }
    nonisolated static func loadInput(for id: UUID) -> String { UserDefaults.standard.string(forKey: inputKey(id)) ?? "" }

    // MARK: Running (debounced, cancellable)

    func scheduleRun() {
        task?.cancel()
        let pipeline = draft
        let text = input
        guard !text.isEmpty, pipeline.steps.contains(where: \.enabled) else {
            run = nil
            running = false
            return
        }
        running = true
        let tools = Dictionary(ToolRegistry.shared.tools.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
            let result = await PipelineEngine.run(pipeline, input: ToolInput(text: text), tools: { tools[$0] })
            if Task.isCancelled { return }
            self?.run = result
            self?.running = false
        }
    }

    func result(for step: PipelineStep) -> PipelineStepResult? { run?.steps.first { $0.step.id == step.id } }

    func isExpanded(_ step: PipelineStep) -> Bool { expanded[step.id] ?? (result(for: step)?.error != nil) }

    // MARK: Editing

    func addStep(_ tool: AnyTool) {
        withAnimation(Motion.animation(Motion.normal)) {
            draft.steps.append(PipelineStep(toolID: tool.id))
        }
    }

    func removeStep(_ id: UUID) {
        withAnimation(Motion.animation(Motion.normal)) { draft.steps.removeAll { $0.id == id } }
    }

    func moveStep(_ id: UUID, to target: UUID) {
        guard id != target, let from = draft.steps.firstIndex(where: { $0.id == id }), let to = draft.steps.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(Motion.animation(Motion.normal)) {
            draft.steps.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        }
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        draft.steps[i].enabled = on
    }

    func options(for id: UUID) -> OptionValues { draft.steps.first { $0.id == id }?.options ?? [:] }

    func setOptions(_ id: UUID, _ options: OptionValues) {
        guard let i = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        draft.steps[i].options = options
    }

    // MARK: CLI

    /// `bl pipe "…"` for the enabled steps; falls back to the saved-pipeline form when a value cannot be written on one line.
    func cliCommand() -> (text: String, exact: Bool) {
        let unsafe = draft.steps.filter(\.enabled).contains { step in
            step.options.values.contains { v in
                let s = v.stringValue
                return s.isEmpty || s.contains { $0.isWhitespace || $0 == "|" || $0 == "\"" || $0 == "'" || $0 == "=" }
            }
        }
        if unsafe { return ("bl pipeline \"\(saved.name)\"", false) }
        let escaped = draft.expression
            .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$").replacingOccurrences(of: "`", with: "\\`")
        return ("bl pipe \"\(escaped)\"", true)
    }
}
