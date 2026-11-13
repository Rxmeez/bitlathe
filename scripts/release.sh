#!/bin/zsh
# release: full release pipeline. Usage: scripts/release.sh <version> [--skip-STEP ...] [--dry-run]
# Steps (in order): bump archive export notarize dmg appcast cask github appstore
#   scripts/release.sh 1.2.0                         everything; stops at notarize without NOTARY_PROFILE
#   scripts/release.sh 1.2.0 --skip-notarize --skip-github   local unsigned dmg for testing
# Env: TEAM_ID, DEVELOPER_ID ("Developer ID Application: Name (TEAM)"), NOTARY_PROFILE, BUILD_NUMBER,
#      SPARKLE_BIN (dir with generate_appcast/sign_update), GITHUB_REPO (default Rxmeez/bitlathe), ALLOW_UNSIGNED=1.
# The appstore step only archives+exports the App Store build; uploading is manual (Transporter/Xcode), see Docs/Release.md.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
VERSION="${1:-}"; shift || true
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "usage: scripts/release.sh <semver, e.g. 1.2.0> [--skip-<step>] [--dry-run]"
STEPS=(bump archive export notarize dmg appcast cask github appstore)
typeset -A SKIP; DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --skip-*) s="${a#--skip-}"; [[ " ${STEPS[*]} " == *" $s "* ]] || die "unknown step '$s'"; SKIP[$s]=1 ;;
    *) die "unknown argument $a" ;;
  esac
done
run_step() { # name, then command...
  local name="$1"; shift
  if [[ -n "${SKIP[$name]:-}" ]]; then echo "-- skip $name"; return 0; fi
  say "step: $name"
  if (( DRY )); then echo "(dry run) $*"; return 0; fi
  "$@"
}

APP="$BUILD_DIR/export/Bitlathe/Bitlathe.app"
DMG="$BUILD_DIR/dmg/Bitlathe-$VERSION.dmg"
REPO="${GITHUB_REPO:-Rxmeez/bitlathe}"

step_bump() {
  local build="${BUILD_NUMBER:-$(( $(build_number) + 1 ))}"
  sed -i '' -E "s/^( *MARKETING_VERSION:) .*/\1 \"$VERSION\"/; s/^( *CURRENT_PROJECT_VERSION:) .*/\1 \"$build\"/" project.yml
  echo "version $VERSION (build $build) written to project.yml"
}
step_archive()  { "$ROOT/scripts/archive.sh" all; }
step_export()   { "$ROOT/scripts/export.sh" all; }
step_notarize() { "$ROOT/scripts/notarize.sh" "$APP"; }
step_dmg() {
  "$ROOT/scripts/dmg.sh" "$APP"
  # The dmg itself is notarised and stapled too, so Gatekeeper accepts it offline.
  if [[ -n "${NOTARY_PROFILE:-}" && -z "${SKIP[notarize]:-}" ]]; then "$ROOT/scripts/notarize.sh" "$DMG"; fi
}
find_sparkle_bin() {
  local d
  for d in "${SPARKLE_BIN:-}" "$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin" "$(dirname "$(command -v generate_appcast 2>/dev/null || echo /nonexistent/x)")"; do
    [[ -n "$d" && -x "$d/generate_appcast" ]] && { echo "$d"; return 0; }
  done
  return 1
}
step_appcast() {
  [[ -f "$DMG" ]] || die "no dmg at $DMG"
  local bin; bin="$(find_sparkle_bin)" || { warn "Sparkle's generate_appcast not found (set SPARKLE_BIN, or build the Direct scheme once so SwiftPM fetches Sparkle). Skipping the appcast."; return 0; }
  local feed="$BUILD_DIR/appcast"; mkdir -p "$feed"; cp "$DMG" "$feed/"
  # The EdDSA private key is read from the login keychain (created once with Sparkle's generate_keys).
  "$bin/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" "$feed"
  echo "appcast: $feed/appcast.xml (upload it to the GitHub release; the app reads .../releases/latest/download/appcast.xml)"
}
step_cask() {
  [[ -f "$DMG" ]] || die "no dmg at $DMG"
  local sha; sha="$(shasum -a 256 "$DMG" | awk '{print $1}')"
  sed -i '' -E "s/^( *version) \".*\"/\1 \"$VERSION\"/; s/^( *sha256) \".*\"/\1 \"$sha\"/" Distribution/homebrew/bitlathe.rb
  echo "cask: version $VERSION sha256 $sha"
}
step_github() {
  command -v gh >/dev/null || need "the GitHub CLI (gh) is required: brew install gh && gh auth login"
  gh auth status >/dev/null 2>&1 || need "gh is not logged in: run gh auth login"
  [[ -f "$DMG" ]] || die "no dmg at $DMG"
  if [[ -e "$BUILD_DIR/dmg/UNSIGNED" && "${ALLOW_UNSIGNED:-0}" != "1" ]]; then
    need "refusing to publish an unsigned dmg. Set TEAM_ID/DEVELOPER_ID/NOTARY_PROFILE, or ALLOW_UNSIGNED=1 for a pre-release test."
  fi
  local assets=("$DMG"); [[ -f "$BUILD_DIR/appcast/appcast.xml" ]] && assets+=("$BUILD_DIR/appcast/appcast.xml")
  gh release create "v$VERSION" "${assets[@]}" --repo "$REPO" --title "Bitlathe $VERSION" --generate-notes
}
step_appstore() { echo "App Store archive: $BUILD_DIR/export/Bitlathe-AppStore (upload with Transporter or: xcrun altool/ Xcode Organizer)"; ls "$BUILD_DIR/export/Bitlathe-AppStore" 2>/dev/null || true; }

for s in $STEPS; do run_step "$s" "step_$s"; done
say "release $VERSION done"
