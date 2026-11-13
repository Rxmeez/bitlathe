#!/bin/zsh
# release: xcodebuild archive, universal (arm64 + x86_64).  ARCHS comes from ARCHS_STANDARD (passing ARCHS on the command line breaks the SwiftPM targets). Usage: scripts/archive.sh [direct|appstore|all]
# Signing: with TEAM_ID set the archive is signed by Xcode (automatic signing, needs your certificates in the keychain).
# Without TEAM_ID it is built ad-hoc signed and unexportable for distribution (fine for local verification).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
FLAVOUR="${1:-all}"
cd "$ROOT"
if [[ "$FLAVOUR" == "all" ]]; then "$0" direct; "$0" appstore; exit 0; fi
SCHEME="$(scheme_for "$FLAVOUR")"
ARCHIVE="$BUILD_DIR/archives/$SCHEME.xcarchive"
mkdir -p "$BUILD_DIR/archives" "$DERIVED"
rm -rf "$ARCHIVE"
SIGN=()
if [[ -n "${TEAM_ID:-}" ]]; then
  SIGN=(DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="-" -allowProvisioningUpdates)
  # Direct builds are signed Developer ID at export time; the archive carries a development signature.
else
  warn "TEAM_ID not set: archiving ad-hoc signed. The result cannot be notarised or uploaded."
  SIGN=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO)
fi
acquire_build_slot
xcodegen generate --quiet
LOG="$BUILD_DIR/archive-$SCHEME.log"
say "archiving $SCHEME (arm64 + x86_64)"
if ! xcodebuild archive -project Bitlathe.xcodeproj -scheme "$SCHEME" -configuration Release \
     -archivePath "$ARCHIVE" -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
     ONLY_ACTIVE_ARCH=NO "${SIGN[@]}" > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u || tail -25 "$LOG"
  die "archive failed (log: $LOG)"
fi
grep -E "warning:" "$LOG" | grep -v appintentsmetadataprocessor | sort -u || true
APP="$ARCHIVE/Products/Applications/Bitlathe.app"
echo "archived: $ARCHIVE"
echo "archs:    $(lipo -archs "$APP/Contents/MacOS/Bitlathe")"
