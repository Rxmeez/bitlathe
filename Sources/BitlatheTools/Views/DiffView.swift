import SwiftUI
import BitlatheCore
import BitlatheUI

// MARK: - Model

/// One line on one side of the diff, with optional intra-line highlight segments.
struct DiffCell: Sendable, Equatable {
    struct Seg: Sendable, Equatable { var text: String; var changed: Bool }
    var no: Int
    var text: String
    var segs: [Seg]?
}

struct DiffPair: Sendable {
    var left: DiffCell?
    var right: DiffCell?
}

struct DiffModel: Sendable {
    enum Part: Sendable {
        case equal([DiffPair])
        case change(block: Int, pairs: [DiffPair])
    }
    var parts: [Part] = []
    var blockCount = 0
    var added = 0
    var removed = 0
    var changed = 0
    var leftCount = 0
    var rightCount = 0
    var isIdentical: Bool { blockCount == 0 }
}

enum DiffResult: Sendable {
    case lines(DiffModel)
    case json([DiffEngine.JSONChange])
    case failure(String)
}

struct DiffSettings: Hashable, Sendable {
    var a: String
    var b: String
    var granularity: String
    var ignoreWhitespace: Bool
    var ignoreCase: Bool
    var ignoreOrder: Bool
}

enum DiffComputer {
    static func compute(_ s: DiffSettings) -> DiffResult {
        if s.granularity == "json" {
            do {
                let ja = try JSONParser.parse(s.a.trimmed().isEmpty ? "null" : s.a, options: .json5)
                let jb = try JSONParser.parse(s.b.trimmed().isEmpty ? "null" : s.b, options: .json5)
                return .json(DiffEngine.jsonDiff(ja, jb, ignoreOrder: s.ignoreOrder))
            } catch {
                return .failure(error.localizedDescription)
            }
        }
        return .lines(lineModel(s))
    }

    private static func normLine(_ l: String, _ s: DiffSettings) -> String {
        var t = l
        if s.ignoreWhitespace { t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed() }
        if s.ignoreCase { t = t.lowercased() }
        return t
    }

    static func lineModel(_ s: DiffSettings) -> DiffModel {
        let la = s.a.isEmpty ? [] : DiffEngine.lines(s.a)
        let lb = s.b.isEmpty ? [] : DiffEngine.lines(s.b)
        var model = DiffModel()
        model.leftCount = la.count
        model.rightCount = lb.count
        let edits = DiffEngine.diff(la.map { normLine($0, s) }, lb.map { normLine($0, s) })

        var equalRun: [DiffPair] = []
        var dels: [Int] = []
        var inss: [Int] = []

        func flushEqual() {
            if !equalRun.isEmpty { model.parts.append(.equal(equalRun)); equalRun = [] }
        }
        func flushBlock() {
            guard !dels.isEmpty || !inss.isEmpty else { return }
            var pairs: [DiffPair] = []
            let n = min(dels.count, inss.count)
            for k in 0..<n {
                let (l, r) = intraLine(la[dels[k]], lb[inss[k]], s)
                pairs.append(DiffPair(left: DiffCell(no: dels[k] + 1, text: la[dels[k]], segs: l),
                                      right: DiffCell(no: inss[k] + 1, text: lb[inss[k]], segs: r)))
            }
            for k in n..<dels.count { pairs.append(DiffPair(left: DiffCell(no: dels[k] + 1, text: la[dels[k]]), right: nil)) }
            for k in n..<inss.count { pairs.append(DiffPair(left: nil, right: DiffCell(no: inss[k] + 1, text: lb[inss[k]]))) }
            model.changed += n
            model.removed += dels.count - n
            model.added += inss.count - n
            model.parts.append(.change(block: model.blockCount, pairs: pairs))
            model.blockCount += 1
            dels = []; inss = []
        }

        for e in edits {
            switch e.op {
            case .equal:
                flushBlock()
                if let o = e.oldIndex, let n = e.newIndex {
                    equalRun.append(DiffPair(left: DiffCell(no: o + 1, text: la[o]), right: DiffCell(no: n + 1, text: lb[n])))
                }
            case .delete:
                flushEqual()
                if let o = e.oldIndex { dels.append(o) }
            case .insert:
                flushEqual()
                if let n = e.newIndex { inss.append(n) }
            }
        }
        flushBlock()
        flushEqual()
        return model
    }

