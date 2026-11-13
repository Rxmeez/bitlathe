# Performance

## Methodology

- Machine: Apple M3 Pro, 18 GB, macOS 27.0 (other agents were building in parallel, so timings are noisy; treat them as order of magnitude).
- Swift 6.1.2, release configuration: `swift test -c release --filter Performance`. Each test prints `PERF ...` lines; run with `grep PERF`.
- Tests live in `Tests/BitlatheTests/Performance*.swift`. Fixtures are generated in the test (the 10 MB JSON is never committed).
- "Before" numbers were taken by running the same tests against the unmodified sources (`git checkout Sources`).
- Hard time bounds are asserted only where they are deterministic enough (diff 10k lines < 1 s, 10 MB JSON format < 1.5 s in release only, cancel latency < 500 ms, mean detection < 20 ms).
- Peak memory is process-wide `ru_maxrss` and includes the 10 MB source string and test harness; it is indicative only.

## Results

| Area | Before | After |
| --- | --- | --- |
| Diff 10k x 10k lines, 100 scattered edits (near both ends) | 9,901 deletes / 100 inserts-equal wall of red (fallback), wrong | exact: 100 delete, 100 insert, 9,900 equal; ~4 ms |
| Diff 10k x 10k fully different | 7 ms (fallback) | ~170 ms (real search, capped at 6,000 edit steps per region) |
| JSON parse 10 MB | 252 ms | 58 ms |
| JSON pretty-print 10 MB | 369 ms | 36-41 ms |
| JSON minify 10 MB | 192 ms | 25 ms |
| Peak RSS during parse + serialize | 171 MB | 131-200 MB (varies with test order; dominated by the value tree) |
| Cancel of a 10 MB JSON Formatter run | not checked in the engine | 9-13 ms to observe cancel |
| Highlight 512 KB JSON (main thread) | ~2,000-3,000 ms (quadratic) | ~75 ms |
| Highlight 128 KB JSON | ~150-600 ms | ~20 ms |
| Show 10 MB output in an NSTextView (compare + set text + highlight + first layout) | not measured | ~45 ms |
| DetectionEngine, 88 tools, mean per typical input (159 samples) | not measured | ~0.5 ms |
| DetectionEngine, 1 MB JSON input (64 KB sample) | ~200 ms | ~90 ms |

## What changed

- `DiffEngine.diff`: tokens are interned to Ints and diffed with linear-space Myers (middle snake, divide and conquer) instead of the O(ND)-memory trace with a 4M-cell fallback. Regions needing more than 6,000 edit steps are reported as replaced.
- `JSONParser`: fast path for strings without escapes, periodic `Task.isCancelled` check (throws `CancellationError`).
- `JSONSerializer`: byte-level writer into one `[UInt8]`, bulk copy of clean string runs, cached indent pads, `stringCancellable` used by the JSON Formatter so cancel stops a large format.
- `Highlighter`: token map plus ascending-order attribute runs (applying one attribute per regex match was quadratic); above the 512 KB limit only a single base-colour run is applied.
- `LineNumberRulerView`: line index built with chunked `getCharacters` instead of iterating a bridged `utf16` view.
- `ToolSession`: a generation counter stops a stale 150 ms timer from re-showing the "running" indicator after Cancel (previously a non-cooperative engine could flip it back on). Tests confirm the indicator appears only after ~150 ms, never for fast runs, and that the engine observes cancellation.
- `HTTPReferenceTool.detect`: bails out on inputs over 64 bytes (it lowercased the whole sample once per header, ~107 ms on a 64 KB sample).

## Not done / manual

- The 1,000-tool-switch Instruments leak check is still to be done by hand (Instruments, Leaks + Allocations, switch tools 1,000 times, expect flat persistent memory).
- Main-thread display time was measured on a headless NSTextView with the same steps `CodeEditor.apply` performs, not inside the full SwiftUI app. Scrolling and window-resize cost of a 10 MB document is not measured.
- Diff of very large inputs that are almost entirely different is not minimal (see the 6,000-step cap).
- `ts.format` detect takes ~55 ms on a 64 KB sample (still within budget); left alone.
