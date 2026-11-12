import SwiftUI
import AppKit
import BitlatheCore

/// State for one tool screen: input, options, output, debounced execution.
@MainActor
@Observable
public final class ToolSession: Identifiable {
    public let id = UUID()
    public private(set) var tool: AnyTool

    public var inputText = "" { didSet { if inputText != oldValue { inputPayloadOverride = nil; scheduleRun() } } }
    public var secondaryText = "" { didSet { if secondaryText != oldValue { scheduleRun() } } }
    /// Non-text input (image, binary, file). Set by drops/opens; cleared when text is edited.
    public var inputPayloadOverride: ToolPayload? { didSet { if inputPayloadOverride != oldValue { scheduleRun(immediate: true) } } }
    public var inputFileName: String?
    public var options: OptionValues { didSet { if options != oldValue { scheduleRun(immediate: true) } } }
    public var selection = NSRange(location: 0, length: 0)

    public private(set) var output: ToolOutput?
    public private(set) var error: ToolError?
    public private(set) var isRunning = false
    public private(set) var lastDuration: Duration = .zero
    public private(set) var runCount = 0
    public var selectedFacet: String?
    public var orientation: SplitOrientation {
        didSet { Settings.shared.setSplitOrientation(orientation, for: tool.id) }
    }
    public var showInspector = false

    /// Hook for the app shell: "use output in another tool".
    public var openInTool: ((String, String) -> Void)?

    private var runTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    public static let debounce: Duration = .milliseconds(120)

    public init(tool: AnyTool, input: String = "", options: OptionValues = [:]) {
        self.tool = tool
        self.options = tool.optionFields.defaults.merging(options) { _, new in new }
        self.orientation = Settings.shared.storedSplitOrientation(for: tool.id) ?? (Self.prefersCompactInput(tool) ? .vertical : .horizontal)
        if !input.isEmpty {
            self.inputText = input
            scheduleRun(immediate: true)
        } else if tool.io.input == .none {
            scheduleRun(immediate: true)
        }
    }

    /// Tools whose inputs are a single short line (a timestamp, a colour, a CIDR block) get a short input strip
    /// above a tall output instead of a half-empty side-by-side split.
    public static func prefersCompactInput(_ tool: AnyTool) -> Bool {
        guard tool.io.input == .text, !tool.io.dualInput, !tool.samples.isEmpty else { return false }
        return tool.samples.allSatisfy { !$0.input.contains("\n") && $0.input.count <= 120 }
    }

    public var compactInput: Bool { Self.prefersCompactInput(tool) }

    public var inputPayload: ToolPayload {
        if let o = inputPayloadOverride { return o }
        return inputText.isEmpty ? .none : .text(inputText)
    }

    public var hasInput: Bool { !inputPayload.isEmpty || tool.io.input == .none }

    public var inputLanguage: CodeLanguage { tool.io.inputLanguage }
    public var outputLanguage: CodeLanguage { output?.language ?? tool.io.outputLanguage }

    public var outputText: String {
        if let f = selectedFacet, let facet = output?.facets.first(where: { $0.title == f }) { return facet.payload.text ?? "" }
        return output?.text ?? ""
    }

    public var currentOutputPayload: ToolPayload? {
        if let f = selectedFacet, let facet = output?.facets.first(where: { $0.title == f }) { return facet.payload }
        return output?.payload
    }

    // MARK: Running

    public func scheduleRun(immediate: Bool = false) {
        debounceTask?.cancel()
        if immediate {
            run()
        } else {
            debounceTask = Task { [weak self] in
                try? await Task.sleep(for: Self.debounce)
                guard !Task.isCancelled else { return }
                self?.run()
            }
        }
    }

