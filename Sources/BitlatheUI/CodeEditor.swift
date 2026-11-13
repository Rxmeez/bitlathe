import AppKit
import SwiftUI
import BitlatheCore

/// Everything the editor needs from settings, computed in a SwiftUI body so changes are observed.
public struct EditorConfig: Equatable {
    public var fontName: String
    public var fontSize: CGFloat
    public var theme: EditorTheme
    public var wrap: Bool
    public var invisibles: Bool
    public var lineNumbers: Bool
    public var tabWidth: Int
    public var highlightCurrentLine: Bool

    @MainActor
    public static var current: EditorConfig {
        let s = Settings.shared
        return EditorConfig(fontName: s.editorFontName, fontSize: s.effectiveMonoSize, theme: EditorTheme.named(s.editorTheme),
                            wrap: s.wrapLines, invisibles: s.showInvisibles, lineNumbers: s.showLineNumbers, tabWidth: s.tabWidth,
                            highlightCurrentLine: s.highlightCurrentLine)
    }

    public var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}

/// Bitlathe's code editor: NSTextView + line-number ruler + regex highlighting + error underlines + find bar.
public struct CodeEditor: NSViewRepresentable {
    @Binding public var text: String
    public var language: CodeLanguage
    public var isEditable: Bool
    public var placeholder: String
    public var error: ToolError?
    public var annotations: [Annotation]
    public var config: EditorConfig
    public var selection: Binding<NSRange>?
    public var onPaste: ((String) -> Void)?
    public var onDrop: (([URL]) -> Void)?
    /// scratchpad: optional handle for multi-selection access and grouped in-place edits.
    public var controller: EditorController?

