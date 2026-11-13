import SwiftUI
import BitlatheCore

/// Header → options → split (input | output) → status strip. Custom tools replace the middle.
public struct ToolScreen: View {
    @Bindable var session: ToolSession
    @State private var settings = Settings.shared
    @Environment(\.colorScheme) private var scheme

    public init(session: ToolSession) { self.session = session }

    public var body: some View {
        let config = EditorConfig.current
        VStack(spacing: 0) {
            ToolHeader(session: session)
            if let custom = ToolViewRegistry.builder(for: session.tool.id) {
                custom(session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OptionBar(session: session)
                GenericToolBody(session: session, config: config)
            }
            StatusStrip(session: session)
        }
        .focusedSceneValue(\.toolSession, session)
        .background(Palette.editorBackground)
    }
}

public struct ToolHeader: View {
    @Bindable var session: ToolSession
    @State private var isFavourite = false

    public init(session: ToolSession) { self.session = session }

    public var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: session.tool.symbol)
                .font(.title3)
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.tool.name).font(Typography.title)
                Text(session.tool.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    .help(session.tool.summary)
            }
            Spacer()
            if session.isRunning {
                ProgressView().controlSize(.small)
                Button("Cancel") { session.cancel() }.controlSize(.small)
            }
            HStack(spacing: Space.sm) {
                Button { toggleFavourite() } label: { Image(systemName: isFavourite ? "star.fill" : "star") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isFavourite ? Color.yellow : Color.secondary)
                    .help(isFavourite ? "Remove from favourites" : "Add to favourites")
                    .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
                Menu {
                    if session.tool.io.input != .none {
                        Button("Paste from Clipboard", systemImage: "doc.on.clipboard") { session.pasteFromClipboard() }
                        Button("Open File…", systemImage: "folder") { session.openFile() }
                        Divider()
                    }
                    Button("Save Output…", systemImage: "square.and.arrow.down") { session.saveOutput() }.disabled(session.output == nil)
                    Button("Replace Clipboard with Output", systemImage: "arrow.triangle.2.circlepath") { session.replaceClipboardWithOutput() }.disabled(session.output == nil)
                    if session.tool.io.input == .text, session.tool.io.output == .text {
                        Button("Swap Input and Output", systemImage: "arrow.up.arrow.down") { session.swapInputOutput() }.disabled(session.output == nil)
                    }
                    if ToolViewRegistry.builder(for: session.tool.id) == nil {
                        Button(session.orientation == .horizontal ? "Stack Vertically" : "Side by Side",
                               systemImage: session.orientation == .horizontal ? "rectangle.split.1x2" : "rectangle.split.2x1") {
                            session.orientation = session.orientation == .horizontal ? .vertical : .horizontal
                        }
                    }
                    Divider()
                    Button("Clear", systemImage: "trash", role: .destructive) { session.clear() }
                        .disabled(!session.hasInput || session.tool.io.input == .none)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
                .accessibilityLabel("More actions")
                Button { session.copyOutput() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(session.output == nil)
                    .help("Copy output (⌘⇧C)")
                    .accessibilityLabel("Copy output")
                    .accessibilityHint("Shortcut Command Shift C")
            }
        }
        .padding(.horizontal, Space.lg)
        .frame(height: Layout.headerHeight + Space.sm)
        .background(Palette.chrome)
        .overlay(alignment: .bottom) { Divider() }
        .task(id: session.tool.id) {
            isFavourite = (try? await DataStore.shared.favourites().contains(session.tool.id)) ?? false
        }
    }

    func toggleFavourite() {
        isFavourite.toggle()
        let id = session.tool.id
        let on = isFavourite
        Task {
            try? await DataStore.shared.setFavourite(id, on)
            NotificationCenter.default.post(name: .bitlatheFavouritesChanged, object: nil)
        }
    }
}

public extension Notification.Name {
    static let bitlatheFavouritesChanged = Notification.Name("bitlathe.favouritesChanged")
    static let bitlathePipelinesChanged = Notification.Name("bitlathe.pipelinesChanged")
    static let bitlatheScriptsChanged = Notification.Name("bitlathe.scriptsChanged")
}

