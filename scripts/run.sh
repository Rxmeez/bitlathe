#!/bin/zsh
# Rebuild the app and relaunch it. Usage: scripts/run.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
CONFIG="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
if [[ ! -d Bitlathe.xcodeproj || project.yml -nt Bitlathe.xcodeproj/project.pbxproj ]]; then
  xcodegen generate --quiet
fi
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
if [[ ! -d "$APP" ]]; then echo "Build failed"; exit 1; fi
pkill -x Bitlathe 2>/dev/null || true
open "$APP"
echo "Launched $APP"
