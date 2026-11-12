#!/bin/zsh
# Rebuild the app and relaunch it. Usage: scripts/run.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
CONFIG="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
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
APP="$DERIVED/Build/Products/$CONFIG/Bitlathe.app"
if [[ "${BUILD_ONLY:-0}" == "1" ]]; then echo "Built $APP"; exit 0; fi
if [[ ! -d "$APP" ]]; then echo "Build failed"; exit 1; fi
pkill -x Bitlathe 2>/dev/null || true
open "$APP"
echo "Launched $APP"