struct GenericToolBody: View {
    @Bindable var session: ToolSession
    let config: EditorConfig

    var body: some View {
        if session.tool.io.input == .none {
            OutputPane(session: session, config: config)
        } else {
            SplitPane(orientation: $session.orientation,
                      initialRatio: session.compactInput && session.orientation == .vertical ? 0.2 : 0.5,
                      minFirst: session.compactInput && session.orientation == .vertical ? 96 : 120) {
                InputPane(session: session, config: config)
            } second: {
                OutputPane(session: session, config: config)
            }
        }
    }
}

public struct InputPane: View {
    @Bindable var session: ToolSession
    let config: EditorConfig
    public init(session: ToolSession, config: EditorConfig) {
        self.session = session
        self.config = config
    }

    public var body: some View {
        VStack(spacing: 0) {
            PaneTitle(title: session.inputPayloadOverride == nil ? (session.inputFileName ?? "Input") : "Input", trailing: {
                if session.tool.io.dualInput { Text("A").font(.caption2.bold()).foregroundStyle(.secondary) }
            })
            if let override = session.inputPayloadOverride, case .image(let d, let f) = override {
                LoadedImageInput(session: session, data: d, format: f)
            } else if let override = session.inputPayloadOverride, case .file(let url) = override {
                FileCard(url: url, session: session)
            } else if session.inputText.isEmpty, [.image, .file, .binary].contains(session.tool.io.input) {
                DropZone(session: session)
            } else {
                // One editor instance for both the empty and filled states: swapping views on the first keystroke
                // would drop keyboard focus. The empty state is an overlay that lets clicks through to the editor.
                if let notice = session.inputNotice, !session.inputText.isEmpty { InputNotice(text: notice).padding(Space.sm) }
                ZStack(alignment: .top) {
                    CodeEditor(text: $session.inputText, language: session.inputLanguage, isEditable: true, placeholder: "",
                               error: session.error, annotations: session.output?.annotations.filter { $0.target == .input } ?? [],
                               config: config, selection: $session.selection, onDrop: { session.load(urls: $0) })
                    if session.inputText.isEmpty, !session.hasInput {
                        EmptyState(symbol: session.tool.symbol, title: emptyTitle, samples: session.tool.samples,
                                   onPaste: { session.pasteFromClipboard() }, onSample: { session.useSample($0) })
                    }
                    if let notice = session.inputNotice, session.inputText.isEmpty { InputNotice(text: notice).padding(Space.sm) }
                }
            }
            if session.tool.io.dualInput {
                Divider()
                PaneTitle(title: "Input B", trailing: { EmptyView() })
                CodeEditor(text: $session.secondaryText, language: session.inputLanguage, isEditable: true,
                           placeholder: "Second input", config: config)
            }
        }
    }

    var emptyTitle: String {
        switch session.tool.io.input {
        case .image: "Drop an image here, paste one, or open a file"
        case .file: "Drop a file here or open one"
        case .binary: "Paste or drop data"
        default: "Paste or type \(session.tool.io.inputLanguage == .plain ? "text" : session.tool.io.inputLanguage.displayName) here"
        }
    }
}

struct FileDropSummary: View {
    let url: URL
    var body: some View { FileCard(url: url, session: nil) }
}

public struct PaneTitle<Trailing: View>: View {
    let title: String
    let trailing: Trailing
    public init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }
    public var body: some View {
        HStack {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, Space.md)
        .frame(height: 26)
        .background(Palette.paneTitle)
        .overlay(alignment: .bottom) { Divider() }
    }
}

public struct OutputPane: View {
    @Bindable var session: ToolSession
    let config: EditorConfig
    public init(session: ToolSession, config: EditorConfig) {
        self.session = session
        self.config = config
    }

