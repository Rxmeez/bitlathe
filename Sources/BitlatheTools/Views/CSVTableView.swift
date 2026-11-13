import SwiftUI
import AppKit
import BitlatheCore
import BitlatheUI

// MARK: - Model

/// Sort state: column index + direction.
struct CSVSort: Equatable, Sendable {
    var column: Int
    var ascending: Bool
}

enum CSVExportFormat { case csv, json }

/// Pure helpers for turning rows into CSV / JSON text.
enum CSVExport {
    static func csv(header: [String], rows: [[String]], delimiter: Character) -> String {
        CSV.write(header: header, rows: rows, delimiter: delimiter)
    }

    static func jsonString(_ s: String) -> String {
        guard let d = try? JSONEncoder().encode(s), let out = String(data: d, encoding: .utf8) else { return "\"\"" }
        return out
    }

    static func json(header: [String], kinds: [String], rows: [[String]]) -> String {
        let numeric = header.indices.map { $0 < kinds.count && ($0 < kinds.count ? (kinds[$0] == "integer" || kinds[$0] == "number") : false) }
        let objects = rows.map { row -> String in
            let fields = header.indices.map { c -> String in
                let v = c < row.count ? row[c] : ""
                let value: String
                if numeric[c], !v.isEmpty, let d = Double(v.replacingOccurrences(of: ",", with: "")), d.isFinite {
                    value = d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
                } else if numeric[c], v.isEmpty {
                    value = "null"
                } else {
                    value = jsonString(v)
                }
                return "    \(jsonString(header[c])): \(value)"
            }
            return "  {\n" + fields.joined(separator: ",\n") + "\n  }"
        }
        return "[\n" + objects.joined(separator: ",\n") + "\n]\n"
    }
}

@MainActor
@Observable
final class CSVTableModel {
    struct Loaded: Sendable {
        var table: CSV.Table
        var stats: [CSVViewerTool.ColumnStats]
    }

    private(set) var table: CSV.Table?
    private(set) var stats: [CSVViewerTool.ColumnStats] = []
    private(set) var tableID = UUID()
    private(set) var order: [Int] = []
    private(set) var orderID = UUID()
    private(set) var isWorking = false
    var sort: CSVSort? { didSet { if sort != oldValue { scheduleOrder(immediate: true) } } }
    var filter = "" { didSet { if filter != oldValue { scheduleOrder(immediate: false) } } }

    @ObservationIgnored private var parseTask: Task<Void, Never>?
    @ObservationIgnored private var orderTask: Task<Void, Never>?
    @ObservationIgnored private var orderGeneration = 0

    var kinds: [String] { stats.map(\.kind) }
    var header: [String] { table?.header ?? [] }
    var rowCount: Int { table?.rows.count ?? 0 }

