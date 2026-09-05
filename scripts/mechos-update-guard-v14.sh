#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_GUARD_V14

LOG=/var/log/mechos-update-guard.log
mkdir -p /var/log /usr/local/bin /usr/local/libexec
exec >>"$LOG" 2>&1
log(){ printf '[%s] [update-guard-v14] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }

[ "$(id -u)" -eq 0 ] || { echo 'update guard must run as root' >&2; exit 77; }

install_shell_if_bad(){
  local target="$1" rescue="$2" label="$3"
  local bad=0
  [ -x "$target" ] || bad=1
  if [ "$bad" -eq 0 ] && ! bash -n "$target" >/dev/null 2>&1; then bad=1; fi
  if [ "$bad" -eq 1 ]; then
    [ -f "$rescue" ] || { log "ERROR: $label rescue missing: $rescue"; return 1; }
    install -m0755 "$rescue" "$target"
    bash -n "$target"
    log "restored $label from protected rescue copy"
  fi
}

install_python_if_bad(){
  local target="$1" rescue="$2" label="$3"
  local bad=0
  [ -f "$target" ] || bad=1
  if [ "$bad" -eq 0 ] && ! python3 - "$target" >/dev/null 2>&1 <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
  then bad=1; fi
  if [ "$bad" -eq 1 ]; then
    [ -f "$rescue" ] || { log "ERROR: $label rescue missing: $rescue"; return 1; }
    install -m0755 "$rescue" "$target"
    python3 - "$target" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
    log "restored $label from protected rescue copy"
  fi
}

install_shell_if_bad /usr/local/bin/mechos-update-helper /usr/local/libexec/mechos-update-helper-v14 'Update Helper'
install_shell_if_bad /usr/local/bin/mechos-reboot /usr/local/libexec/mechos-reboot-v14 'Reboot Helper'
install_shell_if_bad /usr/local/bin/mechos-update-center /usr/local/libexec/mechos-update-center-launcher-v14 'Update Center launcher'
install_python_if_bad /usr/local/libexec/mechos-update-center-v8.py /usr/local/libexec/mechos-update-center-v8-rescue.py 'Update Center backend'

# Keep a stable, human-readable result for diagnostics.
if timeout 10 /usr/local/bin/mechos-update-helper status >/tmp/mechos-update-guard-status.$$ 2>&1; then
  grep -q '^CURRENT_MECHOS_VERSION=' /tmp/mechos-update-guard-status.$$
  grep -q '^REBOOT_REQUIRED=' /tmp/mechos-update-guard-status.$$
  log 'updater self-check passed'
else
  log 'ERROR: updater status self-check failed'
  cat /tmp/mechos-update-guard-status.$$ 2>/dev/null || true
  rm -f /tmp/mechos-update-guard-status.$$
  exit 1
fi
rm -f /tmp/mechos-update-guard-status.$$
