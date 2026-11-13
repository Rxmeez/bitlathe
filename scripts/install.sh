#!/bin/zsh
# Build the Release app ("Bitlathe", com.bitlathe.app) and install it into /Applications.
# Usage: scripts/install.sh [--no-open]        (or: make install)
#
# The everyday app lives in /Applications; development happens in "Bitlathe Dev" (scripts/run.sh), which has its own
# bundle id, data, URL scheme (bitlathe-dev://), hotkeys (with Shift) and icon, so the two run side by side.
# Your settings and history stay in the app's container and survive reinstalls.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
DEST="/Applications/Bitlathe.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

say "Building Bitlathe (Release)"
acquire_build_slot
xcodegen generate --quiet
mkdir -p "$DERIVED"
LOG="$DERIVED/last-install-build.log"
# This copy is signed ad hoc (no Developer ID on this Mac). Under the hardened runtime, library validation then
# refuses the embedded Sparkle.framework ("different Team IDs") and the app dies at launch, so the local install
# turns the hardened runtime off. The App Sandbox still applies. Notarised releases (scripts/release.sh) sign with a
# team and keep it on.
if ! xcodebuild -project Bitlathe.xcodeproj -scheme Bitlathe -configuration Release -derivedDataPath "$DERIVED" \
     -destination 'platform=macOS' ENABLE_HARDENED_RUNTIME=NO build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u || tail -25 "$LOG"
  die "build failed (log: $LOG)"
fi
release_build_slot
APP="$DERIVED/Build/Products/Release/Bitlathe.app"
[[ -d "$APP" ]] || die "no app at $APP"
codesign --verify --deep --strict "$APP" || die "the built app's signature does not verify"

# Quit the installed copy if it is running. Matched by path, so "Bitlathe Dev" keeps running.
RUNNING="^$DEST/Contents/MacOS/Bitlathe\$"
if pgrep -f "$RUNNING" >/dev/null; then
  say "Quitting the running Bitlathe"
  pkill -TERM -f "$RUNNING" || true
  for _ in {1..40}; do pgrep -f "$RUNNING" >/dev/null || break; sleep 0.25; done
fi

say "Installing to $DEST"
STAGE="/Applications/.Bitlathe.app.installing"
rm -rf "$STAGE"
ditto "$APP" "$STAGE"
if [[ -d "$DEST" ]]; then
  rm -rf "$DEST" || die "could not replace $DEST. If macOS blocked it, allow your terminal under System Settings › Privacy & Security › App Management."
fi
mv "$STAGE" "$DEST"

# Only the installed copy should answer bitlathe:// links, Services and Quick Look for com.bitlathe.app:
# forget build products with that bundle id elsewhere in this repo (DerivedData, archives, old worktrees).
$LSREG -dump 2>/dev/null | sed -nE "s|^path: +(${ROOT}/.*/Bitlathe\.app) \(0x[0-9a-f]+\)\$|\1|p" | sort -u |
  while IFS= read -r p; do $LSREG -u "$p" >/dev/null 2>&1 || true; done
$LSREG -f -R "$DEST"
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

say "Installed Bitlathe $(defaults read "$DEST/Contents/Info" CFBundleShortVersionString) at $DEST"
[[ "${1:-}" == "--no-open" ]] || open "$DEST"
