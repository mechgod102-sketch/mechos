#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MECHSCOPE_SAFE_LAUNCH_V31
# MECHOS_MECHSCOPE_SINGLE_OWNER_V32

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/mechscope-safe-launch-v31.log"
LOCK="$STATE_DIR/mechscope-owner-v32.lock"
mkdir -p "$STATE_DIR"
log(){ printf '[%s] [mechscope-safe-launch-v31] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }

# One MechScope owner per graphical user. HF29-HF31 can leave both the
# supervised hardware session and the KDE fallback active while Plasma starts.
# Keep the lock fd open across exec so a second launcher cannot create another
# MechScope process while the first one is alive.
exec 9>"$LOCK"
if ! flock -n 9; then
  log "duplicate launch suppressed pid=$$ supervisor=${MECHOS_SESSION_SUPERVISED:-0}"
  exit 0
fi

is_python_target(){
  local target="$1" first
  [ -f "$target" ] || return 1
  first="$(head -n1 "$target" 2>/dev/null || true)"
  case "$first" in *python*) return 0 ;; esac
  grep -Eq '^[[:space:]]*(from|import)[[:space:]]+[A-Za-z0-9_\.]+' "$target" 2>/dev/null
}

python_source_check(){
  local target="$1"
  /usr/bin/python3 - "$target" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
source=p.read_text(encoding='utf-8')
compile(source,str(p),'exec')
PY
}

resolve_target(){
  if [ -n "${MECHOS_MECHSCOPE_TARGET:-}" ]; then
    printf '%s\n' "$MECHOS_MECHSCOPE_TARGET"
    return 0
  fi

  if [ -f /usr/local/libexec/mechos-mechscope-runtime-v23 ] && \
     [ -f /usr/local/libexec/mechscope-owner-v23.py ]; then
    printf '%s\n' /usr/local/libexec/mechos-mechscope-runtime-v23
  elif [ -f /usr/local/bin/mechscope.real ]; then
    printf '%s\n' /usr/local/bin/mechscope.real
  else
    return 1
  fi
}

target="$(resolve_target)" || {
  log 'ERROR: no MechScope target could be resolved'
  exit 127
}
[ -f "$target" ] || {
  log "ERROR: resolved target is missing: $target"
  exit 127
}

if is_python_target "$target"; then
  if ! python_source_check "$target" >>"$LOG" 2>&1; then
    log "ERROR: Python source validation failed target=$target"
    exit 126
  fi
  log "launch target=$target interpreter=/usr/bin/python3 args=$*"
  exec /usr/bin/python3 "$target" "$@"
fi

[ -x "$target" ] || {
  log "ERROR: non-Python target is not executable: $target"
  exit 126
}
log "launch target=$target interpreter=direct args=$*"
exec "$target" "$@"
