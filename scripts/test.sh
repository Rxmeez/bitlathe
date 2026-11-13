#!/bin/zsh
# release: unit tests, then a build of both distribution flavours and the CLI. Usage: scripts/test.sh [--quick]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
acquire_build_slot
say "swift test"
swift test
release_build_slot
[[ "${1:-}" == "--quick" ]] && exit 0
say "swift build --product bl"
acquire_build_slot; swift build --product bl; release_build_slot
"$ROOT/scripts/build.sh" all Debug