    public var body: some View {
        VStack(spacing: 0) {
            PaneTitle(title: "Output") {
                if let out = session.output, !out.facets.isEmpty {
                    Picker("Variant", selection: Binding(get: { session.selectedFacet ?? "" }, set: { session.selectedFacet = $0.isEmpty ? nil : $0 })) {
                        Text("Result").tag("")
                        ForEach(out.facets) { Text($0.title).tag($0.title) }
                    }
                    .pickerStyle(.menu).controlSize(.small).labelsHidden().fixedSize()
                    .help("Choose which form of the result to show and copy")
                }
                CopyButton(text: { session.outputText }).labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
                    .disabled(session.output == nil)
            }
            if let error = session.error {
                ErrorBanner(error, onFix: { session.setOption($0.option, $0.value) })
            }
            if let out = session.output {
                WarningBanner(out.warnings)
                OutputContent(payload: session.currentOutputPayload ?? out.payload, output: out, session: session, config: config)
            } else if session.error == nil {
                VStack(spacing: Space.sm) {
                    Spacer()
                    Image(systemName: session.isRunning ? "hourglass" : "arrow.right.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.quaternary)
                        .accessibilityHidden(true)
                    Text(session.tool.io.input == .none ? "Generating…" : "Results appear here as you type")
                        .font(.callout).foregroundStyle(Palette.subtle)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Palette.editorBackground)
            } else {
                Spacer().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.editorBackground)
            }
        }
    }
}

/// Renders a tool's result (text editor, facts, image, binary). Shared by the tool screen and the Smart Box.
public struct OutputContent: View {
    let payload: ToolPayload
    let output: ToolOutput
    @Bindable var session: ToolSession
    let config: EditorConfig

    public init(payload: ToolPayload, output: ToolOutput, session: ToolSession, config: EditorConfig) {
        self.payload = payload
        self.output = output
        self.session = session
        self.config = config
    }

    public var body: some View {
        switch payload {
        case .image(let d, _):
            VStack(spacing: 0) {
                PayloadImageView(d)
                if !output.metadata.isEmpty {
                    Divider()
                    MetadataStrip(rows: Array(output.metadata.prefix(6)))
                }
            }
        case .text(let t):
            if t.isEmpty, !output.metadata.isEmpty {
                KeyValueList(output.metadata)
            } else if !t.contains("\n"), t.count <= 120, output.metadata.count > 6, session.selectedFacet == nil {
                VStack(spacing: 0) {
                    ResultHeader(text: t)
                    Divider()
                    KeyValueList(output.metadata)
                }
            } else {
                let editor = CodeEditor(text: .constant(t), language: session.outputLanguage, isEditable: false,
                                        annotations: output.annotations.filter { $0.target == .output }, config: config)
                if output.metadata.isEmpty || MetadataStrip.fits(output.metadata) {
                    VStack(spacing: 0) {
                        editor
                        if !output.metadata.isEmpty {
                            Divider()
                            MetadataStrip(rows: output.metadata)
                        }
                    }
                } else {
                    // A result plus a table of facts about it (a parsed URL, a decoded JWT). With room, they sit side
                    // by side, each at full height. Stacked, the text leaves half the window empty while the table is
                    // squeezed into a strip that has to be scrolled.
                    GeometryReader { geo in
                        if geo.size.width >= 760 {
                            HStack(spacing: 0) {
                                editor
                                Divider()
                                KeyValueList(output.metadata).frame(width: min(max(geo.size.width * 0.42, 340), 560))
                            }
                        } else {
                            VStack(spacing: 0) {
                                editor
                                Divider()
                                KeyValueList(output.metadata).frame(maxHeight: 220)
                            }
                        }
                    }
                }
            }
        case .data(let d):
            BinaryOutputCard(data: d, output: output, session: session, config: config)
        case .file(let url):
            FileDropSummary(url: url)
        case .none:
            if !output.metadata.isEmpty { KeyValueList(output.metadata) } else { Color.clear }
        }
    }
}