    public init(text: Binding<String>, language: CodeLanguage = .plain, isEditable: Bool = true, placeholder: String = "",
                error: ToolError? = nil, annotations: [Annotation] = [], config: EditorConfig, selection: Binding<NSRange>? = nil,
                onPaste: ((String) -> Void)? = nil, onDrop: (([URL]) -> Void)? = nil, controller: EditorController? = nil) {
        _text = text
        self.language = language
        self.isEditable = isEditable
        self.placeholder = placeholder
        self.error = error
        self.annotations = annotations
        self.config = config
        self.selection = selection
        self.onPaste = onPaste
        self.onDrop = onDrop
        self.controller = controller
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.clipsToBounds = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let tv = EditorTextView(frame: .zero, textContainer: container)
        tv.coordinator = context.coordinator
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.importsGraphics = false
        tv.textContainerInset = CGSize(width: Space.sm, height: Space.sm)
        tv.minSize = .zero
        tv.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.autoresizingMask = [.width]
        tv.registerForDraggedTypes([.fileURL])

        scroll.documentView = tv
        let ruler = LineNumberRulerView(textView: tv)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = config.lineNumbers

        context.coordinator.textView = tv
        controller?.textView = tv
        context.coordinator.ruler = ruler
        context.coordinator.apply(self, initial: true)
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.clipFrameChanged(_:)),
                                               name: NSView.frameDidChangeNotification, object: scroll.contentView)
        // A wrapping editor must never be scrolled sideways: programmatic text changes and caret moves can
        // otherwise leave the clip view offset so the first columns hide under the line-number ruler.
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.clipFrameChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(self, initial: false)
        scroll.rulersVisible = config.lineNumbers
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var textView: EditorTextView?
        weak var ruler: LineNumberRulerView?
        private var lastConfig: EditorConfig?
        private var lastLanguage: CodeLanguage?
        private var isUpdating = false
        private var lastAnnouncedError: String?
        private var highlightWork: DispatchWorkItem?

        init(_ parent: CodeEditor) { self.parent = parent }

        var isDark: Bool {
            textView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        var colors: EditorTheme.Colors { isDark ? parent.config.theme.dark : parent.config.theme.light }

        func apply(_ p: CodeEditor, initial: Bool) {
            guard let tv = textView else { return }
            isUpdating = true
            defer { isUpdating = false }
            tv.isEditable = p.isEditable
            tv.placeholder = p.placeholder
            let lang = p.language == .plain ? "" : ", \(p.language.displayName)"
            tv.setAccessibilityLabel((p.isEditable ? "Input editor" : "Output editor") + lang)
            tv.setAccessibilityHelp(p.placeholder.isEmpty ? nil : p.placeholder)
            announceErrorIfNeeded(p.error, in: tv)
            tv.highlightCurrentLine = p.config.highlightCurrentLine && p.isEditable

            let configChanged = lastConfig != p.config
            if configChanged || initial {
                tv.font = p.config.font
                tv.backgroundColor = NSColor(hex: colors.background)
                tv.enclosingScrollView?.backgroundColor = tv.backgroundColor
                tv.insertionPointColor = NSColor(hex: colors.text)
                tv.textColor = NSColor(hex: colors.text)
                tv.currentLineColor = NSColor(hex: colors.currentLine)
                tv.layoutManager?.showsInvisibleCharacters = p.config.invisibles
                tv.defaultParagraphStyle = Self.paragraphStyle(font: p.config.font, tabWidth: p.config.tabWidth)
                tv.typingAttributes = [.font: p.config.font, .foregroundColor: NSColor(hex: colors.text), .paragraphStyle: tv.defaultParagraphStyle!]
                setWrap(p.config.wrap, tv)
                ruler?.update(font: p.config.font, colors: colors)
                lastConfig = p.config
            }

            if tv.string != p.text {
                let sel = tv.selectedRange()
                tv.textStorage?.setAttributedString(NSAttributedString(string: p.text, attributes: tv.typingAttributes))
                ruler?.invalidateLineIndex()
                if p.config.wrap, let clip = tv.enclosingScrollView?.contentView, clip.bounds.origin.x != -clip.contentInsets.left {
                    clip.scroll(to: NSPoint(x: -clip.contentInsets.left, y: clip.bounds.origin.y))
                }
                let newLen = (p.text as NSString).length
                tv.setSelectedRange(NSRange(location: min(sel.location, newLen), length: 0))
                highlightNow()
            } else if configChanged || lastLanguage != p.language || initial {
                highlightNow()
            }
            lastLanguage = p.language
            if let sel = p.selection?.wrappedValue, sel != tv.selectedRange(), NSMaxRange(sel) <= (tv.string as NSString).length {
                tv.setSelectedRange(sel)
            }
            applyAnnotations(p)
            ruler?.needsDisplay = true
        }

        static func paragraphStyle(font: NSFont, tabWidth: Int) -> NSParagraphStyle {
            let ps = NSMutableParagraphStyle()
            let charWidth = (" " as NSString).size(withAttributes: [.font: font]).width
            ps.defaultTabInterval = charWidth * CGFloat(tabWidth)
            ps.tabStops = []
            ps.lineBreakMode = .byWordWrapping
            return ps
        }

        /// Keep a wrapping text view exactly as wide as the visible text area and scrolled fully left.
        /// On macOS 14+ the scroll view makes room for the line-number ruler with a content inset, so "fully left"
        /// is x = -contentInsets.left (not 0); forcing 0 slides the first columns underneath the ruler.
        @objc func clipFrameChanged(_ note: Notification) {
            guard parent.config.wrap, let tv = textView, let clip = tv.enclosingScrollView?.contentView else { return }
            let insets = clip.contentInsets
            let width = clip.bounds.width - insets.left - insets.right
            if width > 0, abs(tv.frame.width - width) > 0.5 { tv.setFrameSize(NSSize(width: width, height: tv.frame.height)) }
            let minX = -insets.left
            if abs(clip.bounds.origin.x - minX) > 0.5 {
                clip.scroll(to: NSPoint(x: minX, y: clip.bounds.origin.y))
                tv.enclosingScrollView?.reflectScrolledClipView(clip)
            }
        }

        private func setWrap(_ wrap: Bool, _ tv: NSTextView) {
            guard let container = tv.textContainer, let scroll = tv.enclosingScrollView else { return }
            scroll.hasHorizontalScroller = !wrap
            defer { scroll.tile() }
            if wrap {
                tv.isHorizontallyResizable = false
                tv.autoresizingMask = [.width]
                container.widthTracksTextView = true
                let clip = scroll.contentView
                tv.setFrameSize(NSSize(width: max(clip.bounds.width - clip.contentInsets.left - clip.contentInsets.right, 1), height: tv.frame.height))
                clip.scroll(to: NSPoint(x: -clip.contentInsets.left, y: clip.bounds.origin.y))
            } else {
                container.widthTracksTextView = false
                container.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                tv.isHorizontallyResizable = true
            }
        }

        func highlightNow() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            storage.beginEditing()
            Highlighter.highlight(storage, language: parent.language, colors: colors)
            storage.endEditing()
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.highlightNow()
                self.applyAnnotations(self.parent)
            }
            highlightWork = work
            let length = textView?.textStorage?.length ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + (length > 100_000 ? 0.25 : 0.05), execute: work)
        }

        /// Exposes the current error as the editor's accessibility value suffix and announces it once when it appears.
        private func announceErrorIfNeeded(_ error: ToolError?, in tv: NSTextView) {
            let message = error.map { "Error: \($0.message)" + ($0.location.map { " at \($0)" } ?? "") }
            guard message != lastAnnouncedError else { return }
            lastAnnouncedError = message
            tv.setAccessibilityRoleDescription(message == nil ? nil : "text area with error")
            if let message {
                NSAccessibility.post(element: tv, notification: .announcementRequested,
                                     userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            }
        }

        func applyAnnotations(_ p: CodeEditor) {
            guard let tv = textView, let lm = tv.layoutManager else { return }
            let len = (tv.string as NSString).length
            lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: NSRange(location: 0, length: len))
            lm.removeTemporaryAttribute(.underlineColor, forCharacterRange: NSRange(location: 0, length: len))
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: len))
            lm.removeTemporaryAttribute(.toolTip, forCharacterRange: NSRange(location: 0, length: len))
            for a in p.annotations where NSMaxRange(NSRange(a.range)) <= len {
                let r = NSRange(a.range)
                let color: NSColor = switch a.style {
                case .match: NSColor.systemYellow.withAlphaComponent(0.35)
                case .group: NSColor.systemBlue.withAlphaComponent(0.25)
                case .error: NSColor.systemRed.withAlphaComponent(0.25)
                case .warning: NSColor.systemOrange.withAlphaComponent(0.25)
                case .added: NSColor.systemGreen.withAlphaComponent(0.25)
                case .removed: NSColor.systemRed.withAlphaComponent(0.2)
                case .info: NSColor.systemTeal.withAlphaComponent(0.2)
                }
                lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: r)
                if let tip = a.tooltip { lm.addTemporaryAttribute(.toolTip, value: tip, forCharacterRange: r) }
            }
            if let e = p.error {
                var range: NSRange?
                if let r = e.range, NSMaxRange(NSRange(r)) <= len { range = NSRange(r) }
                else if let line = e.line {
                    let start = tv.string.utf16Offset(line: line, column: 1)
                    let end = tv.string.utf16Offset(line: line + 1, column: 1)
                    if let col = e.column, col > 0 {
                        let loc = min(start + col - 1, max(len - 1, 0))
                        range = NSRange(location: loc, length: min(max(1, end - loc - 1), len - loc))
                    } else {
                        range = NSRange(location: start, length: max(0, min(end - start - 1, len - start)))
                    }
                }
                if let range, range.length > 0, range.location < len {
                    lm.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue, forCharacterRange: range)
                    lm.addTemporaryAttribute(.underlineColor, value: NSColor.systemRed, forCharacterRange: range)
                    lm.addTemporaryAttribute(.toolTip, value: e.message, forCharacterRange: range)
                }
            }
        }

        // MARK: Delegate

        public func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = textView else { return }
            ruler?.invalidateLineIndex()
            parent.text = tv.string
            scheduleHighlight()
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.selection?.wrappedValue = tv.selectedRange()
            parent.controller?.onSelectionChange?(tv.selectedRanges.map(\.rangeValue).sorted { $0.location < $1.location })
            if tv.highlightCurrentLine { tv.needsDisplay = true }
        }

        func appearanceChanged() {
            guard let tv = textView else { return }
            tv.backgroundColor = NSColor(hex: colors.background)
            tv.enclosingScrollView?.backgroundColor = tv.backgroundColor
            tv.insertionPointColor = NSColor(hex: colors.text)
            tv.currentLineColor = NSColor(hex: colors.currentLine)
            ruler?.update(font: parent.config.font, colors: colors)
            highlightNow()
        }
    }
}

