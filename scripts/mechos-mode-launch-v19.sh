#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MODE_LAUNCH_V19
# Creator Mode must never bootstrap Gaming/MechScope just to reach Creator.
# When the unified MechScope shell is already alive, Creator routes in-place.
# Otherwise the proven Hotfix 15 Creator launcher starts Creator directly.

MODE="${1:-}"
ROUTER=/usr/local/bin/mechos-shell-route
BASE=/usr/local/libexec/mechos-mode-launch-base-v15

case "$MODE" in
  gaming|mechscope|creator|desktop) ;;
  *) echo 'Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}' >&2; exit 2 ;;
esac

mechscope_host_running(){
  pgrep -u "$(id -u)" -f '(^|[[:space:]])(/usr/bin/python3[[:space:]]+)?/usr/local/bin/mechscope(\.real)?([[:space:]]|$)' >/dev/null 2>&1
}

case "$MODE" in
  creator)
    if mechscope_host_running && [ -x "$ROUTER" ]; then
      exec "$ROUTER" creator
    fi
    [ -x "$BASE" ] || { echo 'MechOS Creator launcher base missing' >&2; exit 1; }
    exec "$BASE" creator
    ;;
  gaming|mechscope)
    [ -x "$ROUTER" ] || { echo 'MechOS shell router missing' >&2; exit 1; }
    exec "$ROUTER" "$MODE"
    ;;
  desktop)
    [ -x "$BASE" ] || { echo 'MechOS base mode launcher missing' >&2; exit 1; }
    exec "$BASE" desktop
    ;;
esac
