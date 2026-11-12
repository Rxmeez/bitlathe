import SwiftUI
import BitlatheCore
import BitlatheUI

/// Custom body for the RegExp Tester: pattern bar, live-highlighted test string, and a tabbed results panel.
struct RegexView: View {
    @Bindable var session: ToolSession
    @State private var orientation: SplitOrientation = .vertical
    @State private var tab: Tab = .matches
    @State private var result: RegexTool.Result?

    enum Tab: String, CaseIterable, Identifiable {
        case matches = "Matches", replace = "Replace", explain = "Explain", cheat = "Cheat Sheet"
        var id: String { rawValue }
    }

    private static let flagInfo: [(String, String)] = [
        ("g", "Global: find all matches"), ("i", "Ignore case"), ("m", "Multiline: ^ and $ match at line breaks"),
        ("s", "Dot matches newline"), ("x", "Extended: ignore whitespace, allow comments"), ("u", "Unicode"),
    ]

    private var pattern: Binding<String> { stringBinding("pattern") }
    private var replacement: Binding<String> { stringBinding("replacement") }
    private var engine: Binding<String> { stringBinding("engine") }
    private var flags: String { session.option("flags").stringValue }

    private func stringBinding(_ key: String) -> Binding<String> {
        Binding(get: { session.option(key).stringValue }, set: { session.setOption(key, .string($0)) })
    }

    var body: some View {
        VStack(spacing: 0) {
            patternBar
            Divider()
            SplitPane(orientation: $orientation, initialRatio: 0.52, minFirst: 240) {
                testPane
            } second: {
                resultsPane
            }
        }
        .task(id: session.runCount) { recompute() }
    }

    private func recompute() {
        var o = RegexTool.Options()
        o.pattern = session.option("pattern").stringValue
        o.flags = flags
        o.engine = session.option("engine").stringValue
        o.replacement = session.option("replacement").stringValue
        result = try? RegexTool.test(session.inputText, options: o)
    }

    // MARK: Pattern bar