// MARK: - NSTextView subclass

public final class EditorTextView: NSTextView {
    weak var coordinator: CodeEditor.Coordinator?
    var placeholder = "" { didSet { needsDisplay = true } }
    var highlightCurrentLine = true
    var currentLineColor = NSColor.clear

    override public var acceptsFirstResponder: Bool { true }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        coordinator?.appearanceChanged()
    }

    override public func draw(_ dirtyRect: NSRect) {
        if highlightCurrentLine, isEditable, window?.firstResponder == self, let lm = layoutManager, let tc = textContainer {
            let sel = selectedRange()
            let charIndex = min(sel.location, max((string as NSString).length - 1, 0))
            var lineRect: NSRect
            if (string as NSString).length == 0 {
                lineRect = NSRect(x: 0, y: textContainerInset.height, width: bounds.width, height: font?.boundingRectForFont.height ?? 16)
            } else {
                let glyph = lm.glyphIndexForCharacter(at: charIndex)
                lineRect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                if sel.location >= (string as NSString).length, string.hasSuffix("\n") {
                    lineRect.origin.y += lineRect.height
                }
                lineRect.origin.y += textContainerInset.height
                lineRect.origin.x = 0
                lineRect.size.width = bounds.width
            }
            _ = tc
            currentLineColor.setFill()
            lineRect.fill()
        }
        super.draw(dirtyRect)
        if string.isEmpty, !placeholder.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor]
            let origin = NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height)
            (placeholder as NSString).draw(at: origin, withAttributes: attrs)
        }
    }

    override public func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override public func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override public func paste(_ sender: Any?) {
        if let s = NSPasteboard.general.string(forType: .string), let onPaste = coordinator?.parent.onPaste {
            onPaste(s)
        }
        pasteAsPlainText(sender)
    }

    override public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty, let onDrop = coordinator?.parent.onDrop {
            onDrop(urls)
            return true
        }
        return super.performDragOperation(sender)
    }

    // Keep tab key inserting spaces according to the tab width.
    override public func insertTab(_ sender: Any?) {
        let width = coordinator?.parent.config.tabWidth ?? 4
        insertText(String(repeating: " ", count: width), replacementRange: selectedRange())
    }
}

