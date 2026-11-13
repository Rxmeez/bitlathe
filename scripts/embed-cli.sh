#!/bin/zsh
# release: Xcode build phase of the Direct target. Builds the `bl` CLI and copies it into Bitlathe.app/Contents/Helpers.
# Release builds are universal (arm64 + x86_64); Debug builds are native only.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
: "${TARGET_BUILD_DIR:?run from an Xcode build phase}" "${CONTENTS_FOLDER_PATH:?}"

# Xcode's environment can shadow tools; use the toolchain swift.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
unset SDKROOT TOOLCHAINS MACOSX_DEPLOYMENT_TARGET

SCRATCH="$ROOT/.build/cli-embed"
acquire_build_slot
cd "$ROOT"
# Single-arch builds per architecture then lipo: `swift build --arch a --arch b` (XCBuild) fails on this package.
if [[ "${CONFIGURATION:-Debug}" == "Release" ]]; then ARCHS_TO_BUILD=(arm64 x86_64); else ARCHS_TO_BUILD=("$(uname -m)"); fi
SLICES=()
for arch in $ARCHS_TO_BUILD; do
  swift build -c release --product bl --scratch-path "$SCRATCH-$arch" --triple "$arch-apple-macosx14.0" 1>&2
  SLICES+=("$(swift build -c release --product bl --scratch-path "$SCRATCH-$arch" --triple "$arch-apple-macosx14.0" --show-bin-path)/bl")
done
release_build_slot
BIN="$SCRATCH-bl"
if (( ${#SLICES} > 1 )); then lipo -create "${SLICES[@]}" -output "$BIN"; else cp -f "${SLICES[1]}" "$BIN"; fi

DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
mkdir -p "$DEST"
cp -f "$BIN" "$DEST/bl"

# Sign the helper with the app's identity (ad-hoc "-" when unsigned) so notarisation accepts the bundle.
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]]; then
  echo "embed-cli: CODE_SIGNING_ALLOWED=NO, leaving bl unsigned"
else
  [[ -n "$IDENTITY" ]] || IDENTITY="-"
  if [[ "$IDENTITY" == "-" ]]; then codesign --force --sign - "$DEST/bl"
  else codesign --force --options runtime --timestamp --sign "$IDENTITY" "$DEST/bl"; fi
fi
echo "embed-cli: $DEST/bl ($(lipo -archs "$DEST/bl"))"
