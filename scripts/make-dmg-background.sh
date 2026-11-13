#!/bin/zsh
# release: regenerate Distribution/dmg-background.tiff (660x400 @1x + @2x) with CoreGraphics.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
T="$(mktemp -d)"
swift "$ROOT/scripts/make-dmg-background.swift" "$T/bg.png" 660 400 1
swift "$ROOT/scripts/make-dmg-background.swift" "$T/bg@2x.png" 660 400 2
tiffutil -cathidpicheck "$T/bg.png" "$T/bg@2x.png" -out "$ROOT/Distribution/dmg-background.tiff"
rm -rf "$T"; echo "wrote Distribution/dmg-background.tiff"
