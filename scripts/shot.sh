#!/bin/zsh
# Launch a tool with a sample and capture the window. Usage: scripts/shot.sh <tool.id> <sampleIndex> <out.png> [light|dark] [inspector]
set -euo pipefail
cd "$(dirname "$0")/.."
APP=".build/DerivedData/Build/Products/Debug/Bitlathe.app"
pkill -x Bitlathe 2>/dev/null || true; sleep 0.5
EXTRA=()
[[ "${5:-}" == "inspector" ]] && EXTRA=(-BLInspector YES)
[[ "${5:-}" == "settings" ]] && EXTRA=(-BLSettings YES)
[[ "${5:-}" == search:* ]] && EXTRA=(-BLSearch "${5#search:}")
WIN="${WINDOW_TITLE:-}"
APPEARANCE=()
[[ -n "${4:-}" ]] && APPEARANCE=(-bl.appearance "$4")
open -n "$APP" --args -BLTool "$1" -BLSample "$2" "${EXTRA[@]}" "${APPEARANCE[@]}"
sleep 2.5
ID=$(swift - "$WIN" <<< 'import CoreGraphics; let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []; let want = CommandLine.arguments.dropFirst().first ?? ""; for w in l where (w[kCGWindowOwnerName as String] as? String) == "Bitlathe" && (w[kCGWindowLayer as String] as? Int) == 0 && (want.isEmpty || (w[kCGWindowName as String] as? String ?? "").contains(want)) { print(w[kCGWindowNumber as String]!); break }' 2>/dev/null)
screencapture -x -o -l "$ID" "$3"
echo "$3"