    func load(text: String, delimiter: String, header: Bool, immediate: Bool) {
        parseTask?.cancel()
        guard !text.trimmed().isEmpty else {
            table = nil
            stats = []
            order = []
            orderID = UUID()
            tableID = UUID()
            isWorking = false
            return
        }
        parseTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            self?.isWorking = true
            let result: Loaded? = await Task.detached(priority: .userInitiated) {
                var o = CSVViewerTool.Options()
                o.delimiter = delimiter
                o.header = header
                guard let t = try? CSVViewerTool.parse(text, options: o) else { return nil }
                return Loaded(table: t, stats: CSVViewerTool.stats(t))
            }.value
            guard !Task.isCancelled, let self else { return }
            self.isWorking = false
            guard let result else { return }
            if self.table?.header != result.table.header { self.sort = nil }
            self.table = result.table
            self.stats = result.stats
            self.tableID = UUID()
            self.scheduleOrder(immediate: true)
        }
    }

    func scheduleOrder(immediate: Bool) {
        orderTask?.cancel()
        guard let table else { return }
        orderGeneration += 1
        let gen = orderGeneration
        let filter = self.filter
        let sort = self.sort
        let kinds = self.kinds
        orderTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Self.computeOrder(table: table, kinds: kinds, filter: filter, sort: sort)
            }.value
            guard !Task.isCancelled, let self, gen == self.orderGeneration else { return }
            self.order = result
            self.orderID = UUID()
        }
    }

    // MARK: Filtering & sorting (off the main actor)

    nonisolated static func computeOrder(table: CSV.Table, kinds: [String], filter: String, sort: CSVSort?) -> [Int] {
        var idx = Array(table.rows.indices)
        if let q = parseFilter(filter, header: table.header) {
            idx = idx.filter { i in
                let row = table.rows[i]
                if let col = q.column {
                    return col < row.count && contains(row[col], q.needle)
                }
                return row.contains { contains($0, q.needle) }
            }
        }
        if let sort, sort.column < table.header.count {
            let c = sort.column
            let asc = sort.ascending
            let kind = c < kinds.count ? kinds[c] : "text"
            func cell(_ i: Int) -> String { c < table.rows[i].count ? table.rows[i][c] : "" }
            if kind == "integer" || kind == "number" {
                let keys: [Double?] = table.rows.indices.map { Double(cell($0).replacingOccurrences(of: ",", with: "")) }
                idx.sort { a, b in
                    switch (keys[a], keys[b]) {
                    case let (x?, y?): return x == y ? a < b : (asc ? x < y : x > y)
                    case (nil, nil): return a < b
                    case (nil, _): return false   // empties always last
                    case (_, nil): return true
                    }
                }
            } else {
                let keys: [String] = table.rows.indices.map { cell($0).lowercased() }
                idx.sort { a, b in
                    let x = keys[a], y = keys[b]
                    if x.isEmpty != y.isEmpty { return !x.isEmpty }
                    if x == y { return a < b }
                    return asc ? x < y : x > y
                }
            }
        }
        return idx
    }

    nonisolated static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .literal]) != nil
    }

    /// `column:value` limits the match to a column (name matched case-insensitively, exact first, then prefix).
    nonisolated static func parseFilter(_ text: String, header: [String]) -> (column: Int?, needle: String)? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let colon = t.firstIndex(of: ":") {
            let name = t[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = t[t.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                let col = header.firstIndex { $0.lowercased() == name } ?? header.firstIndex { $0.lowercased().hasPrefix(name) }
                if let col {
                    return value.isEmpty ? nil : (col, value)
                }
            }
        }
        return (nil, t)
    }

    // MARK: Exporting

    func rows(at positions: [Int]) -> [[String]] {
        guard let table else { return [] }
        return positions.compactMap { $0 < order.count ? table.rows[order[$0]] : nil }
    }

    var visibleRows: [[String]] {
        guard let table else { return [] }
        return order.map { table.rows[$0] }
    }

    func text(for rows: [[String]], as format: CSVExportFormat) -> String {
        switch format {
        case .csv: CSVExport.csv(header: header, rows: rows, delimiter: table?.delimiter ?? ",")
        case .json: CSVExport.json(header: header, kinds: kinds, rows: rows)
        }
    }

    func column(_ c: Int) -> [String] {
        guard let table else { return [] }
        return order.map { c < table.rows[$0].count ? table.rows[$0][c] : "" }
    }
}

// MARK: - SwiftUI view

struct CSVTableView: View {
    @Bindable var session: ToolSession
    @State private var model = CSVTableModel()
    @State private var editorCollapsed = false
    @State private var showStats = false

    private var source: [String] {
        [session.inputText, session.option("delimiter").stringValue, session.option("header").boolValue ? "1" : "0"]
    }

