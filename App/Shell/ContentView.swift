import SwiftUI
import BitlatheCore
import BitlatheUI
import BitlatheTools

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openSettings) private var openSettings
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: Layout.sidebarMin, ideal: Layout.sidebarIdeal, max: Layout.sidebarMax)
        } detail: {
            detail
        }
        .navigationTitle(model.selectedTool?.name ?? "Bitlathe")
        .modifier(HideToolbarTitle())
        .toolbar {
            ToolbarItem(placement: .automatic) { Spacer() }
            ToolbarItem(placement: .automatic) {
                Button { model.smartPaste() } label: { Label("Smart Paste", systemImage: "wand.and.stars") }
                    .help("Paste into the best matching tool (⌘⌥V)")
            }
            ToolbarItem(placement: .automatic) {
                Button { model.showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                    .help("Show options, history and docs (⌥⌘I)")
            }
        }
        .overlay { CommandPaletteOverlay() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.detectClipboardIfNeeded()
        }
        .onAppear {
            model.detectClipboardIfNeeded()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "BLSettings") { openSettings() }
            #endif
        }
    }

    @ViewBuilder
    private var detail: some View {
        @Bindable var model = model
        if let session = model.currentSession {
            VStack(spacing: 0) {
                if let report = model.detectionReport { DetectionBanner(report: report) }
                ToolScreen(session: session)
                    .id(session.id)
            }
            .inspector(isPresented: $model.showInspector) {
                InspectorView(session: session, initialTab: model.debugInspectorTab)
                    .inspectorColumnWidth(min: Layout.inspectorMin, ideal: Layout.inspectorIdeal, max: Layout.inspectorMax)
            }
        } else {
            ContentUnavailableView("Choose a tool", systemImage: "wrench.and.screwdriver", description: Text("Pick a tool from the sidebar, or paste something and Bitlathe will guess."))
        }
    }
}

/// The tool header already shows the name; keep the window title for Mission Control/Window menu but hide it in the toolbar.
struct HideToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

struct DetectionBanner: View {
    @Environment(AppModel.self) private var model
    let report: DetectionReport

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "wand.and.stars").foregroundStyle(Palette.accent).accessibilityHidden(true)
            if let best = report.best {
                Text("Clipboard looks like **\(best.score.reason)**").font(.callout)
                Chip("Open in \(best.tool.name)", symbol: best.tool.symbol) { model.applyDetection(best) }
                if !report.alsoTry.isEmpty {
                    Text("Also try").font(.caption).foregroundStyle(.secondary)
                    ForEach(report.alsoTry) { r in Chip(r.tool.name, tint: .secondary) { model.applyDetection(r) } }
                }
            }
            Spacer()
            Button { model.dismissDetection() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Dismiss (Esc) · detected in \(DurationFormatter.ms(report.duration))")
                .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .background(Palette.accent.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct InspectorView: View {
    @Bindable var session: ToolSession
    @State private var tab: Int

    init(session: ToolSession, initialTab: Int = 0) {
        self.session = session
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Options").tag(0)
                Text("History").tag(1)
                Text("About").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Space.md)
            Divider()
            switch tab {
            case 1:
                InspectorHistoryView(session: session)
            case 2:
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.md) {
                        Label(session.tool.name, systemImage: session.tool.symbol).font(Typography.headline)
                        Text(session.tool.summary).font(.callout)
                        Text("ID: \(session.tool.id)").font(Typography.captionMono).foregroundStyle(.secondary)
                        Text("Category: \(session.tool.category.title)").font(.caption).foregroundStyle(.secondary)
                        if !session.tool.keywords.isEmpty { Text("Keywords: " + session.tool.keywords.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                        Text("CLI: bl \(session.tool.id)").font(Typography.captionMono).foregroundStyle(.secondary)
                        Text("URL: bitlathe://tool/\(session.tool.id)?input=…").font(Typography.captionMono).foregroundStyle(.secondary)
                    }
                    .padding(Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            default:
                if session.tool.optionFields.isEmpty {
                    Text("This tool has no options").foregroundStyle(.secondary).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    InspectorOptions(session: session)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.chrome)
    }
}
