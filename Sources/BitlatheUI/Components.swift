import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BitlatheCore

// MARK: - Toasts

@MainActor
@Observable
public final class ToastCenter {
    public static let shared = ToastCenter()
    public struct Toast: Identifiable, Equatable {
        public let id = UUID()
        public let message: String
        public let symbol: String
    }
    public private(set) var current: Toast?
    private var hideTask: Task<Void, Never>?

    public func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        withAnimation(Motion.animation()) { current = Toast(message: message, symbol: symbol) }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.animation()) { self?.current = nil }
        }
    }
}

public struct ToastOverlay: ViewModifier {
    @State private var center = ToastCenter.shared
    public func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = center.current {
                Label(t.message, systemImage: t.symbol)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.bottom, Space.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }
}

public extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}

// MARK: - Clipboard

public enum Clipboard {
    @MainActor
    public static func copy(_ text: String, toast: String? = "Copied") {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if let toast { ToastCenter.shared.show(toast) }
    }

    @MainActor
    public static func copy(_ payload: ToolPayload, toast: String? = "Copied") {
        switch payload {
        case .text(let s): copy(s, toast: toast)
        case .image(let d, _):
            if let img = NSImage(data: d) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([img])
                if let toast { ToastCenter.shared.show(toast) }
            }
        case .data(let d): copy(d.base64EncodedString(), toast: toast)
        case .file(let url):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([url as NSURL])
            if let toast { ToastCenter.shared.show(toast) }
        case .none: break
        }
    }

    public static var string: String? { NSPasteboard.general.string(forType: .string) }

    public static var imageData: (Data, ImageFormat)? {
        let pb = NSPasteboard.general
        if let d = pb.data(forType: .png) { return (d, .png) }
        if let d = pb.data(forType: .tiff), let img = NSImage(data: d), let png = img.pngData { return (png, .png) }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let u = urls.first, let d = try? Data(contentsOf: u), let f = ImageFormat.sniff(d) { return (d, f) }
        return nil
    }

    public static var fileURLs: [URL] {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}

public extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - Small components

public struct CopyButton: View {
    let text: () -> String?
    let label: String
    public init(_ label: String = "Copy", text: @escaping () -> String?) {
        self.label = label
        self.text = text
    }
    public var body: some View {
        Button {
            if let t = text() { Clipboard.copy(t) }
        } label: {
            Label(label, systemImage: "doc.on.doc")
        }
        .help("Copy to clipboard")
        .accessibilityLabel("Copy \(label)")
    }
}

public struct Chip: View {
    let title: String
    let symbol: String?
    let tint: Color
    let action: () -> Void
    public init(_ title: String, symbol: String? = nil, tint: Color = .accentColor, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title).lineLimit(1)
            }
            .font(.callout)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs + 1)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

public struct StatusBadge: View {
    public enum Kind { case success, warning, danger, neutral }
    let text: String
    let kind: Kind
    public init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }
    var color: Color {
        switch kind {
        case .success: Palette.success
        case .warning: Palette.warning
        case .danger: Palette.danger
        case .neutral: .secondary
        }
    }
    var symbol: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .neutral: "circle"
        }
    }
    public var body: some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(color)
    }
}

public struct ErrorBanner: View {
    let error: ToolError
    let onJump: (() -> Void)?
    public init(_ error: ToolError, onJump: (() -> Void)? = nil) {
        self.error = error
        self.onJump = onJump
    }
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(Palette.danger)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(error.message).font(.callout).textSelection(.enabled)
                if let hint = error.hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let loc = error.location {
                Button(loc) { onJump?() }.buttonStyle(.link).font(.caption.monospacedDigit())
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Palette.danger.opacity(0.08))
        .overlay(alignment: .top) { Rectangle().fill(Palette.danger.opacity(0.3)).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error.description)")
    }
}

public struct WarningBanner: View {
    let messages: [String]
    public init(_ messages: [String]) { self.messages = messages }
    public var body: some View {
        if !messages.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    ForEach(messages, id: \.self) { Text($0).font(.caption) }
                }
                Spacer()
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .background(Palette.warning.opacity(0.08))
        }
    }
}

public struct EmptyState: View {
    let symbol: String
    let title: String
    let samples: [ToolSample]
    let acceptsClipboard: Bool
    let onPaste: () -> Void
    let onSample: (ToolSample) -> Void

    public init(symbol: String, title: String, samples: [ToolSample], acceptsClipboard: Bool = true,
                onPaste: @escaping () -> Void, onSample: @escaping (ToolSample) -> Void) {
        self.symbol = symbol
        self.title = title
        self.samples = samples
        self.acceptsClipboard = acceptsClipboard
        self.onPaste = onPaste
        self.onSample = onSample
    }

