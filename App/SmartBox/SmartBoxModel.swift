import SwiftUI
import AppKit
import Observation
import BitlatheCore
import BitlatheUI

/// State behind the Smart Box home screen: the text in the box, what it was recognised as, the ranked actions, and
/// the tool session that runs the chosen action. Accepting a result (copy, replace, open) teaches the ranking.
@MainActor
@Observable
final class SmartBoxModel {
    /// The box. Every change re-analyses after a short pause.
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            if text != replacedText { replacedFrom = nil }
            scheduleAnalysis()
        }
    }
    private(set) var analysis: SmartBox.Analysis?
    private(set) var selected = 0
    /// The person picked an action themselves, so a later re-analysis keeps it rather than jumping back to the top.
    private(set) var userChose = false
    /// Runs the chosen action (the first step of a chain).
    private(set) var session: ToolSession?
    /// Second step of a chained action; its input is the first step's output.
    private(set) var chainSession: ToolSession?
    private(set) var learned: SmartBox.Learned = [:]
    private(set) var recent: [HistoryEntry] = []
    /// Text before the last Replace, for Undo.
    private(set) var replacedFrom: String?
    private var replacedText: String?

    weak var app: AppModel?
    private var analyseTask: Task<Void, Never>?

    var current: SmartBox.Action? {
        guard let a = analysis, a.actions.indices.contains(selected) else { return nil }
        return a.actions[selected]
    }
    /// The session whose output is the final result (the second step for chains).
    var resultSession: ToolSession? { chainSession ?? session }
    var resultText: String { resultSession?.outputText.nonEmpty ?? metadataText ?? "" }
    var canAccept: Bool { !resultText.isEmpty }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var error: ToolError? { session?.error ?? chainSession?.error }

    /// Facts-only results (number bases, a parsed URL) copy as "Label: value" lines.
    private var metadataText: String? {
        guard let rows = resultSession?.output?.metadata, !rows.isEmpty else { return nil }
        return rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }

    init() {
        Task { await reloadMemory() }
    }

    // MARK: Analysis

    private func scheduleAnalysis() {
        analyseTask?.cancel()
        let snapshot = text
        if snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            analysis = nil; selected = 0; userChose = false; session = nil; chainSession = nil
            return
        }
        let tools = ToolRegistry.shared.tools
        let ignoring = Set(Settings.shared.detectionIgnoreList)
        let learned = self.learned
        analyseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                SmartBox.analyse(snapshot, tools: tools, ignoring: ignoring, learned: learned)
            }.value
            guard !Task.isCancelled, let self, self.text == snapshot else { return }
            self.apply(result)
        }
    }

    private func apply(_ result: SmartBox.Analysis?) {
        let previousKey = current?.key
        let previousFormat = analysis?.formatKey
        analysis = result
        guard let result else { session = nil; chainSession = nil; return }
        if result.formatKey != previousFormat { userChose = false }
        if userChose, let key = previousKey, let i = result.actions.firstIndex(where: { $0.key == key }) {
            selected = i
        } else {
            selected = 0
        }
        runCurrent(keepSession: current?.key == previousKey)
    }

    func choose(_ index: Int) {
        guard let a = analysis, a.actions.indices.contains(index), index != selected else { return }
        selected = index
        userChose = true
        runCurrent(keepSession: false)
    }

    private func runCurrent(keepSession: Bool) {
        guard let action = current else { session = nil; chainSession = nil; return }
        if action.opensTool { session = nil; chainSession = nil; return }
        let input = action.inputOverride ?? text
        if keepSession, let s = session, s.tool.id == action.tool.id {
            s.inputText = input              // same action, new text: the session debounces and re-runs
        } else {
            let s = ToolSession(tool: action.tool, input: input, options: action.options)
            session = s
            observe(s)
        }
        if let step = action.then, let first = session {
            if chainSession?.tool.id != step.tool.id {
                chainSession = ToolSession(tool: step.tool, input: first.outputText, options: step.options)
                chainSession?.recordsHistory = false
            } else {
                chainSession?.inputText = first.outputText
            }
        } else {
            chainSession = nil
        }
    }

    /// Follows the first step's output: feeds a chain's second step, and offers a chain when the output is itself data.
    private func observe(_ s: ToolSession) {
        withObservationTracking { _ = s.output } onChange: { [weak self, weak s] in
            Task { @MainActor in
                guard let self, let s, self.session === s else { return }
                self.firstStepChanged(s)
                self.observe(s)
            }
        }
    }

    private func firstStepChanged(_ s: ToolSession) {
        guard let action = current, var a = analysis else { return }
        if action.then != nil {
            chainSession?.inputText = s.outputText
            return
        }
        // Base64 that hides JSON and the like: put "decode → format" first unless the person prefers otherwise.
        guard !userChose, selected == 0,
              var chain = SmartBox.chain(after: action, output: s.outputText, tools: ToolRegistry.shared.tools),
              !a.actions.contains(where: { $0.key == chain.key }) else { return }
        let counts = learned[a.formatKey] ?? [:]
        chain.learned = counts[chain.key] ?? 0
        guard chain.learned >= (counts[action.key] ?? 0) else {
            a.actions.insert(chain, at: 1)
            analysis = a
            return
        }
        a.actions.insert(chain, at: 0)
        analysis = a
        selected = 0
        if let step = chain.then {
            chainSession = ToolSession(tool: step.tool, input: s.outputText, options: step.options)
            chainSession?.recordsHistory = false
        }
    }

    // MARK: Accepting a result

    func copy() {
        guard canAccept else { return }
        Clipboard.copy(resultText)
        learn()
    }

    func replace() {
        guard canAccept else { return }
        learn()
        replacedFrom = text
        replacedText = resultText
        userChose = false
        text = resultText
        ToastCenter.shared.show("Replaced. Undo is next to the result.", symbol: "arrow.uturn.backward")
    }

    func undoReplace() {
        guard let previous = replacedFrom else { return }
        replacedFrom = nil
        text = previous
    }

    func openTool() {
        guard let action = current, let app else { return }
        learn()
        if let step = action.then, let first = session {
            app.open(toolID: step.tool.id, input: first.outputText, options: step.options)
        } else {
            app.open(toolID: action.tool.id, input: action.opensTool ? nil : (action.inputOverride ?? text), options: action.options)
        }
    }

    func clear() {
        text = ""
        Task { await refreshRecent() }
    }

    func paste(_ s: String) {
        userChose = false
        text = s
    }

    /// Counts the accepted action for this kind of data, so it ranks higher next time.
    private func learn() {
        guard let a = analysis, let action = current, a.kind != .words || !action.opensTool else { return }
        learned[a.formatKey, default: [:]][action.key, default: 0] += 1
        let format = a.formatKey, key = action.key
        Task {
            try? await DataStore.shared.recordChoice(format: format, action: key)
            await refreshRecent()
        }
    }

    // MARK: Memory

    func reloadMemory() async {
        let loaded = (try? await DataStore.shared.choices()) ?? [:]
        let changed = loaded != learned
        learned = loaded
        // Text that arrived before the memory loaded (launch, Quick Panel hand-off) is re-ranked with it.
        if changed, !isEmpty { scheduleAnalysis() }
        await refreshRecent()
    }

    func refreshRecent() async {
        recent = (try? await DataStore.shared.latestInputs(limit: 4)) ?? []
    }

    func forgetLearning() async {
        try? await DataStore.shared.clearChoices()
        learned = [:]
        scheduleAnalysis()
    }

    /// The most common choice for the formats used most, for "Your usual" on the empty screen.
    var usual: [String] {
        let tools = Dictionary(ToolRegistry.shared.tools.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return learned
            .compactMap { format, actions -> (String, String, Int)? in
                guard !format.hasPrefix("command"), format != "words", let top = actions.max(by: { $0.value < $1.value }),
                      let formatTool = tools[format] else { return nil }
                let line: String
                if let action = SmartBox.action(fromKey: top.key, tools: tools) {
                    // Same tool, other mode: "JSON Formatter · Minify". Another tool: "JSON Formatter → YAML ⇄ JSON".
                    line = action.tool.id == format
                        ? [action.title, action.detail].compactMap { $0 }.joined(separator: " · ")
                        : "\(formatTool.name) → \(action.title)"
                } else if top.key.contains(">"), let next = top.key.split(separator: ">").last.flatMap({ tools[String($0)] }) {
                    line = "\(formatTool.name) → \(next.name)"
                } else {
                    line = formatTool.name
                }
                return (format, line, top.value)
            }
            .sorted { $0.2 > $1.2 }
            .prefix(3)
            .map(\.1)
    }

    var inputLanguage: CodeLanguage {
        guard let a = analysis, a.kind == .data, let tool = a.actions.first?.tool else { return .plain }
        return tool.io.inputLanguage
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Focus plumbing (menu commands act on the Smart Box when it is in front)

struct SmartBoxFocusKey: FocusedValueKey { typealias Value = SmartBoxModel }

extension FocusedValues {
    var smartBox: SmartBoxModel? {
        get { self[SmartBoxFocusKey.self] }
        set { self[SmartBoxFocusKey.self] = newValue }
    }
}
