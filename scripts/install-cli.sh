#!/bin/zsh
# release: install the `bl` command-line tool.
# Usage: scripts/install-cli.sh [--dest DIR] [--symlink] [--app /path/to/Bitlathe.app]
# Uses the bl embedded in Bitlathe.app (Contents/Helpers/bl) when present, otherwise builds it from source.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
DEST="/usr/local/bin"; APP="/Applications/Bitlathe.app"; LINK=0
while (( $# )); do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    --app) APP="$2"; shift 2 ;;
    --symlink) LINK=1; shift ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) die "unknown argument $1" ;;
  esac
done
SRC="$APP/Contents/Helpers/bl"
if [[ ! -x "$SRC" ]]; then
  warn "no bundled bl at $SRC; building from source"
  cd "$ROOT"; acquire_build_slot
  swift build -c release --product bl
  SRC="$(swift build -c release --product bl --show-bin-path)/bl"
  release_build_slot
  LINK=0
fi
mkdir -p "$DEST" 2>/dev/null || true
if [[ ! -w "$DEST" ]]; then
  echo "$DEST is not writable. Re-run with sudo, pick another folder, or run:"
  if (( LINK )); then echo "  sudo ln -sf '$SRC' '$DEST/bl'"; else echo "  sudo cp '$SRC' '$DEST/bl'"; fi
  exit 1
fi
rm -f "$DEST/bl"
if (( LINK )); then ln -s "$SRC" "$DEST/bl"; else cp "$SRC" "$DEST/bl"; chmod 755 "$DEST/bl"; fi
echo "installed $DEST/bl"
case ":$PATH:" in *":$DEST:"*) ;; *) echo "note: $DEST is not on your PATH" ;; esac
"$DEST/bl" --version 2>/dev/null || true
