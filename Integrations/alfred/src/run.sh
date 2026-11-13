#!/bin/bash
# Run tool $1 (or saved pipeline pipeline.<slug>) on the clipboard; print the result for the next workflow nodes.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
if ! BL="$(find_bl)"; then echo "bl is not installed (Bitlathe > Settings > Integrations)"; exit 0; fi
ID="$1"
if [ "${ID#pipeline.}" != "$ID" ]; then set -- pipeline "${ID#pipeline.}"; else set -- "$ID"; fi
ERR="$(mktemp)"
if OUT="$(pbpaste | "$BL" "$@" 2>"$ERR")"; then
  printf '%s' "$OUT"
else
  echo "Bitlathe error: $(head -n 1 "$ERR")"
fi
rm -f "$ERR"
