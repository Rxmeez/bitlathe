#!/bin/zsh
# release: build Bitlathe-<version>.dmg with a background image and an Applications link (create-dmg).
# Usage: scripts/dmg.sh [path/to/Bitlathe.app]   (default: build/export/Bitlathe/Bitlathe.app)
# Signs the dmg when DEVELOPER_ID is set (e.g. "Developer ID Application: Your Name (TEAMID)").
set -euo pipefail
source "$(dirname "$0")/lib.sh"
command -v create-dmg >/dev/null || die "create-dmg not found (brew install create-dmg)"
APP="${1:-$BUILD_DIR/export/Bitlathe/Bitlathe.app}"
[[ -d "$APP" ]] || die "no app at $APP; run scripts/export.sh direct first"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="$BUILD_DIR/dmg"; DMG="$OUT/Bitlathe-$VERSION.dmg"
BG="$ROOT/Distribution/dmg-background.tiff"
[[ -f "$BG" ]] || "$ROOT/scripts/make-dmg-background.sh"
mkdir -p "$OUT"; rm -f "$DMG"
STAGE="$(mktemp -d)"; ditto "$APP" "$STAGE/Bitlathe.app"
SIGN=(); [[ -n "${DEVELOPER_ID:-}" ]] && SIGN=(--codesign "$DEVELOPER_ID")
say "creating $DMG"
create-dmg --volname "Bitlathe $VERSION" --background "$BG" --window-pos 200 120 --window-size 660 400 \
  --icon-size 100 --icon "Bitlathe.app" 180 190 --hide-extension "Bitlathe.app" --app-drop-link 480 190 \
  --no-internet-enable "${SIGN[@]}" "$DMG" "$STAGE"
rm -rf "$STAGE"
[[ -e "$(dirname "$APP")/UNSIGNED" ]] && touch "$OUT/UNSIGNED" || rm -f "$OUT/UNSIGNED"
echo "dmg: $DMG"
