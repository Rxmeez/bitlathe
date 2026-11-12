import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BitlatheCore

// MARK: - Drop handling

extension ToolSession {
    /// Whether this tool can take an image as input (image tools, and text tools with a "read" mode like QR / barcode).
    public var acceptsImages: Bool {
        if tool.io.input == .image { return true }
        return tool.optionFields.contains { field in
            guard field.key == "mode", case .segmented(let choices) = field.kind else { return false }
            return choices.contains { $0.value == "read" }
        }
    }

    /// Handles providers from a SwiftUI drop: file URLs (Finder) first, then raw image data (Safari, screenshots).
    @discardableResult
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL? = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
                guard let url else { return }
                Task { @MainActor [weak self] in self?.load(urls: [url]) }
            }
            return true
        }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor [weak self] in self?.loadDroppedImage(data) }
            }
            return true
        }
        return false
    }
}

extension View {
    /// Makes the view a drop target for files and images, reporting hover state.
    func inputDropTarget(_ session: ToolSession, isTargeted: Binding<Bool>) -> some View {
        onDrop(of: [.fileURL, .image], isTargeted: isTargeted) { providers in
            session.handleDrop(providers)
        }
    }
}

// MARK: - Empty drop zone

struct DropZone: View {
    @Bindable var session: ToolSession
    @State private var isTargeted = false

    private var isImage: Bool { session.tool.io.input == .image }
    private var title: String { isImage ? "Drop an image here" : "Drop a file here" }
    private var accepted: String {
        isImage ? "PNG, JPEG, HEIC, GIF, TIFF, WebP, BMP, SVG" : "Any file, or paste text"
    }
    private var symbol: String { isImage ? "photo.on.rectangle.angled" : "arrow.down.doc" }

    var body: some View {
        ZStack {
            Palette.editorBackground
            VStack(spacing: Space.lg) {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(isTargeted ? Palette.accent : Color.secondary)
                    .scaleEffect(isTargeted ? 1.1 : 1)
                VStack(spacing: Space.xs) {
                    Text(isTargeted ? "Release to open" : title).font(.headline)
                    Text(accepted).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: Space.sm) {
                    Button("Choose…") { session.openFile() }
                        .buttonStyle(.borderedProminent)
                    Button { session.pasteFromClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                        .keyboardShortcut("v", modifiers: [.command, .option])
                }
                .controlSize(.regular)
                .fixedSize()
                if !session.tool.samples.isEmpty {
                    FlowLayout(spacing: Space.sm, rowSpacing: Space.sm) {
                        ForEach(session.tool.samples.prefix(3)) { s in
                            Chip(s.title, symbol: "sparkle") { session.useSample(s) }.fixedSize()
                        }
                    }
                    .frame(maxWidth: 360)
                }
                if let notice = session.inputNotice {
                    InputNotice(text: notice)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(isTargeted ? Palette.accent.opacity(0.08) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .strokeBorder(isTargeted ? Palette.accent : Palette.separator,
                                  style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [7, 5]))
            }
            .padding(Space.lg)
        }
        .animation(Motion.animation(), value: isTargeted)
        .inputDropTarget(session, isTargeted: $isTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Inline message for rejected drops; cleared by the next successful load or Clear.
struct InputNotice: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(Palette.warning)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(Palette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .frame(maxWidth: 420)
            .accessibilityLabel(text)
    }
}

// MARK: - Loaded image

struct LoadedImageInput: View {
    @Bindable var session: ToolSession
    let data: Data
    let format: ImageFormat
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.inputFileName ?? "Image").font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text(details).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: Space.sm)
                Button("Replace…") { session.openFile() }.fixedSize()
                Button("Remove", role: .destructive) { session.clear() }.fixedSize()
            }
            .controlSize(.small)
            .padding(.horizontal, Space.md)
            .frame(height: 42)
            .background(Palette.chrome)
            .overlay(alignment: .bottom) { Divider() }
            if let notice = session.inputNotice {
                InputNotice(text: notice).padding(Space.sm)
            }
            PayloadImageView(data)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .background(Palette.accent.opacity(0.08))
                    .overlay { Label("Drop to replace", systemImage: "arrow.down.doc").font(.headline).foregroundStyle(Palette.accent) }
                    .padding(Space.sm)
                    .allowsHitTesting(false)
            }
        }
        .animation(Motion.animation(), value: isTargeted)
        .inputDropTarget(session, isTargeted: $isTargeted)
    }

    var details: String {
        var parts: [String] = []
        if let img = NSImage(data: data), let rep = img.representations.first {
            parts.append("\(max(rep.pixelsWide, 1)) × \(max(rep.pixelsHigh, 1)) px")
        }
        parts.append(format.rawValue.uppercased())
        parts.append(ByteFormatter.string(data.count))
        return parts.joined(separator: " · ")
    }
}

