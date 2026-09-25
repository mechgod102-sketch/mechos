#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_CENTER_RESCUE_LAUNCHER_V0312
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/update-center-v8-launch.log"
mkdir -p "$(dirname "$LOG")"
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@" >>"$LOG" 2>&1
