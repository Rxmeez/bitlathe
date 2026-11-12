#!/bin/zsh
# Launch a tool with a sample and capture the window. Usage: scripts/shot.sh <tool.id> <sampleIndex> <out.png> [light|dark] [inspector]
set -euo pipefail
cd "$(dirname "$0")/.."
# Several agents may share this Mac: take a global lock so only one launches/captures at a time.
LOCK=/tmp/bitlathe-shot.lock
for _ in {1..600}; do mkdir "$LOCK" 2>/dev/null && break; sleep 0.5; done
trap 'pkill -x Bitlathe 2>/dev/null || true; rmdir "$LOCK" 2>/dev/null || true' EXIT
APP=".build/DerivedData/Build/Products/Debug/Bitlathe.app"
pkill -x Bitlathe 2>/dev/null || true; while pgrep -x Bitlathe >/dev/null; do sleep 0.2; done; sleep 0.3
EXTRA=()
[[ "${5:-}" == "inspector" ]] && EXTRA=(-BLInspector YES)
[[ "${5:-}" == "settings" ]] && EXTRA=(-BLSettings YES)
[[ "${5:-}" == search:* ]] && EXTRA=(-BLSearch "${5#search:}")
[[ "${5:-}" == palette* ]] && EXTRA=(-BLPalette YES)
[[ "${5:-}" == palette:* ]] && EXTRA+=(-BLPaletteQuery "${5#palette:}")
WIN="${WINDOW_TITLE:-}"
APPEARANCE=()
[[ -n "${4:-}" ]] && APPEARANCE=(-bl.appearance "$4")
open -n "$APP" --args -BLTool "$1" -BLSample "$2" "${EXTRA[@]}" "${APPEARANCE[@]}"
sleep 2.5
ID=$(swift - "$WIN" <<< 'import CoreGraphics; let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []; let want = CommandLine.arguments.dropFirst().first ?? ""; for w in l where (w[kCGWindowOwnerName as String] as? String) == "Bitlathe" && (w[kCGWindowLayer as String] as? Int) == 0 && (want.isEmpty || (w[kCGWindowName as String] as? String ?? "").contains(want)) { print(w[kCGWindowNumber as String]!); break }' 2>/dev/null)
screencapture -x -o -l "$ID" "$3"
echo "$3"
