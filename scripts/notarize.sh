#!/bin/zsh
# release: notarise and staple. Usage: scripts/notarize.sh <Bitlathe.app | Bitlathe.dmg | .zip>
# Needs NOTARY_PROFILE: a keychain profile created once with
#   xcrun notarytool store-credentials "<name>" --apple-id <id> --team-id <TEAM> --password <app-specific-password>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TARGET="${1:-}"; [[ -n "$TARGET" && -e "$TARGET" ]] || die "usage: scripts/notarize.sh <Bitlathe.app|Bitlathe.dmg>"
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  need "notarisation needs credentials. Set NOTARY_PROFILE to a notarytool keychain profile name (create it with: xcrun notarytool store-credentials \"<name>\" --apple-id <apple id> --team-id <TEAM_ID> --password <app-specific password>). The app must also be signed with a Developer ID Application certificate (scripts/export.sh with TEAM_ID)."
fi
if [[ -e "$(dirname "$TARGET")/UNSIGNED" ]]; then die "$TARGET was exported unsigned; re-export with TEAM_ID set"; fi
SUBMIT="$TARGET"; TMP=""
if [[ -d "$TARGET" ]]; then
  TMP="$(mktemp -d)"; SUBMIT="$TMP/$(basename "$TARGET" .app).zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
fi
say "submitting $(basename "$SUBMIT") to Apple (waits for the verdict)"
xcrun notarytool submit "$SUBMIT" --keychain-profile "$NOTARY_PROFILE" --wait
say "stapling"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
[[ -n "$TMP" ]] && rm -rf "$TMP"
echo "notarised: $TARGET"
