#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VM_MECHSCOPE_WATCHDOG_V29

CORE=/usr/local/libexec/mechos-vm-mode-runtime-v5
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/session-mode"
LOG="$STATE_DIR/vm-mode-runtime.log"
mkdir -p "$STATE_DIR"

log(){ printf '[%s] [watchdog] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }
mechscope_running(){
  pgrep -u "$(id -u)" -f '(/usr/bin/python3[[:space:]]+)?/usr/local/(bin/mechscope(\.real)?|libexec/mechos-mechscope-runtime-v23)([[:space:]]|$)' >/dev/null 2>&1
}
gaming_active(){
  [ -r "$MODE_FILE" ] && [ "$(tr -d '[:space:]' <"$MODE_FILE")" = gaming ]
}

[ -x "$CORE" ] || exit 0
log 'watchdog started'
failures=0
while gaming_active; do
  sleep 2
  gaming_active || break
  if mechscope_running; then
    failures=0
    continue
  fi

  failures=$((failures + 1))
  log "MechScope process disappeared while Gaming Mode remains active; recovery attempt=$failures"
  if "$CORE" gaming; then
    sleep 4
    if mechscope_running; then
      log 'MechScope recovered successfully'
      failures=0
      continue
    fi
  fi

  if [ "$failures" -ge 3 ]; then
    log 'MechScope recovery stopped after three consecutive failures; inspect vm-mechscope-launch.log and mechscope-runtime-v23.log'
    exit 1
  fi
  sleep "$failures"
done
log 'watchdog stopped because Gaming Mode is no longer active'