    /// Word (or character) level diff of a paired removed/added line. Returns nil segments when the lines share too little to be useful.
    private static func intraLine(_ a: String, _ b: String, _ s: DiffSettings) -> ([DiffCell.Seg]?, [DiffCell.Seg]?) {
        guard a.utf16.count < 1500, b.utf16.count < 1500 else { return (nil, nil) }
        let chars = s.granularity == "char"
        let ta = chars ? DiffEngine.characters(a) : DiffEngine.words(a)
        let tb = chars ? DiffEngine.characters(b) : DiffEngine.words(b)
        func norm(_ t: String) -> String {
            var x = t
            if s.ignoreCase { x = x.lowercased() }
            if s.ignoreWhitespace, x.allSatisfy(\.isWhitespace) { x = " " }
            return x
        }
        let edits = DiffEngine.diff(ta.map(norm), tb.map(norm))
        var left: [DiffCell.Seg] = [], right: [DiffCell.Seg] = []
        func add(_ list: inout [DiffCell.Seg], _ text: String, _ changed: Bool) {
            if let last = list.last, last.changed == changed { list[list.count - 1].text += text } else { list.append(.init(text: text, changed: changed)) }
        }
        var shared = 0
        for e in edits {
            switch e.op {
            case .equal:
                if let o = e.oldIndex, let n = e.newIndex {
                    add(&left, ta[o], false); add(&right, tb[n], false)
                    if !ta[o].allSatisfy(\.isWhitespace) { shared += ta[o].count }
                }
            case .delete:
                if let o = e.oldIndex { add(&left, ta[o], true) }
            case .insert:
                if let n = e.newIndex { add(&right, tb[n], true) }
            }
        }
        let longest = max(a.filter { !$0.isWhitespace }.count, b.filter { !$0.isWhitespace }.count)
        if longest == 0 || Double(shared) / Double(longest) < 0.3 { return (nil, nil) }
        return (left, right)
    }
}

// MARK: - Display items

struct DiffItem: Identifiable {
    enum Kind { case equal, delete, insert, change, fold }
    var id: String
    var kind: Kind
    var left: DiffCell?
    var right: DiffCell?
    var block: Int?
    var foldPart = 0
    var foldCount = 0
}

struct DiffLayout {
    var items: [DiffItem] = []
    var blockAnchors: [String] = []

    static func build(_ model: DiffModel, unified: Bool, context: Int, expanded: Set<Int>) -> DiffLayout {
        var out = DiffLayout()
        out.blockAnchors = Array(repeating: "", count: model.blockCount)
        for (p, part) in model.parts.enumerated() {
            switch part {
            case .equal(let lines):
                let head = p == 0 ? 0 : context
                let tail = p == model.parts.count - 1 ? 0 : context
                let hidden = lines.count - head - tail
                if hidden >= 2, !expanded.contains(p) {
                    for i in 0..<head { out.items.append(equalItem(lines[i], "e\(p)-\(i)")) }
                    out.items.append(DiffItem(id: "f\(p)", kind: .fold, foldPart: p, foldCount: hidden))
                    for i in (lines.count - tail)..<lines.count { out.items.append(equalItem(lines[i], "e\(p)-\(i)")) }
                } else {
                    for (i, l) in lines.enumerated() { out.items.append(equalItem(l, "e\(p)-\(i)")) }
                }
            case .change(let block, let pairs):
                out.blockAnchors[block] = "c\(p)-0"
                if unified {
                    var i = 0
                    for pr in pairs where pr.left != nil {
                        out.items.append(DiffItem(id: "c\(p)-\(i)", kind: .delete, left: pr.left, right: nil, block: block)); i += 1
                    }
                    for pr in pairs where pr.right != nil {
                        out.items.append(DiffItem(id: "c\(p)-\(i)", kind: .insert, left: nil, right: pr.right, block: block)); i += 1
                    }
                } else {
                    for (i, pr) in pairs.enumerated() {
                        let kind: DiffItem.Kind = pr.left != nil && pr.right != nil ? .change : (pr.left != nil ? .delete : .insert)
                        out.items.append(DiffItem(id: "c\(p)-\(i)", kind: kind, left: pr.left, right: pr.right, block: block))
                    }
                }
            }
        }
        return out
    }

    private static func equalItem(_ pr: DiffPair, _ id: String) -> DiffItem {
        DiffItem(id: id, kind: .equal, left: pr.left, right: pr.right, block: nil)
    }
}

// MARK: - View

struct DiffToolView: View {
    @Bindable var session: ToolSession
    @State private var result: DiffResult?
    @State private var unified = false
    @State private var showInputs = true
    @State private var expanded: Set<Int> = []
    @State private var currentBlock = -1
    @State private var nameB: String?
    @State private var scrollTarget: String?