    var body: some View {
        VStack(spacing: 0) {
            OptionBar(session: session)
            inputArea
            if model.table != nil {
                toolbar
                Divider()
                HStack(spacing: 0) {
                    CSVNSTable(model: model,
                               onSort: { model.sort = $0 },
                               onCopy: { Clipboard.copy($0, toast: $1) })
                    if showStats {
                        Divider()
                        CSVStatsPanel(stats: model.stats, rowCount: model.rowCount)
                            .frame(width: Layout.inspectorIdeal)
                    }
                }
                .overlay {
                    if model.isWorking {
                        ProgressView().controlSize(.small).padding(Space.md)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.medium))
                    }
                }
            } else if session.inputText.trimmed().isEmpty {
                EmptyState(symbol: session.tool.symbol, title: "Paste or drop CSV or TSV data, or open a file",
                           samples: session.tool.samples, onPaste: { session.pasteFromClipboard() }, onSample: { session.useSample($0) })
            } else {
                Spacer()
            }
            if let error = session.error { ErrorBanner(error) }
        }
        .onAppear {
            reload(immediate: true)
            if !session.inputText.isEmpty { editorCollapsed = true }
        }
        .onChange(of: source) { _, _ in reload(immediate: false) }
        .onChange(of: session.inputText) { old, new in
            if new.count - old.count > 20 { editorCollapsed = true }
            if new.isEmpty { editorCollapsed = false }
        }
    }

    func reload(immediate: Bool) {
        model.load(text: session.inputText, delimiter: session.option("delimiter").stringValue,
                   header: session.option("header").boolValue, immediate: immediate)
    }

    // MARK: Input

    @ViewBuilder var inputArea: some View {
        if editorCollapsed && model.table != nil {
            HStack(spacing: Space.sm) {
                Image(systemName: "doc.plaintext").foregroundStyle(.secondary)
                Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Paste", systemImage: "doc.on.clipboard") { session.pasteFromClipboard() }
                Button("Open…", systemImage: "folder") { session.openFile() }
                Button("Edit Input", systemImage: "chevron.down") { editorCollapsed = false }
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .padding(.horizontal, Space.lg)
            .frame(height: Layout.optionBarHeight)
            .background(Palette.paneTitle)
            .overlay(alignment: .bottom) { Divider() }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in dropFiles(providers) }
        } else if model.table != nil || !session.inputText.isEmpty {
            VStack(spacing: 0) {
                CodeEditor(text: $session.inputText, language: .plain, isEditable: true, placeholder: "Paste CSV or TSV here",
                           error: session.error, config: EditorConfig.current, selection: $session.selection,
                           onDrop: { session.load(urls: $0) })
                    .frame(height: 150)
                HStack {
                    Spacer()
                    Button("Collapse", systemImage: "chevron.up") { editorCollapsed = true }
                        .buttonStyle(.borderless).controlSize(.small).disabled(model.table == nil)
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.xs)
                .background(Palette.paneTitle)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }

    var summary: String {
        guard let t = model.table else { return "" }
        let delim = t.delimiter == "\t" ? "tab" : String(t.delimiter)
        let name = session.inputFileName.map { "\($0) · " } ?? ""
        return "\(name)\(t.rows.count.formatted()) rows × \(t.header.count) columns · delimiter \(delim)"
    }

    func dropFiles(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for p in providers where p.hasItemConformingToTypeIdentifier("public.file-url") {
            handled = true
            p.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in session.load(urls: [url]) }
            }
        }
        return handled
    }

    // MARK: Toolbar

    var toolbar: some View {
        HStack(spacing: Space.md) {
            HStack(spacing: Space.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary).imageScale(.small)
                TextField("", text: $model.filter, prompt: Text("Filter, or column:value"))
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !model.filter.isEmpty {
                    Button { model.filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                        .accessibilityLabel("Clear filter")
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs + 1)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.small))
            .frame(maxWidth: 320)

            Text("\(model.order.count.formatted()) of \(model.rowCount.formatted()) rows")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Toggle(isOn: $showStats) { Label("Column Stats", systemImage: "chart.bar.doc.horizontal") }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show column statistics")
            Menu {
                Button("Export as CSV…") { export(.csv) }
                Button("Export as JSON…") { export(.json) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
                .help("Export the filtered and sorted rows")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .background(Palette.chrome)
    }

    func export(_ format: CSVExportFormat) {
        let text = model.text(for: model.visibleRows, as: format)
        let base = session.inputFileName.map { ($0 as NSString).deletingPathExtension } ?? "table"
        switch format {
        case .csv: FilePanels.save(Data(text.utf8), suggestedName: "\(base).csv", type: .commaSeparatedText)
        case .json: FilePanels.save(Data(text.utf8), suggestedName: "\(base).json", type: .json)
        }
    }
}

// MARK: - Stats panel

struct CSVStatsPanel: View {
    let stats: [CSVViewerTool.ColumnStats]
    let rowCount: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Column Stats").font(.headline)
                Spacer()
                Text("\(stats.count) columns").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            Divider()
            ScrollView {
                LazyVStack(spacing: Space.sm) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                        StatCard(stats: s, rowCount: rowCount)
                    }
                }
                .padding(Space.md)
            }
        }
        .background(Palette.paneTitle)
    }
}

private struct StatCard: View {
    let stats: CSVViewerTool.ColumnStats
    let rowCount: Int

    var tint: Color {
        switch stats.kind {
        case "integer", "number": .blue
        case "date": .purple
        case "boolean": .orange
        default: .gray
        }
    }