// MARK: - Ruler

public final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private var textColor = NSColor.secondaryLabelColor
    private var background = NSColor.windowBackgroundColor
    /// UTF-16 offsets of each line start.
    private var lineStarts: [Int] = [0]
    private var lineIndexValid = false

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        clipsToBounds = true
        ruleThickness = 40
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: textView.enclosingScrollView?.contentView)
        textView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func boundsChanged() { needsDisplay = true }

    func update(font: NSFont, colors: EditorTheme.Colors) {
        self.font = NSFont.monospacedDigitSystemFont(ofSize: max(9, font.pointSize - 2), weight: .regular)
        textColor = NSColor(hex: colors.gutterText)
        background = NSColor(hex: colors.gutter)
        needsDisplay = true
    }

    func invalidateLineIndex() { lineIndexValid = false; needsDisplay = true }

    private func rebuildLineIndex() {
        guard let tv = textView else { return }
        var starts = [0]
        let s = tv.string.utf16
        var i = 0
        for u in s {
            i += 1
            if u == 10 { starts.append(i) }
        }
        lineStarts = starts
        lineIndexValid = true
        let digits = max(2, String(starts.count).count)
        let width = CGFloat(digits) * ("0" as NSString).size(withAttributes: [.font: font]).width + Space.lg
        if abs(width - ruleThickness) > 1 {
            ruleThickness = width
            // AppKit doesn't re-lay out the clip view when the ruler's thickness changes; without this the text
            // keeps its old origin and its first columns end up underneath the ruler.
            scrollView?.tile()
        }
    }

    private func lineNumber(for charIndex: Int) -> Int {
        var lo = 0
        var hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= charIndex { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Draw our own background and a hairline separator; NSRulerView's default border is too heavy.
    override public func draw(_ dirtyRect: NSRect) {
        background.setFill()
        bounds.fill()
        drawHashMarksAndLabels(in: dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.4).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }

    override public func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        if !lineIndexValid { rebuildLineIndex() }
        background.setFill()
        bounds.fill()
        let visible = tv.visibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let inset = tv.textContainerInset.height
        let yOffset = convert(NSPoint.zero, from: tv).y
        let total = lineStarts.count
        var line = lineNumber(for: charRange.location)
        let length = (tv.string as NSString).length

        func draw(_ n: Int, at rectY: CGFloat, height: CGFloat) {
            let label = String(n) as NSString
            let size = label.size(withAttributes: attrs)
            let y = rectY + inset + yOffset + (height - size.height) / 2
            label.draw(at: NSPoint(x: ruleThickness - size.width - Space.sm, y: y), withAttributes: attrs)
        }

        while line < total {
            let start = lineStarts[line]
            if start > NSMaxRange(charRange) { break }
            if start >= length {
                // Empty trailing line.
                let extra = lm.extraLineFragmentRect
                if extra.height > 0 { draw(line + 1, at: extra.minY, height: extra.height) }
                else if length == 0 { draw(1, at: 0, height: font.boundingRectForFont.height + 4) }
                break
            }
            let glyph = lm.glyphIndexForCharacter(at: start)
            let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            draw(line + 1, at: frag.minY, height: frag.height)
            line += 1
        }
    }
}
