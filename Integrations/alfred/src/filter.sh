#!/bin/bash
# Script filter. $1 = mode (list|detect), $2 = typed query.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
MODE="$1"; QUERY="${2:-}"
if ! BL="$(find_bl)"; then
  echo '{"items":[{"title":"bl is not installed","subtitle":"Open Bitlathe > Settings > Integrations > Install CLI, or set BL_PATH in this workflow","valid":false}]}'
  exit 0
fi
if [ "$MODE" = "detect" ]; then
  pbpaste | "$BL" detect --json | /usr/bin/osascript -l JavaScript "$DIR/filter.js" detect "$QUERY"
else
  "$BL" list --json | /usr/bin/osascript -l JavaScript "$DIR/filter.js" list "$QUERY"
fi