    func fmt(_ d: Double) -> String { CSVViewerTool.format(d) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text(stats.name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: Space.xs)
                Text(stats.kind)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Space.xxs)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint == .gray ? Color.secondary : tint)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                ProgressView(value: Double(stats.nonEmpty), total: Double(max(rowCount, 1)))
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .controlSize(.mini)
                HStack {
                    Text("\(stats.nonEmpty.formatted()) filled").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(stats.unique.formatted()) unique").foregroundStyle(.secondary)
                }
                .font(.caption.monospacedDigit())
            }
            VStack(spacing: Space.xxs) {
                row("Min", stats.min)
                row("Max", stats.max)
                row("Mean", stats.mean.map(fmt))
                row("Sum", stats.sum.map(fmt))
            }
        }
        .padding(Space.md)
        .background(Palette.editorBackground, in: RoundedRectangle(cornerRadius: Radius.medium))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium).stroke(Palette.separator.opacity(0.6), lineWidth: 0.5))
    }

    @ViewBuilder func row(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.caption).foregroundStyle(Palette.subtle)
                Spacer(minLength: Space.sm)
                Text(value).font(Typography.captionMono).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
        }
    }
}

// MARK: - AppKit table

private final class CSVHeaderView: NSTableHeaderView {
    var menuProvider: ((Int) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let col = column(at: convert(event.locationInWindow, from: nil))
        return col >= 0 ? menuProvider?(col) : nil
    }
}

private final class CSVNSTableView: NSTableView {
    var menuProvider: (() -> NSMenu?)?
    var copyHandler: (() -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let r = row(at: convert(event.locationInWindow, from: nil))
        guard r >= 0 else { return nil }
        if !selectedRowIndexes.contains(r) { selectRowIndexes([r], byExtendingSelection: false) }
        return menuProvider?()
    }
    @objc func copy(_ sender: Any?) { copyHandler?() }
}

private final class CSVCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.sm),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.sm),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

struct CSVNSTable: NSViewRepresentable {
    let model: CSVTableModel
    let onSort: (CSVSort?) -> Void
    let onCopy: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = CSVNSTableView()
        let header = CSVHeaderView()
        tv.headerView = header
        tv.style = .fullWidth
        tv.usesAlternatingRowBackgroundColors = true
        tv.allowsMultipleSelection = true
        tv.allowsColumnReordering = true
        tv.allowsColumnResizing = true
        // Last column absorbs spare width; wider files scroll horizontally.
        tv.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tv.rowHeight = Space.xl - Space.xxs
        tv.intercellSpacing = NSSize(width: Space.md, height: 0)
        tv.dataSource = context.coordinator
        tv.delegate = context.coordinator
        tv.menuProvider = { [weak c = context.coordinator] in c?.rowMenu() }
        tv.copyHandler = { [weak c = context.coordinator] in c?.copySelection() }
        header.menuProvider = { [weak c = context.coordinator] in c?.headerMenu(column: $0) }
        context.coordinator.tableView = tv
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.model = model
        c.onSort = onSort
        c.onCopy = onCopy
        c.sync()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var model: CSVTableModel?
        var onSort: ((CSVSort?) -> Void)?
        var onCopy: ((String, String) -> Void)?
        fileprivate weak var tableView: CSVNSTableView?
        private var shownTableID: UUID?
        private var shownOrderID: UUID?
        private var suppressSort = false
        private var menuColumn = 0

        static let rowNumberID = NSUserInterfaceItemIdentifier("#")
        func isNumeric(_ c: Int) -> Bool {
            guard let k = model?.kinds, c < k.count else { return false }
            return k[c] == "integer" || k[c] == "number"
        }

        func sync() {
            guard let tv = tableView, let model else { return }
            if shownTableID != model.tableID {
                shownTableID = model.tableID
                rebuildColumns(tv, model)
            }
            if shownOrderID != model.orderID {
                shownOrderID = model.orderID
                tv.reloadData()
            }
            // Reflect model sort (e.g. reset on new data) in the header indicator.
            let want = model.sort
            let have = tv.sortDescriptors.first.flatMap { d in d.key.flatMap { Int($0.dropFirst()) }.map { CSVSort(column: $0, ascending: d.ascending) } }
            if want != have {
                suppressSort = true
                tv.sortDescriptors = want.map { [NSSortDescriptor(key: "c\($0.column)", ascending: $0.ascending)] } ?? []
                suppressSort = false
            }
        }

