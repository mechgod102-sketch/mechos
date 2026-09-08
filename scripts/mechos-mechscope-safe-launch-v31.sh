#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MECHSCOPE_SAFE_LAUNCH_V31
# MECHOS_MECHSCOPE_SINGLE_OWNER_V32
# MECHOS_MECHSCOPE_SOURCE_RUNTIME_ROUTE_V33

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/mechscope-safe-launch-v31.log"
LOCK="$STATE_DIR/mechscope-owner-v32.lock"
SOURCE_RUNTIME=/usr/local/libexec/mechos-mechscope-source-runtime-v33
LEGACY_RUNTIME=/usr/local/libexec/mechos-mechscope-runtime-v23
LEGACY_OWNER=/usr/local/libexec/mechscope-owner-v23.py
LEGACY_REAL=/usr/local/bin/mechscope.real
mkdir -p "$STATE_DIR"
log(){ printf '[%s] [mechscope-safe-launch-v31] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }

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
compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
}

resolve_target(){
  # Hotfix 33 makes the source-owned runtime authoritative on installed MechOS.
  # Do not automatically fall back to mechscope.real: that generated historical
  # owner is the source of the repeated hardware crash/relaunch loop.
  if [ -f "$SOURCE_RUNTIME" ]; then
    printf '%s\n' "$SOURCE_RUNTIME"
    return 0
  fi

  # Explicit override remains available for diagnostics/recovery only.
  if [ -n "${MECHOS_MECHSCOPE_TARGET:-}" ]; then
    printf '%s\n' "$MECHOS_MECHSCOPE_TARGET"
    return 0
  fi

  if [ -f /var/lib/mechos/installed ]; then
    log "ERROR: source-owned runtime missing on installed system; refusing legacy automatic fallback"
    return 1
  fi

  # Live/development media may still use the historical runtime while the ISO
  # build chain migrates to V33.
  if [ -f "$LEGACY_RUNTIME" ] && [ -f "$LEGACY_OWNER" ]; then
    printf '%s\n' "$LEGACY_RUNTIME"
  elif [ -f "$LEGACY_REAL" ]; then
    printf '%s\n' "$LEGACY_REAL"
  else
    return 1
  fi
}

target="$(resolve_target)" || {
  log 'ERROR: no safe MechScope target could be resolved'
  exit 127
}
[ -f "$target" ] || { log "ERROR: resolved target is missing: $target"; exit 127; }

if is_python_target "$target"; then
  if ! python_source_check "$target" >>"$LOG" 2>&1; then
    log "ERROR: Python source validation failed target=$target"
    exit 126
  fi
  log "launch target=$target interpreter=/usr/bin/python3 args=$*"
  exec /usr/bin/python3 "$target" "$@"
fi

[ -x "$target" ] || { log "ERROR: non-Python target is not executable: $target"; exit 126; }
log "launch target=$target interpreter=direct args=$*"
exec "$target" "$@"
