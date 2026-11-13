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
BIN="$SCRATCH-bl"
if (( ${#SLICES} > 1 )); then lipo -create "${SLICES[@]}" -output "$BIN"; else cp -f "${SLICES[1]}" "$BIN"; fi

# bl-advisor: the on-device model helper (Sources/BitlatheAdvisor). The model's framework (FoundationModels) is only
# in the macOS 26+ SDK. When Xcode is older than that, the Command Line Tools may still be new enough: build the
# helper with them. With no such SDK anywhere it still builds, and reports that no model is available.
ADVISOR_DEV=""
CLT=/Library/Developer/CommandLineTools
XCODE_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [[ ! -d "$XCODE_SDK/System/Library/Frameworks/FoundationModels.framework" && -x "$CLT/usr/bin/swift" ]] \
   && ls -d "$CLT"/SDKs/MacOSX*.sdk/System/Library/Frameworks/FoundationModels.framework >/dev/null 2>&1; then
  ADVISOR_DEV="$CLT"
fi
build_advisor() {  # $1 = DEVELOPER_DIR to use, or empty for the default toolchain
  local dev="$1" slices=() arch scratch out
  sw() { if [[ -n "$dev" ]]; then DEVELOPER_DIR="$dev" swift "$@"; else swift "$@"; fi }
  for arch in $ARCHS_TO_BUILD; do
    scratch="$SCRATCH-advisor${dev:+-clt}-$arch"
    sw build -c release --product bl-advisor --scratch-path "$scratch" --triple "$arch-apple-macosx14.0" 1>&2 || return 1
    out="$(sw build -c release --product bl-advisor --scratch-path "$scratch" --triple "$arch-apple-macosx14.0" --show-bin-path)/bl-advisor"
    [[ -x "$out" ]] || return 1
    slices+=("$out")
  done
  if (( ${#slices} > 1 )); then lipo -create "${slices[@]}" -output "$SCRATCH-bl-advisor"; else cp -f "${slices[1]}" "$SCRATCH-bl-advisor"; fi
}
if [[ -n "$ADVISOR_DEV" ]] && build_advisor "$ADVISOR_DEV"; then
  echo "embed-cli: bl-advisor built with $ADVISOR_DEV (on-device model support)"
else
  build_advisor "" || { echo "embed-cli: could not build bl-advisor" >&2; exit 1; }
fi
release_build_slot

DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
mkdir -p "$DEST"
cp -f "$BIN" "$DEST/bl"
cp -f "$SCRATCH-bl-advisor" "$DEST/bl-advisor"

# Sign the helper with the app's identity (ad-hoc "-" when unsigned) so notarisation accepts the bundle.
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]]; then
  echo "embed-cli: CODE_SIGNING_ALLOWED=NO, leaving bl unsigned"
else
  [[ -n "$IDENTITY" ]] || IDENTITY="-"
  for helper in bl bl-advisor; do
    if [[ "$IDENTITY" == "-" ]]; then codesign --force --sign - "$DEST/$helper"
    else codesign --force --options runtime --timestamp --sign "$IDENTITY" "$DEST/$helper"; fi
  done
fi
echo "embed-cli: $DEST/bl ($(lipo -archs "$DEST/bl")), $DEST/bl-advisor ($(lipo -archs "$DEST/bl-advisor"))"