public enum HexDump {
    public static func dump(_ data: Data, bytesPerLine: Int = 16) -> String {
        var out = ""
        out.reserveCapacity(data.count * 4)
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let chunk = bytes[offset..<min(offset + bytesPerLine, bytes.count)]
            out += String(format: "%08x  ", offset)
            var hex = ""
            for (i, b) in chunk.enumerated() {
                hex += String(format: "%02x ", b)
                if i == 7 { hex += " " }
            }
            out += hex.padding(toLength: bytesPerLine * 3 + 1, withPad: " ", startingAt: 0)
            out += " |"
            out += String(chunk.map { $0 >= 32 && $0 < 127 ? Character(UnicodeScalar($0)) : "." })
            out += "|\n"
            offset += bytesPerLine
        }
        return out
    }
}

public struct StatusStrip: View {
    @Bindable var session: ToolSession
    public init(session: ToolSession) { self.session = session }

    public var body: some View {
        HStack(spacing: Space.lg) {
            if session.tool.io.input != .none, !session.hasInput {
                Text("Ready").foregroundStyle(Palette.subtle)
            } else if session.tool.io.input != .none {
                let bytes = session.inputPayload.byteCount
                Text("\(ByteFormatter.string(bytes))").help("Input size")
                if case .text(let t) = session.inputPayload {
                    Text(t.lineCount == 1 ? "1 line" : "\(t.lineCount) lines")
                    Text("UTF-8")
                    let endings = t.lineEndingKinds
                    if endings.count > 1 { Label("Mixed line endings", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.warning) }
                    else if let e = endings.first, e != "LF" { Text(e) }
                }
                if session.inputLanguage != .plain { Text(session.inputLanguage.displayName) }
            }
            Spacer()
            if let out = session.output {
                if let valid = out.isValid {
                    StatusBadge(valid ? "Valid" : "Invalid", valid ? .success : .danger)
                } else if session.error == nil {
                    StatusBadge("OK", .success)
                }
            }
            if session.error != nil { StatusBadge("Error", .danger).fixedSize() }
            if session.runCount > 0 { Text(DurationFormatter.ms(session.lastDuration)).monospacedDigit().help("Processing time") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.lg)
        .frame(height: Layout.statusHeight)
        .background(Palette.chrome)
        .overlay(alignment: .top) { Divider() }
    }
}

/// A compact footer of short facts ("Type object · Depth 2 · Keys 4") under an output editor.
public struct MetadataStrip: View {
    let rows: [MetaRow]
    public init(rows: [MetaRow]) { self.rows = rows }

    public static func fits(_ rows: [MetaRow]) -> Bool {
        rows.count <= 6 && rows.allSatisfy { $0.value.count <= 40 && !$0.value.contains("\n") && $0.label.count <= 24 }
    }

    public var body: some View {
        FlowLayout(spacing: Space.md, rowSpacing: Space.xs) {
            ForEach(rows) { row in
                HStack(spacing: Space.xs) {
                    Text(row.label).foregroundStyle(.secondary)
                    Text(row.value)
                        .font(row.style == .mono ? Typography.captionMono : .caption.weight(.medium))
                        .foregroundStyle(color(row.style))
                        .textSelection(.enabled)
                }
                .font(.caption)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xxs + 1)
                .background(Palette.raised, in: Capsule())
                .contextMenu { Button("Copy \(row.label)") { Clipboard.copy(row.value) } }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paneTitle)
    }

    func color(_ s: MetaRow.Style) -> Color {
        switch s {
        case .success: Palette.success
        case .warning: Palette.warning
        case .danger: Palette.danger
        case .muted: .secondary
        default: .primary
        }
    }
}

/// The primary result of a tool shown large, above its details.
struct ResultHeader: View {
    let text: String
    var body: some View {
        HStack(spacing: Space.md) {
            if let c = KeyValueRow.colour(text) { SwatchDot(color: c, size: 44) }
            Text(text)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer()
            Button { Clipboard.copy(text) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy result")
                .accessibilityLabel("Copy result")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.editorBackground)
    }
}
