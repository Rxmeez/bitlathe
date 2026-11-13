#!/bin/zsh
# Builds, signs and publishes a self-signed Bitlathe release (the pattern Superkeys uses: no Apple Developer ID).
#
#   scripts/ship.sh 0.2.0            publish
#   scripts/ship.sh 0.2.0 --dry-run  build, sign and package only; publish nothing, change nothing in git
#
# This is the release path while there is no Developer ID. scripts/release.sh is the notarised path for when there is.
#
# Before publishing: run scripts/setup-signing-keys.sh once, set RELEASES_REPO below (and SU_FEED_URL in project.yml
# to match), add a "## [0.2.0] - YYYY-MM-DD" section to CHANGELOG.md, and commit everything.
# Keys come from the 1Password vault "Bitlathe" (Touch ID) and never touch the repo: the certificate goes into a
# throwaway keychain deleted on exit, and the Sparkle key is piped straight into Sparkle's tools.
#
# What it does:
#   0. runs the tests, and stops if any fail
#   1. bumps the version and build number in project.yml
#   2. builds a universal Release app signed as "Bitlathe"
#   3. zips it and writes the Sparkle update feed (appcast.xml), signed
#   4. commits, tags vX.Y.Z and pushes
#   5. creates the release in RELEASES_REPO with the zip, the feed and the changelog notes
#   6. bumps the cask in Rxmeez/homebrew-tap
#
# A dry run without the 1Password keys signs ad hoc and skips the feed signature, so the build and packaging can be
# checked before any key exists.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

VERSION=${1:?usage: scripts/ship.sh <version> [--dry-run]}
DRY_RUN=${2:-}
VAULT="Bitlathe"
# The PUBLIC repository whose releases hold the downloads (the source repo is private, and Homebrew and Sparkle need
# a public URL). Empty until that is decided: publishing refuses to run without it.
RELEASES_REPO="${RELEASES_REPO:-}"
TAP_REPO="Rxmeez/homebrew-tap"
TAP="$(brew --repository 2>/dev/null)/Library/Taps/rxmeez/homebrew-tap"
BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
OUT="$BUILD_DIR/ship"
ZIP="$OUT/Bitlathe-$VERSION.zip"
dry() { [[ "$DRY_RUN" == "--dry-run" ]]; }

# --- Checks -------------------------------------------------------------------------
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "version must look like 1.2.3"
[[ -z "$DRY_RUN" || "$DRY_RUN" == "--dry-run" ]] || die "unknown argument $DRY_RUN"
NOTES_SECTION="$VERSION"
HAVE_KEYS=0
# SHIP_NO_KEYS=1 keeps a dry run away from 1Password altogether (no Touch ID prompt).
if [[ -z "${SHIP_NO_KEYS:-}" ]] && command -v op >/dev/null && op item get "Bitlathe signing certificate" --vault "$VAULT" >/dev/null 2>&1; then HAVE_KEYS=1; fi
if dry; then
  # A dry run may use the Unreleased notes, a dirty tree, and no keys.
  grep -q "^## \[$VERSION\]" CHANGELOG.md || NOTES_SECTION="Unreleased"
  (( HAVE_KEYS )) || warn "no keys in 1Password vault \"$VAULT\": signing ad hoc and leaving the feed unsigned (dry run only)"
else
  [[ -n "$RELEASES_REPO" ]] || die "set RELEASES_REPO to the public repo that will hold the downloads (see the top of this script)"
  [[ "$(gh repo view "$RELEASES_REPO" --json visibility --jq .visibility 2>/dev/null)" == PUBLIC ]] || die "$RELEASES_REPO must exist and be public"
  grep -q "SU_FEED_URL: https://github.com/$RELEASES_REPO/releases/latest/download/appcast.xml" project.yml \
    || die "SU_FEED_URL in project.yml must be https://github.com/$RELEASES_REPO/releases/latest/download/appcast.xml, or installed copies will never see updates"
  (( HAVE_KEYS )) || die "run scripts/setup-signing-keys.sh first"
  grep -qE 'SU_PUBLIC_ED_KEY: "[^"]+"' project.yml || die "SU_PUBLIC_ED_KEY is empty in project.yml: run scripts/setup-signing-keys.sh"
  [[ -z "$(git status --porcelain)" ]] || die "commit or stash your changes first"
  [[ "$(git branch --show-current)" == main ]] || die "release from main"
  git pull -q --ff-only || die "main has diverged from origin; pull and sort it out first"
  git rev-parse "v$VERSION" >/dev/null 2>&1 && die "v$VERSION is already tagged"
  grep -q "^## \[$VERSION\]" CHANGELOG.md || die "add a '## [$VERSION] - $(date +%F)' section to CHANGELOG.md"
  [[ -d "$TAP" ]] || die "tap the cask repo first: brew tap rxmeez/tap"