    private var settings: DiffSettings {
        DiffSettings(a: session.inputText, b: session.secondaryText,
                     granularity: session.option("granularity").stringValue,
                     ignoreWhitespace: session.option("ignoreWhitespace").boolValue,
                     ignoreCase: session.option("ignoreCase").boolValue,
                     ignoreOrder: session.option("ignoreOrder").boolValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            OptionBar(session: session)
            if showInputs {
                inputs
                    .frame(height: 190)
                Divider()
            }
            toolbar
            Divider()
            diffArea
        }
        .task(id: settings) {
            let s = settings
            if s.a.isEmpty && s.b.isEmpty { result = nil; return }
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
            let r = await Task.detached(priority: .userInitiated) { DiffComputer.compute(s) }.value
            if Task.isCancelled { return }
            expanded = []
            currentBlock = -1
            result = r
        }
    }

    // MARK: Inputs

    private var inputs: some View {
        let config = EditorConfig.current
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                PaneTitle(title: session.inputFileName ?? "Original") {
                    openButton { urls in session.load(urls: urls) }
                }
                CodeEditor(text: $session.inputText, language: .plain, isEditable: true, placeholder: "Paste or drop the original text",
                           config: config, onDrop: { session.load(urls: $0) })
            }
            VStack(spacing: Space.sm) {
                Button { swapInputs() } label: { Image(systemName: "arrow.left.arrow.right") }
                    .buttonStyle(.borderless)
                    .help("Swap Original and Changed")
                    .accessibilityLabel("Swap Original and Changed")
            }
            .frame(width: Space.xxl)
            .frame(maxHeight: .infinity)
            .background(Palette.paneTitle)
            VStack(spacing: 0) {
                PaneTitle(title: nameB ?? "Changed") {
                    openButton { urls in loadB(urls) }
                }
                CodeEditor(text: $session.secondaryText, language: .plain, isEditable: true, placeholder: "Paste or drop the changed text",
                           config: config, onDrop: { loadB($0) })
            }
        }
    }

    private func openButton(_ handler: @escaping ([URL]) -> Void) -> some View {
        Button {
            let u = FilePanels.open(multiple: false)
            if !u.isEmpty { handler(u) }
        } label: { Image(systemName: "folder") }
            .buttonStyle(.borderless).controlSize(.small).help("Open a file")
            .accessibilityLabel("Open a file")
    }

    private func loadB(_ urls: [URL]) {
        guard let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) else { return }
        nameB = url.lastPathComponent
        session.secondaryText = s
    }

    private func swapInputs() {
        let a = session.inputText, b = session.secondaryText
        let nA = session.inputFileName
        session.inputText = b
        session.secondaryText = a
        session.inputFileName = nameB
        nameB = nA
    }

    // MARK: Toolbar

    private var isJSON: Bool { settings.granularity == "json" }

    private var toolbar: some View {
        HStack(spacing: Space.sm) {
            summaryChips
            Spacer()
            if case .lines(let m)? = result, !m.isIdentical {
                Text(currentBlock >= 0 ? "Change \(currentBlock + 1) of \(m.blockCount)" : "\(m.blockCount) \(m.blockCount == 1 ? "change" : "changes")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { step(-1, m.blockCount) } label: { Image(systemName: "chevron.up") }
                    .keyboardShortcut("[", modifiers: .command).help("Previous change (⌘[)")
                    .accessibilityLabel("Previous change")
                Button { step(1, m.blockCount) } label: { Image(systemName: "chevron.down") }
                    .keyboardShortcut("]", modifiers: .command).help("Next change (⌘])")
                    .accessibilityLabel("Next change")
            }
            if !isJSON {
                Picker("View", selection: $unified) {
                    Text("Side by Side").tag(false)
                    Text("Unified").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            }
            Button { withAnimation(Motion.animation()) { showInputs.toggle() } } label: {
                Image(systemName: showInputs ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            .help(showInputs ? "Hide the input editors" : "Show the input editors")
            .accessibilityLabel(showInputs ? "Hide inputs" : "Show inputs")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Space.md)
        .frame(height: Layout.optionBarHeight)
        .background(Palette.chrome)
    }

    @ViewBuilder private var summaryChips: some View {
        switch result {
        case .lines(let m):
            HStack(spacing: Space.xs) {
                DiffChip(text: "+\(m.added)", label: "added", tint: Palette.success)
                DiffChip(text: "−\(m.removed)", label: "removed", tint: Palette.danger)
                DiffChip(text: "~\(m.changed)", label: "changed", tint: Palette.warning)
            }
        case .json(let changes):
            HStack(spacing: Space.xs) {
                DiffChip(text: "+\(changes.filter { $0.kind == .added }.count)", label: "added", tint: Palette.success)
                DiffChip(text: "−\(changes.filter { $0.kind == .removed }.count)", label: "removed", tint: Palette.danger)
                DiffChip(text: "~\(changes.filter { $0.kind == .changed || $0.kind == .typeChanged || $0.kind == .moved }.count)", label: "changed", tint: Palette.warning)
            }
        default:
            Text("Paste or drop two texts to compare").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func step(_ d: Int, _ count: Int) {
        guard count > 0, let layout else { return }
        currentBlock = currentBlock < 0 ? (d > 0 ? 0 : count - 1) : (currentBlock + d + count) % count
        if layout.blockAnchors.indices.contains(currentBlock) { scrollTarget = layout.blockAnchors[currentBlock] }
    }

    // MARK: Diff area

    private var contextLines: Int {
        session.options["context"] == nil ? 3 : max(0, session.option("context").intValue)
    }

    private var layout: DiffLayout? {
        guard case .lines(let m)? = result else { return nil }
        return DiffLayout.build(m, unified: unified, context: contextLines, expanded: expanded)
    }

    @ViewBuilder private var diffArea: some View {
        switch result {
        case nil:
            VStack(spacing: Space.sm) {
                Image(systemName: "arrow.left.and.right.text.vertical").font(.system(size: 28, weight: .light)).foregroundStyle(.quaternary)
                Text(showInputs ? "The diff appears here as you type" : "Nothing to compare yet").font(.callout).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.editorBackground)
        case .failure(let msg)?:
            VStack(spacing: 0) {
                ErrorBanner(ToolError(msg))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.editorBackground)
        case .json(let changes)?:
            JSONChangeList(changes: changes)
        case .lines(let m)?:
            if m.isIdentical {
                VStack(spacing: Space.sm) {
                    Image(systemName: "checkmark.circle").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.success)
                    Text("No differences").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.editorBackground)
            } else if let layout {
                DiffRows(layout: layout, unified: unified, currentBlock: currentBlock,
                         digits: String(max(m.leftCount, m.rightCount)).count, scrollTarget: $scrollTarget) { part in
                    withAnimation(Motion.animation()) { _ = expanded.insert(part) }
                }
            }
        }
    }
}

struct DiffChip: View {
    let text: String
    let label: String
    let tint: Color
    var body: some View {
        HStack(spacing: Space.xs) {
            Text(text).font(.caption.weight(.semibold).monospacedDigit())
            Text(label).font(.caption)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xxs)
        .lineLimit(1)
        .fixedSize()
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rows

struct DiffRows: View {
    let layout: DiffLayout
    let unified: Bool
    let currentBlock: Int
    let digits: Int
    @Binding var scrollTarget: String?
    let onExpand: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(layout.items) { item in
                        Group {
                            if item.kind == .fold {
                                FoldRow(count: item.foldCount) { onExpand(item.foldPart) }
                            } else if unified {
                                UnifiedRow(item: item, digits: digits)
                            } else {
                                SideBySideRow(item: item, digits: digits)
                            }
                        }
                        .overlay(alignment: .leading) {
                            if let b = item.block, b == currentBlock { Rectangle().fill(Palette.accent).frame(width: Space.xxs) }
                        }
                        .id(item.id)
                    }
                }
            }
            .background(Palette.editorBackground)
            .onChange(of: scrollTarget) { _, id in
                guard let id else { return }
                withAnimation(Motion.animation(Motion.normal)) { proxy.scrollTo(id, anchor: .center) }
                scrollTarget = nil
            }
        }
    }
}

private func cellText(_ cell: DiffCell, tint: Color) -> Text {
    func tabs(_ s: String) -> String { s.replacingOccurrences(of: "\t", with: "    ") }
    guard let segs = cell.segs else { return Text(cell.text.isEmpty ? " " : tabs(cell.text)) }
    var out = AttributedString()
    for s in segs {
        var a = AttributedString(tabs(s.text))
        if s.changed { a.backgroundColor = tint.opacity(0.35) }
        out += a
    }
    return Text(out)
}

struct SideBySideRow: View {
    let item: DiffItem
    let digits: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            side(item.left, tint: Palette.danger, filled: item.kind == .delete || item.kind == .change)
            Rectangle().fill(Palette.separator).frame(width: 1)
            side(item.right, tint: Palette.success, filled: item.kind == .insert || item.kind == .change)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func side(_ cell: DiffCell?, tint: Color, filled: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(cell.map { String($0.no) } ?? "")
                .font(Typography.monoSmall.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: CGFloat(digits) * 8 + Space.lg, alignment: .trailing)
                .padding(.trailing, Space.sm)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(filled && cell != nil ? tint.opacity(0.18) : Color.clear)
            if let cell {
                cellText(cell, tint: tint)
                    .font(Typography.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.sm)
            } else {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cell == nil ? Palette.raised.opacity(0.6) : (filled ? tint.opacity(0.10) : Color.clear))
        .accessibilityElement(children: .combine)
    }
}

struct UnifiedRow: View {
    let item: DiffItem
    let digits: Int

    var body: some View {
        let tint: Color = item.kind == .delete ? Palette.danger : Palette.success
        let filled = item.kind == .delete || item.kind == .insert
        let cell = item.kind == .insert ? item.right : item.left
        let w = CGFloat(digits) * 8 + Space.md
        HStack(alignment: .top, spacing: 0) {
            Text(item.left.map { String($0.no) } ?? "").frame(width: w, alignment: .trailing)
            Text(item.right.map { String($0.no) } ?? "").frame(width: w, alignment: .trailing)
            Text(item.kind == .delete ? "−" : (item.kind == .insert ? "+" : " "))
                .foregroundStyle(filled ? tint : Color.secondary)
                .frame(width: Space.xl)
            if let cell {
                cellText(cell, tint: tint)
                    .font(Typography.mono)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(Typography.monoSmall.monospacedDigit())
        .foregroundStyle(.tertiary)
        .padding(.trailing, Space.sm)
        .background(filled ? tint.opacity(0.10) : Color.clear)
        .accessibilityElement(children: .combine)
    }
}

struct FoldRow: View {
    let count: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: "ellipsis").imageScale(.small)
                Text("\(count) unchanged \(count == 1 ? "line" : "lines")")
                Spacer()
                Text("Click to expand").font(.caption2).opacity(hover ? 1 : 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.md)
            .frame(height: Space.xl)
            .frame(maxWidth: .infinity)
            .background(hover ? Palette.accent.opacity(0.12) : Palette.raised)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("Expand \(count) unchanged lines")
    }
}

// MARK: - JSON changes

struct JSONChangeList: View {
    let changes: [DiffEngine.JSONChange]

    var body: some View {
        if changes.isEmpty {
            VStack(spacing: Space.sm) {
                Image(systemName: "checkmark.circle").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.success)
                Text("The JSON documents are structurally identical").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.editorBackground)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(changes.enumerated()), id: \.offset) { _, c in
                        row(c)
                        Divider()
                    }
                }
            }
            .background(Palette.editorBackground)
        }
    }

    private func tint(_ k: DiffEngine.JSONChange.Kind) -> Color {
        switch k {
        case .added: Palette.success
        case .removed: Palette.danger
        case .typeChanged: Palette.warning
        case .changed: Palette.accent
        case .moved: Color.secondary
        }
    }

    private func label(_ k: DiffEngine.JSONChange.Kind) -> String {
        k == .typeChanged ? "type" : k.rawValue
    }

    private func row(_ c: DiffEngine.JSONChange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Text(label(c.kind).uppercased())
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xxs)
                .frame(width: 72)
                .background(tint(c.kind).opacity(0.15), in: Capsule())
                .foregroundStyle(tint(c.kind))
            Text(c.path)
                .font(Typography.mono)
                .textSelection(.enabled)
                .frame(minWidth: 140, maxWidth: 320, alignment: .leading)
            values(c)
                .font(Typography.mono)
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .accessibilityElement(children: .combine)
    }

    private func values(_ c: DiffEngine.JSONChange) -> Text {
        switch c.kind {
        case .added: Text(c.after ?? "").foregroundColor(Palette.success)
        case .removed: Text(c.before ?? "").foregroundColor(Palette.danger)
        case .moved: Text(c.before ?? "").foregroundColor(.secondary)
        default:
            Text(c.before ?? "").foregroundColor(Palette.danger) + Text("  →  ").foregroundColor(.secondary) + Text(c.after ?? "").foregroundColor(Palette.success)
        }
    }
}

// MARK: - Registration

@MainActor
enum DiffToolViewRegistration {
    static func register() {
        ToolViewRegistry.register(DiffTool.id) { session in AnyView(DiffToolView(session: session)) }
    }
}