    public var body: some View {
        VStack(spacing: Space.lg) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if acceptsClipboard {
                Button { onPaste() } label: { Label("Paste from clipboard", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut("v", modifiers: [.command, .option])
            }
            if !samples.isEmpty {
                VStack(spacing: Space.sm) {
                    Text("Try a sample").font(.caption).foregroundStyle(.tertiary)
                    FlowLayout(spacing: Space.sm, rowSpacing: Space.sm) {
                        ForEach(samples.prefix(4)) { s in
                            Chip(s.title, symbol: "sparkle") { onSample(s) }
                                .fixedSize()
                        }
                    }
                    .frame(maxWidth: 420)
                }
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.editorBackground)
    }
}

public struct KeyValueList: View {
    let rows: [MetaRow]
    public init(_ rows: [MetaRow]) { self.rows = rows }

    public var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 460
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        if row.value.isEmpty, row.label.hasPrefix("──") {
                            Text(row.label.replacingOccurrences(of: "── ", with: ""))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                                .padding(.horizontal, Space.lg).padding(.top, Space.lg).padding(.bottom, Space.xs)
                        } else {
                            KeyValueRow(row: row, wide: wide)
                            Divider().padding(.leading, Space.lg)
                        }
                    }
                }
                .padding(.vertical, Space.xs)
            }
        }
        .background(Palette.editorBackground)
    }
}

struct KeyValueRow: View {
    let row: MetaRow
    let wide: Bool
    @State private var hovering = false

    var body: some View {
        let value = Text(row.value)
            .font(row.style == .mono ? Typography.mono : .body)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        let label = Text(row.label).foregroundStyle(.secondary)
        let swatch = KeyValueRow.colour(row.value)
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            if wide {
                label.font(.callout).frame(width: 170, alignment: .leading)
                if let swatch { SwatchDot(color: swatch) }
                value
            } else {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    label.font(.caption)
                    HStack(spacing: Space.sm) {
                        if let swatch { SwatchDot(color: swatch) }
                        value
                    }
                }
            }
            Button { Clipboard.copy(row.value) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
                .help("Copy \(row.label)")
                .accessibilityLabel("Copy \(row.label)")
        }
        .padding(.vertical, wide ? Space.sm : Space.sm - 1)
        .padding(.horizontal, Space.lg)
        .contentShape(Rectangle())
        .background(hovering ? Palette.raised.opacity(0.6) : .clear)
        .onHover { hovering = $0 }
        .contextMenu { Button("Copy \(row.label)") { Clipboard.copy(row.value) } }
        .accessibilityElement(children: .combine)
    }

    /// A value that is exactly a hex colour gets a swatch.
    static func colour(_ s: String) -> Color? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("#"), [4, 7, 9].contains(t.count), let v = UInt32(t.dropFirst(), radix: 16) else { return nil }
        let hex = t.count == 4 ? t.dropFirst().map { "\($0)\($0)" }.joined() : String(t.dropFirst())
        guard let full = UInt32(hex.prefix(6), radix: 16) else { return nil }
        _ = v
        let a = hex.count == 8 ? Double(UInt32(hex.suffix(2), radix: 16) ?? 255) / 255 : 1
        return Color(.sRGB, red: Double((full >> 16) & 0xFF) / 255, green: Double((full >> 8) & 0xFF) / 255, blue: Double(full & 0xFF) / 255, opacity: a)
    }

    var color: Color {
        switch row.style {
        case .success: Palette.success
        case .warning: Palette.warning
        case .danger: Palette.danger
        case .muted: .secondary
        default: .primary
        }
    }
}

public struct SectionCard<Content: View>: View {
    let title: String
    let content: Content
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).font(Typography.headline)
            content
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Split pane

public struct SplitPane<First: View, Second: View>: View {
    @Binding var orientation: SplitOrientation
    @State private var ratio: CGFloat
    @State private var dragStart: CGFloat?
    let minFirst: CGFloat
    let first: First
    let second: Second

    public init(orientation: Binding<SplitOrientation>, initialRatio: CGFloat = 0.5, minFirst: CGFloat = 120,
                @ViewBuilder first: () -> First, @ViewBuilder second: () -> Second) {
        _orientation = orientation
        _ratio = State(initialValue: initialRatio)
        self.minFirst = minFirst
        self.first = first()
        self.second = second()
    }

