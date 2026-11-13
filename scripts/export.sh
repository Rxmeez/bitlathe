#!/bin/zsh
# release: export an archive. Usage: scripts/export.sh [direct|appstore|all]
# Signed export (xcodebuild -exportArchive with Distribution/ExportOptions/*.plist) needs TEAM_ID and the matching
# certificate. Without TEAM_ID the .app is copied out of the archive unsigned-for-distribution (local testing only)
# and a marker file build/export/<scheme>/UNSIGNED is written so later steps refuse to publish it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
FLAVOUR="${1:-all}"
cd "$ROOT"
if [[ "$FLAVOUR" == "all" ]]; then "$0" direct; "$0" appstore; exit 0; fi
SCHEME="$(scheme_for "$FLAVOUR")"
ARCHIVE="$BUILD_DIR/archives/$SCHEME.xcarchive"
OUT="$BUILD_DIR/export/$SCHEME"
[[ -d "$ARCHIVE" ]] || die "no archive at $ARCHIVE; run scripts/archive.sh $FLAVOUR first"
rm -rf "$OUT"; mkdir -p "$OUT"
if [[ -n "${TEAM_ID:-}" ]]; then
  PLIST_SRC="$ROOT/Distribution/ExportOptions/$([[ $SCHEME == Bitlathe ]] && echo developer-id || echo app-store).plist"
  PLIST="$BUILD_DIR/ExportOptions-$SCHEME.plist"
  sed "s/__TEAM_ID__/$TEAM_ID/" "$PLIST_SRC" > "$PLIST"
  say "exporting $SCHEME with $(basename "$PLIST_SRC")"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" -exportOptionsPlist "$PLIST" -allowProvisioningUpdates \
    > "$BUILD_DIR/export-$SCHEME.log" 2>&1 || { tail -20 "$BUILD_DIR/export-$SCHEME.log"; die "export failed (is the certificate for team $TEAM_ID installed?)"; }
else
  warn "TEAM_ID not set: copying the .app out of the archive without distribution signing."
  ditto "$ARCHIVE/Products/Applications/Bitlathe.app" "$OUT/Bitlathe.app"
  touch "$OUT/UNSIGNED"
fi
echo "exported: $OUT"
ls "$OUT"
