#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MODE_LAUNCH_V19
# Backward-compatibility markers: v19 preserves the v15 Creator handoff/VM
# overlay and v16 routing for MechScope-owned pages.
# MECHOS_MODE_LAUNCH_V16
# MECHOS_MODE_LAUNCH_V15
# MECHOS_CREATOR_HANDOFF_V15
# MECHOS_CREATOR_VM_OVERLAY_V15
# MECHOS_CREATOR_EXTERNAL_QT_HANDOFF_V26
# Creator Mode owns its own Qt application and must never be imported/routed
# inside the live MechScope QApplication. Always use the proven Hotfix 15
# external Creator handoff, even while MechScope is already running.

MODE="${1:-}"
ROUTER=/usr/local/bin/mechos-shell-route
BASE=/usr/local/libexec/mechos-mode-launch-base-v15
CREATOR=/usr/local/libexec/mechos-creator-launch-v19

case "$MODE" in
  gaming|mechscope|creator|desktop) ;;
  *) echo 'Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}' >&2; exit 2 ;;
esac

case "$MODE" in
  creator)
    [ -x "$CREATOR" ] || { echo 'MechOS Creator launcher is missing' >&2; exit 1; }
    exec "$CREATOR" creator
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