fi

# --- Tests ----------------------------------------------------------------------------
say "Running the tests"
TEST_LOG=$(swift test 2>&1 || true)
[[ "$TEST_LOG" == *"with 0 failures"* && "$TEST_LOG" != *"error:"* ]] || { print -r -- "$TEST_LOG" | grep -E "error:|failed" | head -20; die "tests failed"; }

# --- Signing certificate into a throwaway keychain -------------------------------------
IDENTITY="-"
SIGN_FLAGS="--timestamp=none"
if (( HAVE_KEYS )); then
  say "Reading the signing certificate from 1Password"
  KEYCHAIN="$(mktemp -d)/release.keychain-db"
  KEYCHAIN_PASSWORD=$(openssl rand -base64 24)
  ORIGINAL_KEYCHAINS=("${(@f)$(security list-keychains -d user | sed 's/^ *"//; s/"$//')}")
  cleanup() {
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" 2>/dev/null || true
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    rm -rf "$(dirname "$KEYCHAIN")"
    release_build_slot
  }
  trap cleanup EXIT
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings -lut 3600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  P12="$(dirname "$KEYCHAIN")/bitlathe.p12"
  op read "op://$VAULT/Bitlathe signing certificate/p12_base64" | base64 -d > "$P12"
  security import "$P12" -k "$KEYCHAIN" -P "$(op read "op://$VAULT/Bitlathe signing certificate/password")" -T /usr/bin/codesign >/dev/null
  rm -f "$P12"
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
  security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
  IDENTITY="Bitlathe"
  SIGN_FLAGS="--keychain $KEYCHAIN --timestamp=none"
fi

# --- Version ----------------------------------------------------------------------------
cp project.yml "$TMPDIR/bitlathe-project.yml.before"
BUILD=$(( $(sed -n -E 's/^ *CURRENT_PROJECT_VERSION: *"?([0-9]+)"?.*/\1/p' project.yml | head -1) + 1 ))
say "Bitlathe $VERSION (build $BUILD)"
sed -i '' -E "s/^( *MARKETING_VERSION:) .*/\1 \"$VERSION\"/; s/^( *CURRENT_PROJECT_VERSION:) .*/\1 \"$BUILD\"/" project.yml
restore_version() { cp "$TMPDIR/bitlathe-project.yml.before" project.yml; xcodegen generate --quiet || true; }

# --- Build ------------------------------------------------------------------------------
say "Building a universal Release app, signed as \"$IDENTITY\""
acquire_build_slot
xcodegen generate --quiet
mkdir -p "$DERIVED" "$OUT"
LOG="$DERIVED/last-ship-build.log"
# Without a team, library validation under the hardened runtime refuses the embedded Sparkle.framework and the app
# dies at launch, so it is off here (as in scripts/install.sh). The App Sandbox still applies.
# BL_SELF_SIGNED tells scripts/embed-cli.sh to sign the helpers the same way (no timestamp server, no runtime flag).
if ! BL_SELF_SIGNED=1 xcodebuild -project Bitlathe.xcodeproj -scheme Bitlathe -configuration Release -derivedDataPath "$DERIVED" \
     -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO ENABLE_HARDENED_RUNTIME=NO \
     CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="" OTHER_CODE_SIGN_FLAGS="$SIGN_FLAGS" \
     build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u | head -20 || tail -25 "$LOG"
  restore_version
  die "build failed (log: $LOG)"
fi
release_build_slot
APP="$DERIVED/Build/Products/Release/Bitlathe.app"
[[ "$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)" == "$VERSION" ]] || { restore_version; die "the built app is not version $VERSION"; }
codesign --verify --deep --strict "$APP" || { restore_version; die "signature check failed"; }
if (( HAVE_KEYS )); then
  [[ "$(codesign -dvv "$APP" 2>&1)" == *"Authority=Bitlathe"* ]] || { restore_version; die "not signed as Bitlathe"; }
fi
for helper in bl bl-advisor; do
  [[ "$(lipo -archs "$APP/Contents/Helpers/$helper")" == *arm64* && "$(lipo -archs "$APP/Contents/Helpers/$helper")" == *x86_64* ]] \
    || { restore_version; die "$helper is not universal"; }
done
[[ "$(lipo -archs "$APP/Contents/MacOS/Bitlathe")" == *x86_64* ]] || { restore_version; die "the app is not universal"; }

# --- Package ----------------------------------------------------------------------------
say "Packaging $ZIP"
rm -rf "$OUT"; mkdir -p "$OUT/feed"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
cp "$ZIP" "$OUT/feed/"
# Release notes for Sparkle's update window, from CHANGELOG.md (ASCII with character references, so older copies
# that assume Latin-1 do not garble punctuation).
python3 - "$NOTES_SECTION" > "$OUT/feed/Bitlathe-$VERSION.html" <<'PY'
import html, re, sys
version = sys.argv[1]
text = open("CHANGELOG.md").read()
m = re.search(rf"^## \[{re.escape(version)}\].*?\n(.*?)(?=^## \[|^\[|\Z)", text, re.S | re.M)
section = m.group(1) if m else ""
def inline(s):
    s = html.escape(s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", s)
out, in_list = [], False
for line in section.strip().splitlines():
    if line.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        out.append(f"<li>{inline(line[2:])}</li>")
        continue
    if in_list: out.append("</ul>"); in_list = False
    if line.startswith("### "): out.append(f"<h3>{inline(line[4:])}</h3>")
    elif line.strip(): out.append(f"<p>{inline(line)}</p>")
if in_list: out.append("</ul>")
print("\n".join(out).encode("ascii", "xmlcharrefreplace").decode())
PY

if (( HAVE_KEYS )); then
  say "Signing the update feed"
  op read "op://$VAULT/Sparkle update key/credential" | "$BIN/generate_appcast" --ed-key-file - \
    --download-url-prefix "https://github.com/${RELEASES_REPO:-OWNER/REPO}/releases/download/v$VERSION/" \
    --embed-release-notes --maximum-deltas 0 -o "$OUT/appcast.xml" "$OUT/feed"
  grep -q "<sparkle:shortVersionString>$VERSION<" "$OUT/appcast.xml" || { restore_version; die "appcast is missing $VERSION"; }
fi

# The cask as it will be published.
sed -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/; s|OWNER/REPO|${RELEASES_REPO:-OWNER/REPO}|g" \
  Distribution/homebrew/bitlathe.rb > "$OUT/bitlathe.rb"

if dry; then
  restore_version
  say "Dry run: built and packaged Bitlathe $VERSION. Nothing published; project.yml restored."
  echo "  app   $APP ($(lipo -archs "$APP/Contents/MacOS/Bitlathe"); signed: $( (( HAVE_KEYS )) && echo Bitlathe || echo 'ad hoc'))"
  echo "  zip   $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '), sha256 $SHA)"
  echo "  cask  $OUT/bitlathe.rb"
  (( HAVE_KEYS )) && echo "  feed  $OUT/appcast.xml" || echo "  feed  not written (no Sparkle key yet)"
  exit 0
fi

# --- Publish ------------------------------------------------------------------------------
say "Committing and tagging v$VERSION"
git add project.yml Bitlathe.xcodeproj 2>/dev/null || git add project.yml
git commit -q -m "Release $VERSION"
git tag -a "v$VERSION" -m "Bitlathe $VERSION"
git push -q && git push -q origin "v$VERSION"

# The release in the public repo is what Sparkle (latest/download/appcast.xml) and the cask download from.
say "Creating the release in $RELEASES_REPO"
scripts/release-notes.sh "$VERSION" | gh release create "v$VERSION" "$ZIP" "$OUT/appcast.xml" -R "$RELEASES_REPO" \
  --title "Bitlathe $VERSION" --notes-file - --latest

say "Waiting for the download to be served"
URL="https://github.com/$RELEASES_REPO/releases/download/v$VERSION/Bitlathe-$VERSION.zip"
for _ in {1..40}; do
  [[ "$(curl -sL -m 60 "$URL" | shasum -a 256 | cut -d' ' -f1)" == "$SHA" ]] && break
  sleep 5
done
[[ "$(curl -sL -m 60 "$URL" | shasum -a 256 | cut -d' ' -f1)" == "$SHA" ]] \
  || die "download not live yet; the cask was not bumped. Copy $OUT/bitlathe.rb to the tap when it is."

say "Bumping the Homebrew cask"
git -C "$TAP" pull -q
cp "$OUT/bitlathe.rb" "$TAP/Casks/bitlathe.rb"
git -C "$TAP" add Casks/bitlathe.rb
git -C "$TAP" commit -qm "bitlathe $VERSION"
git -C "$TAP" push -q

say "Released Bitlathe $VERSION: brew install --cask rxmeez/tap/bitlathe. Installed copies will offer it within a day."