    public func run() {
        runTask?.cancel()
        let payload = inputPayload
        guard !payload.isEmpty || tool.io.input == .none else {
            output = nil
            error = nil
            isRunning = false
            return
        }
        let input = ToolInput(payload, secondary: tool.io.dualInput ? .text(secondaryText) : nil, fileName: inputFileName,
                              selection: selection.length > 0 ? selection.location..<(selection.location + selection.length) : nil)
        let tool = self.tool
        let options = self.options
        let clock = ContinuousClock()
        runTask = Task { [weak self] in
            let slowIndicator = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled { self?.isRunning = true }
            }
            let start = clock.now
            let result: Result<ToolOutput, ToolError>
            do {
                let out = try await tool.run(input, options: options)
                result = .success(out)
            } catch let e as ToolError {
                result = .failure(e)
            } catch is CancellationError {
                slowIndicator.cancel()
                return
            } catch {
                result = .failure(ToolError(error.localizedDescription))
            }
            slowIndicator.cancel()
            guard !Task.isCancelled, let self else { return }
            self.lastDuration = clock.now - start
            self.isRunning = false
            self.runCount += 1
            switch result {
            case .success(let out):
                withAnimation(Motion.animation()) {
                    self.output = out
                    self.error = nil
                }
                if let f = self.selectedFacet, !out.facets.contains(where: { $0.title == f }) { self.selectedFacet = nil }
                self.recordHistory(input: input)
            case .failure(let e):
                withAnimation(Motion.animation()) { self.error = e }
            }
        }
    }

    public func cancel() {
        runTask?.cancel()
        isRunning = false
    }

    private func recordHistory(input: ToolInput) {
        guard Settings.shared.isHistoryEnabled(for: tool.id), case .text(let s) = input.payload else { return }
        historyTask?.cancel()
        let toolID = tool.id
        let opts = options
        historyTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? await DataStore.shared.addHistory(toolID: toolID, input: s, options: opts)
        }
    }

    // MARK: Actions

    public func pasteFromClipboard() {
        if tool.io.input == .image, let (d, f) = Clipboard.imageData {
            setInput(.image(d, f), name: "clipboard.\(f.fileExtension)")
        } else if let s = Clipboard.string {
            inputText = s
        } else if let (d, f) = Clipboard.imageData {
            setInput(.image(d, f), name: "clipboard.\(f.fileExtension)")
        }
    }

    public func useSample(_ s: ToolSample) {
        for (k, v) in s.options { options[k] = v }
        inputText = s.input
    }

    public func clear() {
        inputText = ""
        secondaryText = ""
        inputPayloadOverride = nil
        inputFileName = nil
        output = nil
        error = nil
    }

    public func copyOutput() {
        guard let p = currentOutputPayload, !p.isEmpty else { return }
        Clipboard.copy(p)
    }

    public func replaceClipboardWithOutput() {
        guard let p = currentOutputPayload, !p.isEmpty else { return }
        Clipboard.copy(p, toast: "Clipboard replaced")
    }

    public func swapInputOutput() {
        guard let p = currentOutputPayload else { return }
        if case .text(let t) = p { inputText = t } else { setInput(p, name: nil) }
        output = nil
    }

    public func setInput(_ payload: ToolPayload, name: String?) {
        inputFileName = name
        if case .text(let t) = payload { inputText = t } else {
            inputText = payload.text.map { $0.utf8.count < 2_000_000 ? $0 : "" } ?? ""
            inputPayloadOverride = payload
        }
    }

    public func load(urls: [URL]) {
        guard let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        if urls.count > 1, tool.io.dualInput, let second = try? String(contentsOf: urls[1], encoding: .utf8) {
            secondaryText = second
        }
        if let f = ImageFormat.sniff(data), f != .svg || tool.io.input == .image {
            setInput(.image(data, f), name: url.lastPathComponent)
        } else if tool.io.input == .file {
            setInput(.file(url), name: url.lastPathComponent)
        } else if let s = String(data: data, encoding: .utf8) {
            inputFileName = url.lastPathComponent
            inputText = s
        } else {
            setInput(.data(data), name: url.lastPathComponent)
        }
    }

    public func openFile() {
        let urls = FilePanels.open(multiple: tool.io.dualInput)
        if !urls.isEmpty { load(urls: urls) }
    }

    public func saveOutput() {
        guard let p = currentOutputPayload, let data = p.data else { return }
        let ext: String = switch p {
        case .image(_, let f): f.fileExtension
        case .text: Self.fileExtension(for: outputLanguage)
        default: "bin"
        }
        let base = output?.suggestedFileName ?? (inputFileName.map { ($0 as NSString).deletingPathExtension + "-output" } ?? "output")
        FilePanels.save(data, suggestedName: base.contains(".") && output?.suggestedFileName != nil ? base : "\(base).\(ext)")
    }

    public static func fileExtension(for lang: CodeLanguage) -> String {
        switch lang {
        case .plain: "txt"
        case .javascript: "js"
        case .typescript: "ts"
        case .markdown: "md"
        case .python: "py"
        case .rust: "rs"
        case .kotlin: "kt"
        case .csharp: "cs"
        case .ruby: "rb"
        case .shell: "sh"
        case .dotenv: "env"
        case .regex: "txt"
        case .hex: "txt"
        case .graphql: "graphql"
        default: lang.rawValue
        }
    }

    public func setOption(_ key: String, _ value: OptionValue) { options[key] = value }
    public func option(_ key: String) -> OptionValue { options[key] ?? tool.optionFields.first { $0.key == key }?.defaultValue ?? .string("") }
}
