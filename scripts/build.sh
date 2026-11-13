#!/bin/zsh
# release: build one distribution flavour. Usage: scripts/build.sh [direct|appstore|all] [Debug|Release]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
FLAVOUR="${1:-direct}"; CONFIG="${2:-Debug}"
cd "$ROOT"
if [[ "$FLAVOUR" == "all" ]]; then "$0" direct "$CONFIG"; "$0" appstore "$CONFIG"; exit 0; fi
SCHEME="$(scheme_for "$FLAVOUR")"
acquire_build_slot
xcodegen generate --quiet
mkdir -p "$DERIVED"
LOG="$DERIVED/last-build-$SCHEME.log"
if ! xcodebuild -project Bitlathe.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" -derivedDataPath "$DERIVED" \
     -destination 'platform=macOS' build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u || tail -25 "$LOG"
  die "build failed (log: $LOG)"
fi
grep -E "warning:" "$LOG" | grep -v appintentsmetadataprocessor | sort -u || true
echo "** BUILD SUCCEEDED ** $SCHEME $CONFIG -> $DERIVED/Build/Products/$CONFIG/Bitlathe.app"
