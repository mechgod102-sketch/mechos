#!/usr/bin/env bash
set -Eeuo pipefail
MODE="${1:-}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/mode-shortcut.log"
mkdir -p "$STATE_DIR"
log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }
notify_error(){
  local msg="$1"; log "ERROR: $msg"
  if command -v kdialog >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    kdialog --title 'MechOS Mode Launcher' --error "$msg\n\nLog: $LOG" >/dev/null 2>&1 || true
  fi
}
case "$MODE" in gaming|mechscope|creator|desktop) ;; *) echo 'Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}' >&2; exit 2 ;; esac

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -n "$virt" ] && [ "$virt" != none ] && [ ! -e /run/archiso/bootmnt ] && ! grep -q archiso /proc/cmdline 2>/dev/null; then
  # MECHOS_HOTFIX5_VM_DIRECT_ROUTER_V1
  # Bypass the historical gaming-layer controller in VMs. Older upgraded
  # installs can have a controller that never received the VM router, causing
  # the persistent 'MechScope could not be started' dialog after Hotfix 4.
  case "$MODE" in mechscope) MODE=gaming ;; esac
  log "virtualization=$virt; routing mode=$MODE directly to VM runtime"
  if /usr/local/bin/mechos-vm-mode-runtime "$MODE" >>"$LOG" 2>&1; then
    log "VM mode=$MODE launch accepted"
    exit 0
  fi
  notify_error "${MODE^} could not be started in the virtual machine."
  exit 1
fi

CONTROL=/usr/local/bin/mechos-gaming-layer-control
[ -x "$CONTROL" ] || { notify_error 'MechOS mode controller is missing.'; exit 1; }
case "$MODE" in
  gaming|mechscope) "$CONTROL" start >>"$LOG" 2>&1 ;;
  creator) "$CONTROL" creator >>"$LOG" 2>&1 ;;
  desktop) "$CONTROL" desktop >>"$LOG" 2>&1 ;;
esac || { notify_error "${MODE^} could not be started."; exit 1; }

# Build 127 rebuild trigger: the Build 118 compatibility stage now validates
# MechScope launcher capabilities semantically instead of matching exact text.