    public var body: some View {
        GeometryReader { geo in
            let horizontal = orientation == .horizontal
            let total = horizontal ? geo.size.width : geo.size.height
            let firstSize = max(minFirst, min(total - 120, total * ratio))
            ZStack(alignment: .topLeading) {
                if horizontal {
                    HStack(spacing: 0) {
                        first.frame(width: firstSize)
                        divider(horizontal: true)
                        second.frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        first.frame(height: firstSize)
                        divider(horizontal: false)
                        second.frame(maxHeight: .infinity)
                    }
                }
            }
            .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                let pos = horizontal ? v.location.x : v.location.y
                let start = horizontal ? v.startLocation.x : v.startLocation.y
                if dragStart == nil {
                    guard abs(start - firstSize) < 8 else { return }
                    dragStart = start
                }
                ratio = max(0.1, min(0.9, pos / total))
            }.onEnded { _ in dragStart = nil })
        }
    }

    func divider(horizontal: Bool) -> some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(width: horizontal ? 1 : nil, height: horizontal ? nil : 1)
            .overlay {
                Rectangle().fill(.clear)
                    .frame(width: horizontal ? 9 : nil, height: horizontal ? nil : 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { horizontal ? NSCursor.resizeLeftRight.push() : NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
            }
            .zIndex(1)
    }
}

// MARK: - File helpers

public enum FilePanels {
    @MainActor
    public static func open(types: [UTType] = [.data], multiple: Bool = false) -> [URL] {
        let p = NSOpenPanel()
        p.allowedContentTypes = types
        p.allowsMultipleSelection = multiple
        p.canChooseDirectories = false
        return p.runModal() == .OK ? p.urls : []
    }

    @MainActor
    public static func openFolder() -> URL? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url : nil
    }

    @MainActor
    public static func save(_ data: Data, suggestedName: String, type: UTType? = nil) {
        let p = NSSavePanel()
        p.nameFieldStringValue = suggestedName
        if let type { p.allowedContentTypes = [type] }
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try data.write(to: url)
            ToastCenter.shared.show("Saved \(url.lastPathComponent)", symbol: "square.and.arrow.down.fill")
        } catch {
            ToastCenter.shared.show("Could not save: \(error.localizedDescription)", symbol: "xmark.octagon.fill")
        }
    }
}

// MARK: - Image view

public struct PayloadImageView: View {
    let data: Data
    @State private var actualSize = false
    public init(_ data: Data) { self.data = data }

    public var body: some View {
        if let img = NSImage(data: data), let rep = img.representations.first {
            let px = CGSize(width: max(rep.pixelsWide, 1), height: max(rep.pixelsHigh, 1))
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let avail = CGSize(width: max(geo.size.width - Space.xl * 2, 1), height: max(geo.size.height - Space.xl * 2, 1))
                    let fitScale = min(avail.width / px.width, avail.height / px.height)
                    // Retina: one image pixel per screen point is "actual size" for pixel-exact output like QR codes.
                    let scale = actualSize ? 1.0 : fitScale
                    let size = CGSize(width: px.width * scale, height: px.height * scale)
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(scale >= 1 ? .none : .high)
                            .frame(width: size.width, height: size.height)
                            .background(CheckerboardBackground())
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                            .padding(Space.xl)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                    .scrollDisabled(!actualSize)
                }
                HStack(spacing: Space.sm) {
                    Text("\(Int(px.width)) × \(Int(px.height)) px")
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: Space.sm)
                    Button { actualSize.toggle() } label: {
                        Image(systemName: actualSize ? "arrow.down.right.and.arrow.up.left" : "1.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help(actualSize ? "Fit to pane" : "Actual size (1 image pixel per point)")
                    .accessibilityLabel(actualSize ? "Fit to pane" : "Show actual size")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.xs + 1)
                .background(Palette.paneTitle)
                .overlay(alignment: .top) { Divider() }
            }
            .background(Palette.editorBackground)
        } else {
            ContentUnavailableView("Unsupported image", systemImage: "photo.badge.exclamationmark")
        }
    }
}

public struct CheckerboardBackground: View {
    public init() {}
    public var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 8
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    if Int((x + y) / s) % 2 == 0 {
                        ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.gray.opacity(0.15)))
                    }
                    x += s
                }
                y += s
            }
        }
    }
}

// MARK: - Focus plumbing for menu commands

public struct ToolSessionFocusKey: FocusedValueKey {
    public typealias Value = ToolSession
}

public extension FocusedValues {
    var toolSession: ToolSession? {
        get { self[ToolSessionFocusKey.self] }
        set { self[ToolSessionFocusKey.self] = newValue }
    }
}

// MARK: - Custom tool views

/// Tools that need a bespoke body register a builder here. Everything else uses the generic screen.
@MainActor
public enum ToolViewRegistry {
    public typealias Builder = @MainActor (ToolSession) -> AnyView
    private static var builders: [String: Builder] = [:]

    public static func register(_ id: String, _ builder: @escaping Builder) { builders[id] = builder }
    public static func builder(for id: String) -> Builder? { builders[id] }
}
