#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MECHSCOPE_SAFE_LAUNCH_V31

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/mechscope-safe-launch-v31.log"
mkdir -p "$STATE_DIR"
log(){ printf '[%s] [mechscope-safe-launch-v31] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }

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

  # Prefer the source-owned persistent runtime when its generated owner exists.
  # Otherwise fall back to the preserved tutorial target. Never fall back to
  # /usr/local/bin/mechscope here because that public wrapper calls this helper.
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