// MARK: - File card

struct FileCard: View {
    let url: URL
    /// Nil for read-only display (e.g. a file output); then only Reveal is offered.
    var session: ToolSession?
    @State private var isTargeted = false

    var body: some View {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey])
        ZStack {
            Palette.editorBackground
            VStack(spacing: Space.lg) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().interpolation(.high)
                    .frame(width: 72, height: 72)
                VStack(spacing: Space.xs) {
                    Text(url.lastPathComponent).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Text(facts(values)).font(.callout).foregroundStyle(.secondary)
                    if let date = values?.contentModificationDate {
                        Text("Modified \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary)
                    }
                    Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.head)
                }
                VStack(spacing: Space.sm) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    if let session {
                        HStack(spacing: Space.sm) {
                            Button("Replace…") { session.openFile() }
                            Button("Remove", role: .destructive) { session.clear() }
                        }
                    }
                }
                .controlSize(.regular)
                .fixedSize()
                if let notice = session?.inputNotice { InputNotice(text: notice) }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .background(Palette.accent.opacity(0.08))
                        .padding(Space.lg)
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(Motion.animation(), value: isTargeted)
        .modifier(OptionalDrop(session: session, isTargeted: $isTargeted))
    }

    func facts(_ v: URLResourceValues?) -> String {
        var parts: [String] = []
        if let kind = v?.localizedTypeDescription { parts.append(kind) }
        if let size = v?.fileSize { parts.append(ByteFormatter.string(size)) }
        return parts.joined(separator: " · ")
    }
}

private struct OptionalDrop: ViewModifier {
    let session: ToolSession?
    @Binding var isTargeted: Bool
    func body(content: Content) -> some View {
        if let session { content.inputDropTarget(session, isTargeted: $isTargeted) } else { content }
    }
}

// MARK: - Binary output

struct BinaryOutputCard: View {
    let data: Data
    let output: ToolOutput
    @Bindable var session: ToolSession
    let config: EditorConfig
    @State private var showHex = false

    private var fileName: String { output.suggestedFileName ?? "output.bin" }
    private var type: UTType? { UTType(filenameExtension: (fileName as NSString).pathExtension) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Palette.editorBackground
                VStack(spacing: Space.lg) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 64, height: 64)
                    VStack(spacing: Space.xs) {
                        Text(fileName).font(.headline).lineLimit(2).multilineTextAlignment(.center).textSelection(.enabled)
                        Text([type?.localizedDescription ?? "Binary data", ByteFormatter.string(data.count)].joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    VStack(spacing: Space.sm) {
                        Button { session.saveOutput() } label: { Label("Save…", systemImage: "square.and.arrow.down") }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut("s", modifiers: [.command, .shift])
                        Button { Clipboard.copy(data.base64EncodedString()) } label: { Label("Copy as Base64", systemImage: "doc.on.doc") }
                    }
                    .controlSize(.regular)
                    .fixedSize()
                }
                .padding(Space.xl)
            }
            .frame(maxHeight: showHex ? 230 : .infinity)
            Divider()
            VStack(spacing: 0) {
                DisclosureGroup(isExpanded: $showHex) {
                    CodeEditor(text: .constant(HexDump.dump(data.prefix(64 * 1024))), language: .hex, isEditable: false, config: config)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } label: {
                    Text(data.count > 64 * 1024 ? "Hex dump (first 64 KB)" : "Hex dump")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                if showHex { Spacer(minLength: 0) }
            }
            .frame(maxHeight: showHex ? .infinity : nil, alignment: .top)
            .background(Palette.paneTitle)
        }
    }

    var icon: NSImage {
        if let type { return NSWorkspace.shared.icon(for: type) }
        return NSWorkspace.shared.icon(for: .data)
    }
}
