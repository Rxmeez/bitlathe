#!/bin/bash
# Builds Bitlathe.alfredworkflow (a zip of info.plist + scripts). Usage: Integrations/alfred/build.sh [output-dir]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$HERE"/src/info.plist "$HERE"/src/common.sh "$HERE"/src/filter.sh "$HERE"/src/filter.js "$HERE"/src/run.sh "$STAGE/"
[ -f "$HERE/src/icon.png" ] && cp "$HERE/src/icon.png" "$STAGE/"
chmod +x "$STAGE"/*.sh
plutil -lint "$STAGE/info.plist" >/dev/null
mkdir -p "$OUT"
rm -f "$OUT/Bitlathe.alfredworkflow"
(cd "$STAGE" && /usr/bin/zip -qr -X "$OUT/Bitlathe.alfredworkflow" .)
echo "Built $OUT/Bitlathe.alfredworkflow"
