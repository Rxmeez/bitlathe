#!/bin/zsh
# Rebuild the dev app ("Bitlathe Dev") and relaunch it. Usage: scripts/run.sh [debug|release]
# The dev app has its own bundle id, data, URL scheme and icon, so it never touches the installed /Applications/Bitlathe.app.
# To update the installed copy, use scripts/install.sh (or `make install`).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
CONFIG="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
# Many agents may build on this Mac at once: hold one of 3 build slots so memory isn't exhausted.
SLOT=""
for _ in {1..2400}; do
  for n in 1 2 3; do mkdir "/tmp/bitlathe-build-slot-$n" 2>/dev/null && SLOT="/tmp/bitlathe-build-slot-$n" && break 2; done
  sleep 0.5
done
trap '[[ -n "$SLOT" ]] && rmdir "$SLOT" 2>/dev/null || true' EXIT
# Always regenerate: XcodeGen globs App/, so new files (e.g. from merges) must be picked up. It takes ~1 s.
xcodegen generate --quiet
DERIVED=".build/DerivedData"
LOG="$DERIVED/last-build.log"
mkdir -p "$DERIVED"
if ! xcodebuild -project Bitlathe.xcodeproj -scheme Bitlathe -configuration "$CONFIG" -derivedDataPath "$DERIVED" -destination 'platform=macOS' build > "$LOG" 2>&1; then
  if ! grep -E "error:" "$LOG" | sort -u; then tail -25 "$LOG"; fi
  echo "Build failed (full log: $LOG)"
  exit 1
fi
grep -E "warning:" "$LOG" | grep -v appintentsmetadataprocessor | sort -u || true
echo "** BUILD SUCCEEDED **"
NAME="Bitlathe Dev"; [[ "$CONFIG" == "Release" ]] && NAME="Bitlathe"
APP="$DERIVED/Build/Products/$CONFIG/$NAME.app"
if [[ "${BUILD_ONLY:-0}" == "1" ]]; then echo "Built $APP"; exit 0; fi
if [[ ! -d "$APP" ]]; then echo "Build failed"; exit 1; fi
# Quit only this copy, matched by bundle path, never the installed app.
pkill -f "$PWD/$APP/Contents/MacOS/" 2>/dev/null || true
for _ in {1..40}; do pgrep -f "$PWD/$APP/Contents/MacOS/" >/dev/null || break; sleep 0.25; done
open "$APP"
echo "Launched $APP"
