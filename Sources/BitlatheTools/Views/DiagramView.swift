import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

/// Draws a tool's `Diagram` (GitHub Actions workflows, Kubernetes manifests): cards in columns joined by arrows.
/// Click a card to see everything about it and to light up what it connects to. Zoom with the buttons or a pinch;
/// copy the picture or its Mermaid source.
struct DiagramResultView: View {
    @Bindable var session: ToolSession
    let output: ToolOutput
    // Screenshot harness: `-BLDiagramSelect 'job:test'` opens with that card selected.
    @State private var selection: String? = {
        #if DEBUG
        UserDefaults.standard.string(forKey: "BLDiagramSelect")
        #else
        nil
        #endif
    }()
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat?
    @State private var fittedFor: String?
    @Environment(\.colorScheme) private var scheme

    private var diagram: Diagram? {
        output.facets.first { $0.title == Diagram.facetTitle }?.payload.text.flatMap(Diagram.decode)
    }

    var body: some View {
        if let diagram, !diagram.nodes.isEmpty {
            let geometry = DiagramGeometry(diagram)
            let key = diagram.nodes.map(\.id).joined(separator: "|")
            VStack(spacing: 0) {
                toolbar(diagram, geometry)
                HStack(spacing: 0) {
                    GeometryReader { viewport in
                        ScrollView([.horizontal, .vertical]) {
                            DiagramCanvas(diagram: diagram, geometry: geometry, selection: selection) { id in
                                withAnimation(Motion.animation()) { selection = selection == id ? nil : id }
                            }
                            .scaleEffect(zoom, anchor: .topLeading)
                            .frame(width: geometry.size.width * zoom, height: geometry.size.height * zoom, alignment: .topLeading)
                            .frame(minWidth: viewport.size.width, minHeight: viewport.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(Motion.animation()) { selection = nil } }
                        }
                        .gesture(MagnifyGesture()
                            .onChanged { value in
                                let base = pinchBase ?? zoom
                                pinchBase = base
                                zoom = Self.clamp(base * value.magnification)
                            }
                            .onEnded { _ in pinchBase = nil })
                        .onAppear { fit(geometry, in: viewport.size, key: key) }
                        .onChange(of: key) { fit(geometry, in: viewport.size, key: key) }
                    }
                    if let id = selection, let node = diagram.nodes.first(where: { $0.id == id }) {
                        Divider()
                        DiagramInspector(diagram: diagram, node: node) { next in
                            withAnimation(Motion.animation()) { selection = next }
                        }
                        .frame(width: 300)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .background(Palette.editorBackground)
                .onExitCommand { if selection != nil { withAnimation(Motion.animation()) { selection = nil } } }
                if !output.metadata.isEmpty {
                    Divider()
                    MetadataStrip(rows: Array(output.metadata.filter { $0.value.count <= 60 }.prefix(6)))
                }
            }
            .onChange(of: key) { if let s = selection, !diagram.nodes.contains(where: { $0.id == s }) { selection = nil } }
        } else {
            Text("Nothing to draw").foregroundStyle(Palette.subtle).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    static func clamp(_ z: CGFloat) -> CGFloat { min(max(z, 0.3), 2.5) }

    /// Fits a new diagram to the window, but never so small that the cards cannot be read (or past 100 %): a wide
    /// diagram scrolls instead. A diagram whose nodes did not change keeps the zoom the person chose.
    private func fit(_ geometry: DiagramGeometry, in viewport: CGSize, key: String) {
        guard fittedFor != key, viewport.width > 0 else { return }
        fittedFor = key
        let scale = min(viewport.width / geometry.size.width, viewport.height / geometry.size.height)
        zoom = Self.clamp(min(1, max(scale, Self.readable)))
    }

    /// Below this the cards' small print stops being legible.
    static let readable: CGFloat = 0.8

    /// The tool screen for the visualisers: the same input and output panes, with most of the width for the drawing.
    struct Screen: View {
        @Bindable var session: ToolSession
        var body: some View {
            let config = EditorConfig.current
            VStack(spacing: 0) {
                OptionBar(session: session)
                SplitPane(orientation: $session.orientation, initialRatio: 0.34) {
                    InputPane(session: session, config: config)
                } second: {
                    OutputPane(session: session, config: config)
                }
            }
        }
    }

    private func toolbar(_ diagram: Diagram, _ geometry: DiagramGeometry) -> some View {
        HStack(spacing: Space.sm) {
            Text(summary(diagram)).font(.caption).foregroundStyle(Palette.subtle).lineLimit(1)
            Spacer(minLength: Space.sm)
            Button { zoom = Self.clamp(zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out").accessibilityLabel("Zoom out")
            Button("\(Int((zoom * 100).rounded()))%") { zoom = 1 }
                .font(.caption.monospacedDigit()).frame(minWidth: 40).help("Actual size")
            Button { zoom = Self.clamp(zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in").accessibilityLabel("Zoom in")
            Button { fittedFor = nil } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                .help("Fit to window").accessibilityLabel("Fit to window")
            Divider().frame(height: 14)
            Button { copyMermaid(diagram) } label: { Label("Mermaid", systemImage: "doc.on.doc") }
                .help("Copy the diagram as Mermaid, for a README or a pull request")
            Button { copyImage(diagram, geometry) } label: { Label("Image", systemImage: "photo") }
                .help("Copy the diagram as a picture")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Space.lg)
        .frame(height: 30)
        .background(Palette.chrome)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func summary(_ d: Diagram) -> String {
        let defined = d.nodes.filter { !$0.external }.count
        var parts = ["\(defined) item\(defined == 1 ? "" : "s")", "\(d.edges.count) link\(d.edges.count == 1 ? "" : "s")"]
        let missing = d.nodes.count - defined
        if missing > 0 { parts.append("\(missing) not defined here") }
        return parts.joined(separator: " · ") + (selection == nil ? " · click a card for details" : "")
    }

    private func copyMermaid(_ d: Diagram) {
        Clipboard.copy(d.mermaid(), toast: "Copied the diagram as Mermaid")
    }

    private func copyImage(_ d: Diagram, _ g: DiagramGeometry) {
        let content = DiagramCanvas(diagram: d, geometry: g, selection: nil) { _ in }
            .frame(width: g.size.width, height: g.size.height)
            .background(Palette.editorBackground)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        ToastCenter.shared.show("Copied the diagram as an image", symbol: "photo")
    }
}

// MARK: - Geometry

enum DiagramMetrics {
    static let cardWidth: CGFloat = 220
    static let columnGap: CGFloat = 100
    static let rowGap: CGFloat = 18
    static let margin: CGFloat = 28
    static let padding: CGFloat = 10
    static let lineHeight: CGFloat = 15
    static let maxLines = 5

    static func height(_ n: Diagram.Node) -> CGFloat {
        var h = padding * 2 + 14 + 3 + 18          // kind row, title
        if let s = n.subtitle, !s.isEmpty { h += 15 }
        let lines = min(n.lines.count, maxLines) + (n.lines.count > maxLines ? 1 : 0)
        if lines > 0 { h += 7 + CGFloat(lines) * lineHeight }
        return h
    }
}

/// Where every card goes: columns from `Diagram.columns()`, each centred on the tallest.
struct DiagramGeometry {
    var frames: [String: CGRect] = [:]
    var size: CGSize = .zero

    init(_ d: Diagram) {
        let byID = Dictionary(uniqueKeysWithValues: d.nodes.map { ($0.id, $0) })
        let columns = d.columns()
        let heights = columns.map { col in
            col.compactMap { byID[$0] }.map(DiagramMetrics.height).reduce(0, +) + CGFloat(max(col.count - 1, 0)) * DiagramMetrics.rowGap
        }
        let tallest = heights.max() ?? 0
        for (c, col) in columns.enumerated() {
            var y = DiagramMetrics.margin + (tallest - heights[c]) / 2
            let x = DiagramMetrics.margin + CGFloat(c) * (DiagramMetrics.cardWidth + DiagramMetrics.columnGap)
            for id in col {
                guard let n = byID[id] else { continue }
                let h = DiagramMetrics.height(n)
                frames[id] = CGRect(x: x, y: y, width: DiagramMetrics.cardWidth, height: h)
                y += h + DiagramMetrics.rowGap
            }
        }
        size = CGSize(width: DiagramMetrics.margin * 2 + CGFloat(columns.count) * DiagramMetrics.cardWidth + CGFloat(max(columns.count - 1, 0)) * DiagramMetrics.columnGap,
                      height: DiagramMetrics.margin * 2 + tallest)
    }
}

@MainActor
extension Diagram.Tone {
    var color: Color {
        switch self {
        case .trigger: .purple
        case .job: Palette.accent
        case .network: .teal
        case .workload: .blue
        case .config: .orange
        case .secret: .pink
        case .storage: .brown
        case .identity: .green
        case .policy: .indigo
        case .other: .gray
        }
    }
}

// MARK: - Canvas

struct DiagramCanvas: View {
    let diagram: Diagram
    let geometry: DiagramGeometry
    let selection: String?
    let select: (String) -> Void

    private var connected: Set<String> {
        guard let s = selection else { return [] }
        return Set(diagram.edges.filter { $0.from == s || $0.to == s }.flatMap { [$0.from, $0.to] })
    }

    var body: some View {
        let lit = connected
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for edge in diagram.edges {
                    guard let a = geometry.frames[edge.from], let b = geometry.frames[edge.to] else { continue }
                    let on = selection != nil && (edge.from == selection || edge.to == selection)
                    let dim = selection != nil && !on
                    let tone = diagram.nodes.first { $0.id == (edge.from == selection ? edge.to : edge.from) }?.tone ?? .other
                    let color = on ? tone.color : Palette.subtle.opacity(dim ? 0.18 : 0.55)
                    Self.draw(edge, from: a, to: b, color: color, width: on ? 2.2 : 1.3, in: &ctx, labelled: !dim)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .allowsHitTesting(false)
            ForEach(diagram.nodes) { node in
                if let f = geometry.frames[node.id] {
                    DiagramCard(node: node, selected: node.id == selection)
                        .frame(width: f.width, height: f.height, alignment: .topLeading)
                        .opacity(selection == nil || lit.contains(node.id) || node.id == selection ? 1 : 0.38)
                        .onTapGesture { select(node.id) }
                        .offset(x: f.minX, y: f.minY)
                }
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    }

    /// A curve from the right side of `a` to the left side of `b`, or a loop round the side when `b` is not to the right.
    static func draw(_ edge: Diagram.Edge, from a: CGRect, to b: CGRect, color: Color, width: CGFloat, in ctx: inout GraphicsContext, labelled: Bool) {
        let start: CGPoint, end: CGPoint, c1: CGPoint, c2: CGPoint
        if b.minX > a.maxX + 1 {
            start = CGPoint(x: a.maxX, y: a.midY)
            end = CGPoint(x: b.minX, y: b.midY)
            let dx = max(36, (end.x - start.x) * 0.5)
            c1 = CGPoint(x: start.x + dx, y: start.y)
            c2 = CGPoint(x: end.x - dx, y: end.y)
        } else {
            // Same column or backwards: leave on the right, come round, enter on the right.
            start = CGPoint(x: a.maxX, y: a.midY)
            end = CGPoint(x: b.maxX, y: b.midY)
            let out = max(a.maxX, b.maxX) + 56
            c1 = CGPoint(x: out, y: start.y)
            c2 = CGPoint(x: out, y: end.y)
        }
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: c1, control2: c2)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: edge.dashed ? [5, 4] : []))

        // Arrowhead along the last stretch of the curve.
        let angle = atan2(end.y - c2.y, end.x - c2.x)
        let size: CGFloat = 7
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - size * cos(angle - .pi / 7), y: end.y - size * sin(angle - .pi / 7)))
        head.addLine(to: CGPoint(x: end.x - size * cos(angle + .pi / 7), y: end.y - size * sin(angle + .pi / 7)))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))

        guard labelled, let label = edge.label, !label.isEmpty else { return }
        // The curve's midpoint (cubic Bézier at t = 0.5).
        let mid = CGPoint(x: 0.125 * start.x + 0.375 * c1.x + 0.375 * c2.x + 0.125 * end.x,
                          y: 0.125 * start.y + 0.375 * c1.y + 0.375 * c2.y + 0.125 * end.y)
        // A label wider than the gap between columns would sit on the cards: shorten it until it fits.
        let room = DiagramMetrics.columnGap - 14
        var shown = label
        var text = ctx.resolve(Text(shown).font(.caption2).foregroundStyle(Palette.subtle))
        while shown.count > 2, text.measure(in: CGSize(width: 400, height: 20)).width > room {
            shown = String(shown.dropLast(2)) + "…"
            if shown.hasSuffix("……") { shown = String(shown.dropLast(2)) + "…" }
            text = ctx.resolve(Text(shown).font(.caption2).foregroundStyle(Palette.subtle))
        }
        let size2 = text.measure(in: CGSize(width: 400, height: 20))
        let box = CGRect(x: mid.x - size2.width / 2 - 4, y: mid.y - size2.height / 2 - 1, width: size2.width + 8, height: size2.height + 2)
        ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(Palette.editorBackground))
        ctx.draw(text, at: mid)
    }
}

struct DiagramCard: View {
    let node: Diagram.Node
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        let tone = node.tone.color
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Space.xs) {
                Image(systemName: node.symbol).font(.caption2.weight(.semibold)).foregroundStyle(tone)
                Text((node.badge ?? "").uppercased()).font(.caption2.weight(.semibold)).tracking(0.4).foregroundStyle(tone).lineLimit(1)
                Spacer(minLength: 0)
                if node.external { Image(systemName: "questionmark.circle").font(.caption2).foregroundStyle(Palette.subtle).help("Not defined in this input") }
            }
            .frame(height: 14)
            Text(node.title).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle).frame(height: 18)
            if let s = node.subtitle, !s.isEmpty {
                Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).frame(height: 15)
            }
            if !node.lines.isEmpty {
                Divider().padding(.vertical, 3)
                ForEach(Array(node.lines.prefix(DiagramMetrics.maxLines).enumerated()), id: \.offset) { _, line in
                    Text(line).font(Typography.captionMono).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        .frame(height: DiagramMetrics.lineHeight, alignment: .leading)
                }
                if node.lines.count > DiagramMetrics.maxLines {
                    Text("+\(node.lines.count - DiagramMetrics.maxLines) more").font(.caption2).foregroundStyle(Palette.subtle)
                        .frame(height: DiagramMetrics.lineHeight, alignment: .leading)
                }
            }
        }
        .padding(DiagramMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.editorBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .background(tone.opacity(hovering || selected ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(selected ? tone : tone.opacity(node.external ? 0.5 : 0.35),
                              style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: node.external ? [4, 3] : []))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(tone).frame(width: 3).padding(.vertical, DiagramMetrics.padding)
                .opacity(node.external ? 0.4 : 1)
        }
        .shadow(color: .black.opacity(selected ? 0.18 : 0.06), radius: selected ? 8 : 3, y: selected ? 3 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .onHover { hovering = $0 }
        .help(node.subtitle.map { "\(node.title) — \($0)" } ?? node.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([node.badge, node.title, node.subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Shows details and connections")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Inspector

struct DiagramInspector: View {
    let diagram: Diagram
    let node: Diagram.Node
    let select: (String?) -> Void

    var body: some View {
        let names = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, $0) })
        let incoming = diagram.edges.filter { $0.to == node.id }
        let outgoing = diagram.edges.filter { $0.from == node.id }
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.sm) {
                    Image(systemName: node.symbol).font(.title3).foregroundStyle(node.tone.color).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        if let b = node.badge { Text(b.uppercased()).font(.caption2.weight(.semibold)).tracking(0.4).foregroundStyle(node.tone.color) }
                        Text(node.title).font(.headline).textSelection(.enabled)
                        if let s = node.subtitle, !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                    Spacer(minLength: 0)
                    Button { select(nil) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.subtle).help("Close (Esc)").accessibilityLabel("Close details")
                }
                if !node.details.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ForEach(Array(node.details.enumerated()), id: \.offset) { _, d in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.label).font(.caption).foregroundStyle(.secondary)
                                Text(d.value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if !incoming.isEmpty || !outgoing.isEmpty {
                    Divider()
                    Text("CONNECTIONS").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(Palette.subtle)
                    ForEach(Array(incoming.enumerated()), id: \.offset) { _, e in link("arrow.left", names[e.from], e.label) }
                    ForEach(Array(outgoing.enumerated()), id: \.offset) { _, e in link("arrow.right", names[e.to], e.label) }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.chrome)
    }

    @ViewBuilder
    private func link(_ arrow: String, _ other: Diagram.Node?, _ label: String?) -> some View {
        if let other {
            Button { select(other.id) } label: {
                HStack(spacing: Space.sm) {
                    Image(systemName: arrow).font(.caption).foregroundStyle(Palette.subtle).frame(width: 14)
                    Image(systemName: other.symbol).font(.caption).foregroundStyle(other.tone.color)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(other.title).font(.callout).lineLimit(1)
                        Text([other.badge, label].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3).padding(.horizontal, Space.sm)
                .background(Palette.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show \(other.title)")
        }
    }
}
