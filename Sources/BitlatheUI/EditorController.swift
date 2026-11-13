import AppKit

/// Handle onto a `CodeEditor`'s text view for callers that need more than a text binding: multiple selections,
/// in-place edits that undo as one step, and focus. Attach one via `CodeEditor(…, controller:)`.
@MainActor
public final class EditorController {
    weak var textView: EditorTextView?
    /// Called whenever the selection changes, with every selected range (a lone caret is a zero-length range).
    public var onSelectionChange: (([NSRange]) -> Void)?

    public init() {}

    public var string: String { textView?.string ?? "" }

    /// All selected ranges in ascending order. Always contains at least one range (the caret).
    public var selectedRanges: [NSRange] {
        guard let tv = textView else { return [] }
        return tv.selectedRanges.map(\.rangeValue).sorted { $0.location < $1.location }
    }

    public func setSelectedRanges(_ ranges: [NSRange]) {
        guard let tv = textView else { return }
        let length = (tv.string as NSString).length
        let valid = ranges.filter { NSMaxRange($0) <= length }
        guard !valid.isEmpty else { return }
        tv.setSelectedRanges(valid.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
    }

    public func undo() { textView?.undoManager?.undo() }

    public func focus() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    /// Replaces each (ascending, non-overlapping) range with the matching string as ONE undo step, then selects
    /// every replacement. Returns false when the editor refused the change.
    @discardableResult
    public func replace(ranges: [NSRange], with strings: [String]) -> Bool {
        guard let tv = textView, let storage = tv.textStorage, ranges.count == strings.count, !ranges.isEmpty else { return false }
        guard tv.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: strings) else { return false }
        let undo = tv.undoManager
        undo?.beginUndoGrouping()
        storage.beginEditing()
        for (range, string) in zip(ranges, strings).reversed() {
            storage.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: tv.typingAttributes))
        }
        storage.endEditing()
        tv.didChangeText()
        undo?.endUndoGrouping()
        var delta = 0
        var selected: [NSRange] = []
        for (range, string) in zip(ranges, strings) {
            let length = (string as NSString).length
            selected.append(NSRange(location: range.location + delta, length: length))
            delta += length - range.length
        }
        setSelectedRanges(selected)
        return true
    }
}
