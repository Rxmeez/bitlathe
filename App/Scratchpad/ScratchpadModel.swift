import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

/// State behind the Scratchpad window: the autosaved document, selections, tool application and status.
@MainActor
@Observable
final class ScratchpadModel {
    static let shared = ScratchpadModel()

    var text: String {
        didSet { if text != oldValue { scheduleSave() } }
    }
    /// Every selected range (a lone caret is zero-length).
    var selections: [NSRange] = []
    var showPicker = false
    var errorMessage: String?
    var isRunning = false
    private(set) var lastToolID: String?
    private(set) var recentIDs: [String]
    private var lastOptions: [String: OptionValues]

    let controller = EditorController()
    let registry = ToolRegistry.shared

    /// Disabled by the DEBUG screenshot harness so seeded text never overwrites a real scratchpad.
    var persistenceEnabled = true
    private var saveTask: Task<Void, Never>?

    private enum Keys {
        static let recents = "scratchpad.recentTools"
        static let options = "scratchpad.toolOptions"
    }
    static let maxRecents = 6

    private static var fileURL: URL { StorePaths.appSupport.appendingPathComponent("scratchpad.txt") }

    private init() {
        text = (try? String(contentsOf: Self.fileURL, encoding: .utf8)) ?? ""
        let defaults = UserDefaults.standard
        recentIDs = defaults.stringArray(forKey: Keys.recents) ?? []
        if let data = defaults.data(forKey: Keys.options), let decoded = try? JSONDecoder().decode([String: OptionValues].self, from: data) {
            lastOptions = decoded
        } else {
            lastOptions = [:]
        }
        lastToolID = recentIDs.first
        controller.onSelectionChange = { [weak self] ranges in self?.selections = ranges }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ScratchpadModel.shared.saveNow() }
        }
    }

    // MARK: Derived

    /// Text tools only: text in, text out, single input, no side effects. Script tools qualify like native ones.
    var eligibleTools: [AnyTool] {
        registry.tools.filter { $0.io.input == .text && $0.io.output == .text && !$0.io.dualInput && !$0.sideEffects }
    }

    var lastTool: AnyTool? { lastToolID.flatMap { registry.tool($0) } }
    var recentTools: [AnyTool] {
        let eligible = Set(eligibleTools.map(\.id))
        return recentIDs.filter(eligible.contains).compactMap { registry.tool($0) }
    }

    /// Non-empty selections; when empty the tool runs on the whole document.
    var activeSelections: [NSRange] { selections.filter { $0.length > 0 } }
    var charCount: Int { text.count }
    var lineCount: Int { text.isEmpty ? 1 : text.reduce(into: 1) { if $1 == "\n" { $0 += 1 } } }

    /// What a tool run would act on, for the picker footer.
    var targetDescription: String {
        let n = activeSelections.count
        switch n {
        case 0: return "whole document"
        case 1: return "selection"
        default: return "\(n) selections"
        }
    }

    // MARK: Applying tools

    func openPicker() { errorMessage = nil; showPicker = true }
    func closePicker() { showPicker = false; controller.focus() }

    func repeatLast() {
        guard let tool = lastTool else { openPicker(); return }
        apply(tool)
    }

    func apply(_ tool: AnyTool) {
        showPicker = false
        controller.focus()
        guard !isRunning else { return }
        let snapshot = controller.string
        let full = NSRange(location: 0, length: (snapshot as NSString).length)
        let selected = controller.selectedRanges.filter { $0.length > 0 }
        let targets = selected.isEmpty ? [full] : selected
        let options = lastOptions[tool.id] ?? tool.optionFields.defaults
        errorMessage = nil
        isRunning = true
        Task {
            defer { isRunning = false }
            var outputs: [String] = []
            for (i, range) in targets.enumerated() {
                let piece = (snapshot as NSString).substring(with: range)
                do {
                    let output = try await tool.run(ToolInput(text: piece), options: options)
                    guard case .text(let result) = output.payload else {
                        throw ToolError("\(tool.name) did not produce text")
                    }
                    outputs.append(result)
                } catch {
                    let message = (error as? ToolError)?.description ?? error.localizedDescription
                    errorMessage = targets.count > 1 ? "\(tool.name), selection \(i + 1): \(message)" : "\(tool.name): \(message)"
                    return
                }
            }
            guard controller.string == snapshot else {
                errorMessage = "\(tool.name): the text changed while the tool was running"
                return
            }
            guard controller.replace(ranges: targets, with: outputs) else {
                errorMessage = "\(tool.name): the editor rejected the change"
                return
            }
            // A whole-document run leaves a caret at the end rather than a misleading full selection.
            if selected.isEmpty { controller.setSelectedRanges([NSRange(location: (controller.string as NSString).length, length: 0)]) }
            remember(tool, options: options)
        }
    }

    private func remember(_ tool: AnyTool, options: OptionValues) {
        lastToolID = tool.id
        recentIDs.removeAll { $0 == tool.id }
        recentIDs.insert(tool.id, at: 0)
        recentIDs = Array(recentIDs.prefix(Self.maxRecents))
        lastOptions[tool.id] = options
        let defaults = UserDefaults.standard
        defaults.set(recentIDs, forKey: Keys.recents)
        if let data = try? JSONEncoder().encode(lastOptions) { defaults.set(data, forKey: Keys.options) }
    }

    // MARK: Persistence

    private func scheduleSave() {
        guard persistenceEnabled else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard persistenceEnabled else { return }
        saveTask?.cancel()
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Focus plumbing

struct ScratchpadFocusKey: FocusedValueKey { typealias Value = ScratchpadModel }
extension FocusedValues {
    var scratchpad: ScratchpadModel? {
        get { self[ScratchpadFocusKey.self] }
        set { self[ScratchpadFocusKey.self] = newValue }
    }
}
