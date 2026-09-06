#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MODE_LAUNCH_V16
MODE="${1:-gaming}"
ROUTER=/usr/local/bin/mechos-shell-route
BASE=/usr/local/libexec/mechos-mode-launch-base-v15

case "$MODE" in
  gaming|mechscope|creator)
    [ -x "$ROUTER" ] || { echo 'MechOS shell router missing' >&2; exit 1; }
    exec "$ROUTER" "$MODE"
    ;;
  desktop)
    [ -x "$BASE" ] || { echo 'MechOS base mode launcher missing' >&2; exit 1; }
    exec "$BASE" desktop
    ;;
  *)
    echo 'Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}' >&2
    exit 2
    ;;
esac