    private var patternBar: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text("/").font(.system(.title2, design: .monospaced)).foregroundStyle(.tertiary)
                TextField("pattern", text: pattern)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, design: .monospaced))
                    .autocorrectionDisabled()
                    .accessibilityLabel("Regular expression pattern")
                Text("/").font(.system(.title2, design: .monospaced)).foregroundStyle(.tertiary)
                Text(flags).font(.system(.title3, design: .monospaced)).foregroundStyle(Color.accentColor)
                    .frame(minWidth: Space.lg)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(session.error != nil ? Palette.danger.opacity(0.7) : Palette.separator))

            HStack(spacing: Space.sm) {
                ForEach(Self.flagInfo, id: \.0) { f in
                    flagChip(f.0, help: f.1)
                }
                Spacer(minLength: Space.md)
                Picker("Engine", selection: engine) {
                    Text("ICU").tag("icu")
                    Text("JS").tag("js")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
                .help("Regex engine: ICU (PCRE-like) or JavaScript")
                if let r = result, session.error == nil {
                    StatusBadge("\(r.matches.count) \(r.matches.count == 1 ? "match" : "matches")", r.matches.isEmpty ? .neutral : .success)
                }
            }
            if let e = session.error {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(e.message + (e.hint.map { " — \($0)" } ?? ""))
                        .textSelection(.enabled)
                }
                .font(.callout)
                .foregroundStyle(Palette.danger)
            }
        }
        .padding(Space.md)
    }

    private func flagChip(_ flag: String, help: String) -> some View {
        let on = flags.contains(flag)
        return Button {
            toggleFlag(flag)
        } label: {
            Text(flag)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .frame(width: Space.xl, height: Space.xl)
                .background(on ? Color.accentColor : Palette.raised, in: RoundedRectangle(cornerRadius: Radius.small))
                .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggleFlag(_ f: String) {
        guard f.count == 1 else { return }
        var set = Set(flags)
        if set.contains(Character(f)) { set.remove(Character(f)) } else { set.insert(Character(f)) }
        session.setOption("flags", .string(Self.flagInfo.map(\.0).filter { set.contains(Character($0)) }.joined()))
    }

    // MARK: Test string

    private var testPane: some View {
        VStack(spacing: 0) {
            paneTitle("Test String")
            CodeEditor(text: $session.inputText, language: .plain, placeholder: "Type or paste text to test against",
                       annotations: session.error == nil ? (session.output?.annotations ?? []) : [],
                       config: EditorConfig.current, selection: $session.selection)
        }
    }

    private func paneTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs + 1)
            .background(Palette.paneTitle)
    }

    // MARK: Results

    private var resultsPane: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Space.sm)
            Divider()
            Group {
                switch tab {
                case .matches: matchesTab
                case .replace: replaceTab
                case .explain: explainTab
                case .cheat: cheatTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Palette.chrome)
    }

    private func placeholder(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: Space.sm) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.lg)
    }

    private var matchesTab: some View {
        Group {
            if let r = result, session.error == nil {
                if r.matches.isEmpty {
                    placeholder("magnifyingglass", session.inputText.isEmpty ? "Enter some text to test" : "No matches")
                } else {
                    let groupCount = r.matches.map(\.groups.count).max() ?? 0
                    ScrollView(.vertical) {
                        Grid(alignment: .topLeading, horizontalSpacing: Space.lg, verticalSpacing: Space.sm) {
                            GridRow {
                                headerCell("#"); headerCell("Match"); headerCell("Pos")
                                ForEach(0..<groupCount, id: \.self) { i in
                                    headerCell(groupTitle(r, i))
                                }
                            }
                            Divider().gridCellColumns(3 + groupCount)
                            ForEach(r.matches.prefix(500)) { m in
                                GridRow {
                                    Text("\(m.index + 1)").foregroundStyle(.secondary)
                                    cell(m.text, color: .yellow)
                                    Text("\(m.range.lowerBound)–\(m.range.upperBound)").foregroundStyle(.secondary)
                                    ForEach(0..<groupCount, id: \.self) { i in
                                        if i < m.groups.count, let t = m.groups[i].text { cell(t, color: .green) }
                                        else { Text("—").foregroundStyle(.tertiary) }
                                    }
                                }
                            }
                        }
                        .font(Typography.captionMono)
                        .padding(Space.md)
                    }
                }
            } else {
                placeholder("exclamationmark.triangle", session.error?.message ?? "Enter a pattern")
            }
        }
    }

    private func groupTitle(_ r: RegexTool.Result, _ i: Int) -> String {
        if i < r.groupNames.count, let n = r.groupNames[i] { return n }
        return "$\(i + 1)"
    }

    private func headerCell(_ s: String) -> some View {
        Text(s).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func cell(_ s: String, color: Color) -> some View {
        Text(s.isEmpty ? "(empty)" : s)
            .textSelection(.enabled)
            .padding(.horizontal, Space.xs)
            .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: Space.xs))
    }

    private var replaceTab: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Replace with").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("$1 or ${name}", text: replacement)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Text("Result").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                CopyButton("Copy") { result?.replaced }
            }
            .padding(.top, Space.sm)
            ScrollView {
                Group {
                    if session.error != nil {
                        Text("Fix the pattern to see the result").foregroundStyle(.secondary)
                    } else if let r = result?.replaced {
                        Text(r).textSelection(.enabled)
                    } else {
                        Text("Enter a replacement to preview the result").foregroundStyle(.secondary)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(Space.sm)
            }
            .background(Palette.editorBackground, in: RoundedRectangle(cornerRadius: Radius.small))
        }
        .padding(Space.md)
    }

    private var explainTab: some View {
        let lines = RegexExplainer.explain(session.option("pattern").stringValue)
        return Group {
            if lines.isEmpty {
                placeholder("text.magnifyingglass", "Enter a pattern to see a plain-English explanation")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            let indent = line.prefix { $0 == " " }.count
                            Text(line.trimmingCharacters(in: .whitespaces))
                                .font(Typography.captionMono)
                                .textSelection(.enabled)
                                .padding(.leading, CGFloat(indent / 2) * Space.lg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Space.md)
                }
            }
        }
    }

    private var cheatTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(Array(RegexExplainer.cheatSheet.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(section.0.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(section.1.enumerated()), id: \.offset) { _, entry in
                            Button { insert(entry.0, section: section.0) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                                    Text(entry.0).font(Typography.captionMono).foregroundStyle(Color.accentColor)
                                        .frame(width: 120, alignment: .leading)
                                    Text(entry.1).font(.callout).foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, Space.xxs)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Insert into the pattern")
                        }
                    }
                }
            }
            .padding(Space.md)
        }
    }

    /// Inserts the first token of a cheat-sheet entry (e.g. "\\d \\D" becomes "\\d") into the pattern or replacement.
    private func insert(_ raw: String, section: String) {
        if section == "Flags" { toggleFlag(raw); return }
        var token = raw.components(separatedBy: " ").first ?? raw
        if raw.contains("…") { token = raw.components(separatedBy: " / ").first ?? raw }
        token = token.replacingOccurrences(of: "…", with: "")
        if section == "Replacement" { replacement.wrappedValue += token; tab = .replace; return }
        pattern.wrappedValue += token
    }
}