        func rebuildColumns(_ tv: NSTableView, _ model: CSVTableModel) {
            suppressSort = true
            tv.sortDescriptors = []
            for col in tv.tableColumns { tv.removeTableColumn(col) }
            defer { suppressSort = false }
            guard let table = model.table else { return }
            let rn = NSTableColumn(identifier: Self.rowNumberID)
            rn.title = "#"
            rn.width = 52
            rn.minWidth = 36
            rn.maxWidth = 90
            rn.headerCell.alignment = .right
            tv.addTableColumn(rn)
            let sample = table.rows.prefix(300)
            for (c, name) in table.header.enumerated() {
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(c)"))
                col.title = name
                col.sortDescriptorPrototype = NSSortDescriptor(key: "c\(c)", ascending: true)
                // Measure with the fonts the cells and header actually use.
                let cellFont: NSFont = isNumeric(c) ? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) : .systemFont(ofSize: NSFont.systemFontSize)
                let headerFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
                let longestCell = sample.reduce(CGFloat(0)) { acc, row in
                    guard c < row.count else { return acc }
                    return max(acc, (row[c] as NSString).size(withAttributes: [.font: cellFont]).width)
                }
                let headerWidth = (name as NSString).size(withAttributes: [.font: headerFont]).width + Space.xl   // room for the sort arrow
                col.width = min(max(max(longestCell, headerWidth) + Space.lg, 72), 360)
                col.minWidth = 48
                col.maxWidth = 1200
                col.headerCell.alignment = isNumeric(c) ? .right : .left
                tv.addTableColumn(col)
            }
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int { model?.order.count ?? 0 }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let model, let table = model.table, let tableColumn, row < model.order.count else { return nil }
            let id = tableColumn.identifier
            let reuse = NSUserInterfaceItemIdentifier("cell")
            let cell = (tableView.makeView(withIdentifier: reuse, owner: nil) as? CSVCellView) ?? {
                let v = CSVCellView(frame: .zero)
                v.identifier = reuse
                return v
            }()
            let source = model.order[row]
            let label = cell.label
            let small = NSFont.systemFontSize - 1
            if id == Self.rowNumberID {
                label.stringValue = String(source + 1)
                label.font = .monospacedDigitSystemFont(ofSize: small - 1, weight: .regular)
                label.textColor = .tertiaryLabelColor
                label.alignment = .right
                return cell
            }
            guard let c = Int(id.rawValue.dropFirst()), source < table.rows.count else { return cell }
            let value = c < table.rows[source].count ? table.rows[source][c] : ""
            if value.isEmpty {
                label.stringValue = "—"
                label.textColor = .quaternaryLabelColor
            } else {
                label.stringValue = value
                label.textColor = .labelColor
            }
            if isNumeric(c) {
                label.font = .monospacedSystemFont(ofSize: small, weight: .regular)
                label.alignment = .right
            } else {
                label.font = .systemFont(ofSize: small)
                label.alignment = .left
            }
            return cell
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !suppressSort else { return }
            guard let d = tableView.sortDescriptors.first, let key = d.key, let c = Int(key.dropFirst()) else {
                onSort?(nil)
                return
            }
            onSort?(CSVSort(column: c, ascending: d.ascending))
        }

        // MARK: Menus & copy

        var selectedPositions: [Int] { tableView.map { Array($0.selectedRowIndexes) } ?? [] }

        func rowMenu() -> NSMenu {
            let n = selectedPositions.count
            let menu = NSMenu()
            menu.addItem(item(n > 1 ? "Copy \(n) Rows as CSV" : "Copy Row as CSV", #selector(copyRowsCSV)))
            menu.addItem(item(n > 1 ? "Copy \(n) Rows as JSON" : "Copy Row as JSON", #selector(copyRowsJSON)))
            return menu
        }

        func headerMenu(column: Int) -> NSMenu? {
            guard let tv = tableView, column < tv.tableColumns.count else { return nil }
            let id = tv.tableColumns[column].identifier
            guard id != Self.rowNumberID, let c = Int(id.rawValue.dropFirst()) else { return nil }
            menuColumn = c
            let menu = NSMenu()
            menu.addItem(item("Copy Column", #selector(copyColumn)))
            return menu
        }

        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            return i
        }

        func copySelection() { copyRows(.csv) }

        @objc func copyRowsCSV() { copyRows(.csv) }
        @objc func copyRowsJSON() { copyRows(.json) }

        func copyRows(_ format: CSVExportFormat) {
            guard let model else { return }
            let rows = model.rows(at: selectedPositions)
            guard !rows.isEmpty else { return }
            onCopy?(model.text(for: rows, as: format), rows.count == 1 ? "Copied row" : "Copied \(rows.count) rows")
        }

        @objc func copyColumn() {
            guard let model else { return }
            let values = model.column(menuColumn)
            onCopy?(values.joined(separator: "\n"), "Copied \(values.count) values")
        }
    }
}
