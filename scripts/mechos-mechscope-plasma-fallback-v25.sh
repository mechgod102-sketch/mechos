#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MECHSCOPE_PLASMA_FALLBACK_V25

MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/session-mode"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
REQUEST="$STATE_DIR/plasma-fallback-request-v25"
LOG_FILE="$STATE_DIR/mechscope-session-v23.log"
CRASH_MARKER="$STATE_DIR/mechscope-crash-loop-v33"
LOCK_FILE="$STATE_DIR/mechscope-owner-v32.lock"
RUNTIME=/usr/local/libexec/mechos-mechscope-source-runtime-v33

mkdir -p "$STATE_DIR" "$(dirname "$MODE_FILE")"

log(){
  printf '[%s] [mechscope-plasma-fallback-v25] %s\n'     "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG_FILE"
}

mode(){
  if [[ -r "$MODE_FILE" ]]; then
    tr -d '\r\n[:space:]' <"$MODE_FILE"
  else
    printf 'gaming'
  fi
}

safe_desktop(){
  local reason="$1"
  printf 'desktop\n' >"$MODE_FILE"
  printf '%s\n' "$reason" >"$CRASH_MARKER"
  rm -f "$REQUEST"
  log "SAFE FALLBACK: $reason; session-mode changed to desktop"
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --title 'MechScope Recovery' --error       'MechScope could not remain visible in Gaming Mode. MechOS left Plasma Desktop available. See ~/.local/state/mechos/mechscope-session-v23.log.'       >/dev/null 2>&1 || true
  fi
}

[[ -f "$REQUEST" ]] || exit 0
if [[ "$(mode)" != gaming ]]; then
  rm -f "$REQUEST"
  exit 0
fi

if [[ ! -f "$RUNTIME" ]]; then
  safe_desktop "source-owned MechScope runtime missing: $RUNTIME"
  exit 0
fi

if ! /usr/bin/python3 - "$RUNTIME" >>"$LOG_FILE" 2>&1 <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
then
  safe_desktop 'source-owned MechScope runtime failed Python validation'
  exit 0
fi

# Plasma autostart normally runs with the final display environment already
# imported. Still wait for the Wayland socket to exist so legacy/slow GPUs do
# not race KWin startup.
ready=0
for _ in $(seq 1 60); do
  if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" &&         -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
    ready=1
    break
  fi
  if [[ -n "${DISPLAY:-}" ]]; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" -ne 1 ]]; then
  safe_desktop 'Plasma display environment did not become ready within 60 seconds'
  exit 0
fi

log "Plasma display ready WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-none} DISPLAY=${DISPLAY:-none} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-none}"
sleep 2

# If another valid MechScope owner already holds the lock, do not start a
# duplicate or incorrectly count that as a crash.
if ! /usr/bin/flock -n "$LOCK_FILE" -c true >/dev/null 2>&1; then
  log 'MechScope owner lock already held; existing instance retained'
  exit 0
fi

export MECHOS_DISABLE_GAMESCOPE=1
export MECHOS_SESSION_SUPERVISED=1
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=KDE
export DESKTOP_SESSION=plasma

crashes=0
while [[ "$(mode)" == gaming && -f "$REQUEST" ]]; do
  started="$(date +%s)"
  log "starting visible MechScope after Plasma readiness attempt=$((crashes+1))"
  set +e
  /usr/bin/flock -n "$LOCK_FILE" /usr/bin/python3 "$RUNTIME" >>"$LOG_FILE" 2>&1
  rc=$?
  set -e
  elapsed=$(( $(date +%s) - started ))

  if [[ "$(mode)" != gaming ]]; then
    rm -f "$REQUEST"
    log "MechScope exited rc=$rc after intentional mode transition"
    exit 0
  fi

  if (( elapsed >= 30 )); then
    crashes=0
  else
    crashes=$((crashes+1))
  fi
  log "MechScope exited rc=$rc elapsed=${elapsed}s while Plasma fallback Gaming Mode active; crash-count=$crashes"

  if (( crashes >= 3 )); then
    safe_desktop "MechScope exited three times in under 30 seconds in Plasma fallback (last rc=$rc)"
    exit 0
  fi
  sleep $((crashes+1))
done

rm -f "$REQUEST"
exit 0
