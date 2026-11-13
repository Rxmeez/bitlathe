import XCTest
import AppKit
@testable import BitlatheUI
import BitlatheCore

@MainActor
final class PerformanceEditorTests: XCTestCase {
    private func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    /// Mirrors what CodeEditor.apply does for a 10 MB output: compare, set text, highlight, lay out the visible page.
    func testTenMegabyteOutputMainThreadDisplayTime() {
        let line = "    \"key\": \"value with some text\", \"n\": 1234.5,\n"
        let text = String(repeating: line, count: 10_485_760 / line.utf8.count)
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        tv.isVerticallyResizable = true
        let colors = EditorTheme.named("default").light
        let clock = ContinuousClock()

        let compare = clock.measure { _ = (tv.string != text) }
        let set = clock.measure { storage.setAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])) }
        let highlight = clock.measure {
            storage.beginEditing()
            Highlighter.highlight(storage, language: .json, colors: colors)
            storage.endEditing()
        }
        let layoutTime = clock.measure {
            _ = layout.glyphRange(forBoundingRect: NSRect(x: 0, y: 0, width: 800, height: 600), in: container)
        }
        let total = ms(compare) + ms(set) + ms(highlight) + ms(layoutTime)
        print("PERF editor 10 MB display: compare \(Int(ms(compare))) ms, set text \(Int(ms(set))) ms, highlight \(Int(ms(highlight))) ms, visible layout \(Int(ms(layoutTime))) ms, total \(Int(total)) ms")
        XCTAssertLessThan(ms(highlight), 100, "highlight must be skipped above the size limit")
    }

    func testHighlightingCostScaling() {
        let line = "    \"key\": \"value\", \"n\": 1234.5, \"ok\": true,\n"
        let colors = EditorTheme.named("default").light
        for kb in [32, 64, 128, 256, Highlighter.sizeLimit / 1024] {
            let text = String(repeating: line, count: kb * 1024 / line.utf8.count - 1)
            let storage = NSTextStorage(string: text)
            // Same bracketing CodeEditor.highlightNow uses.
            let t = ContinuousClock().measure {
                storage.beginEditing()
                Highlighter.highlight(storage, language: .json, colors: colors)
                storage.endEditing()
            }
            print("PERF highlight JSON \(kb) KB: \(Int(ms(t))) ms")
            let plain = NSMutableAttributedString(string: text)
            let t2 = ContinuousClock().measure { Highlighter.highlight(plain, language: .json, colors: colors) }
            print("PERF highlight JSON \(kb) KB standalone string: \(Int(ms(t2))) ms")
        }
    }
}
