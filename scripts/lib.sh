# release: shared helpers, sourced by the other scripts (zsh or bash). Not executable on its own.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
DERIVED="$ROOT/.build/DerivedData"

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
# Credentials missing: explain and stop with exit code 2 so callers/CI can tell it from a real failure.
need() { printf 'STOPPED: %s\n' "$*" >&2; exit 2; }

# Many agents may build on this Mac at once: hold one of 3 build slots (same pattern as scripts/run.sh).
SLOT=""
acquire_build_slot() {
  # A parent script (e.g. build.sh -> xcodebuild -> embed-cli.sh) already holds a slot: do not take a second one.
  [[ -n "$SLOT" || -n "${BITLATHE_SLOT_HELD:-}" ]] && return 0
  local i n
  for i in $(seq 1 2400); do
    for n in 1 2 3; do
      if mkdir "/tmp/bitlathe-build-slot-$n" 2>/dev/null; then SLOT="/tmp/bitlathe-build-slot-$n"; export BITLATHE_SLOT_HELD=1; trap release_build_slot EXIT; return 0; fi
    done
    sleep 0.5
  done
  die "no build slot became free"
}
release_build_slot() { [[ -n "$SLOT" ]] && rmdir "$SLOT" 2>/dev/null || true; SLOT=""; unset BITLATHE_SLOT_HELD; }

# direct -> Bitlathe, appstore -> Bitlathe-AppStore
scheme_for() {
  case "$1" in
    direct|Bitlathe) echo Bitlathe ;;
    appstore|app-store|Bitlathe-AppStore) echo Bitlathe-AppStore ;;
    *) die "unknown flavour '$1' (use direct or appstore)" ;;
  esac
}
flavour_for() { [[ "$1" == "Bitlathe-AppStore" ]] && echo appstore || echo direct; }

marketing_version() { sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?.*/\1/p' "$ROOT/project.yml" | head -1; }
build_number()      { sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([^"]+)"?.*/\1/p' "$ROOT/project.yml" | head -1; }

has_identity() { security find-identity -v -p codesigning 2>/dev/null | grep -q "$1"; }
