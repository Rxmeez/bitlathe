import SwiftUI
import BitlatheCore
import BitlatheUI

private let symbolChoices = ["point.3.connected.trianglepath.dotted", "archivebox", "key.horizontal", "lock", "curlybraces", "doc.text", "number",
                             "link", "photo", "wand.and.stars", "bolt", "terminal", "tray.full", "arrow.triangle.branch"]

struct PipelineEditorView: View {
    @Bindable var editor: PipelineEditor
    @Environment(AppModel.self) private var model
    @State private var showPicker = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    inputCard
                    ForEach(Array(editor.draft.steps.enumerated()), id: \.element.id) { i, step in
                        connector
                        StepCardView(editor: editor, step: step, index: i)
                    }
                    connector
                    addStepButton
                    connector
                    outputCard
                }
                .frame(maxWidth: PipelineMetrics.contentMaxWidth)
                .padding(Space.lg)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.chrome)
        }
        .background(Palette.editorBackground)
        .confirmationDialog("Delete “\(editor.saved.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Pipeline", role: .destructive) { model.pipelines.delete(editor) }
        } message: { Text("This removes the saved pipeline and its entry in the palette and CLI. It cannot be undone.") }
        .onAppear { if editor.debugShowPicker { showPicker = true } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.md) {
            Menu {
                ForEach(symbolChoices, id: \.self) { s in
                    Button { editor.draft.symbol = s } label: { Label(s == editor.draft.symbol ? "Selected" : " ", systemImage: s) }
                }
            } label: {
                Image(systemName: editor.draft.symbol).symbolRenderingMode(.hierarchical).font(.title2).foregroundStyle(Palette.accent)
                    .frame(width: Space.xxl, height: Space.xxl)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Choose an icon")
            VStack(alignment: .leading, spacing: 0) {
                TextField("Pipeline name", text: $editor.draft.name).textFieldStyle(.plain).font(Typography.title)
                TextField("What does this pipeline do?", text: $editor.draft.summary).textFieldStyle(.plain).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.md)
            if editor.running { ProgressView().controlSize(.small) }
            Button { Task { await model.pipelines.save(editor) } } label: { Label("Save", systemImage: "checkmark.circle") }
                .buttonStyle(.borderedProminent)
                .disabled(!editor.isDirty)
                .help(editor.isDirty ? "Save and register this pipeline as a tool" : "No unsaved changes")
            Menu {
                Button("Duplicate") { model.pipelines.duplicate(editor) }
                Divider()
                Button("Export…") { model.pipelines.exportPipeline(editor) }
                Button("Import…") { model.pipelines.importPipeline() }
                Divider()
                Button("Copy CLI Command") { copyCLI() }.disabled(editor.draft.steps.isEmpty)
                Divider()
                Button("Delete…", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Pipeline actions")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .frame(minHeight: Layout.headerHeight)
    }

    private func copyCLI() {
        let cmd = editor.cliCommand()
        Clipboard.copy(cmd.text)
        if !cmd.exact { ToastCenter.shared.show("Options contain spaces; copied the saved-pipeline command", symbol: "info.circle.fill") }
    }

    // MARK: Pieces

    private var connector: some View {
        Image(systemName: "arrow.down").font(.caption).foregroundStyle(.tertiary).frame(height: Space.xl)
    }

    private var inputCard: some View {
        card {
            HStack {
                Label("Input", systemImage: "square.and.arrow.down").font(.headline)
                Spacer()
                Button("Paste") { if let s = Clipboard.string { editor.input = s } }.buttonStyle(.borderless)
                Button("Clear") { editor.input = "" }.buttonStyle(.borderless).disabled(editor.input.isEmpty)
            }
            CodeEditor(text: $editor.input, language: .plain, isEditable: true, placeholder: "Paste or type input…", config: EditorConfig.current,
                       onDrop: { urls in if let u = urls.first, let s = try? String(contentsOf: u, encoding: .utf8) { editor.input = s } })
                .frame(height: PipelineMetrics.editorHeight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Palette.separator, lineWidth: PipelineMetrics.borderWidth))
        }
    }

    private var addStepButton: some View {
        Button { showPicker = true } label: { Label("Add Step", systemImage: "plus.circle.fill").font(.headline) }
            .buttonStyle(.bordered).controlSize(.large)
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                StepToolPicker { tool in
                    editor.addStep(tool)
                    showPicker = false
                }
            }
    }

    @ViewBuilder
    private var outputCard: some View {
        let run = editor.run
        card {
            HStack {
                Label("Output", systemImage: "square.and.arrow.up").font(.headline)
                Spacer()
                if let run, run.error == nil {
                    Text("\(run.steps.filter { !$0.skipped }.count) steps · \(DurationFormatter.ms(run.duration))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                CopyButton("Copy") { run?.finalOutput?.payload.text }.buttonStyle(.borderless).disabled(run?.finalOutput?.payload.text == nil)
            }
            outputBody(run)
        }
    }

    @ViewBuilder
    private func outputBody(_ run: PipelineRun?) -> some View {
        if editor.draft.steps.isEmpty {
            hint("Add a step to start building.")
        } else if editor.input.isEmpty {
            hint("Paste some input above to run the pipeline.")
        } else if let run {
            if let failed = run.steps.enumerated().first(where: { $0.element.error != nil }), let e = failed.element.error {
                ErrorBanner(e).clipShape(RoundedRectangle(cornerRadius: Radius.small))
                Text("Step \(failed.offset + 1) failed, so there is no final output.").font(.caption).foregroundStyle(.secondary)
            } else if let out = run.finalOutput {
                if case .image(let data, _) = out.payload {
                    PayloadImageView(data).frame(height: PipelineMetrics.outputMax).clipShape(RoundedRectangle(cornerRadius: Radius.small))
                } else {
                    let text = PipelinePreview.text(out, limit: 200_000)
                    CodeEditor(text: .constant(text), language: out.language, isEditable: false, config: EditorConfig.current)
                        .frame(height: min(PipelineMetrics.outputMax, max(PipelineMetrics.editorHeight / 2, PipelinePreview.height(for: text) * 1.6)))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                        .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Palette.separator, lineWidth: PipelineMetrics.borderWidth))
                }
            } else {
                hint("All steps are disabled.")
            }
        } else {
            hint("Running…")
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm, content: content)
            .padding(Space.md)
            .background(Palette.editorBackground, in: RoundedRectangle(cornerRadius: Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(Palette.separator, lineWidth: PipelineMetrics.borderWidth))
    }
}
