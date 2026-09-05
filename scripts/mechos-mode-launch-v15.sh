#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MODE_LAUNCH_V15
# Creator Mode is launched and health-checked before MechScope is ever touched.
# In a VM, Creator inherits the same software-rendering environment as the VM
# runtime, but MechScope remains alive underneath it for safe back navigation.

MODE="${1:-}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
MODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mechos"
LOG="$STATE_DIR/mode-shortcut-v15.log"
CREATOR_LOG="$STATE_DIR/creator-mode-launch-v15.log"
BASE=/usr/local/libexec/mechos-mode-launch-base-v15
CREATOR=/usr/local/bin/mechos-creator-mode
mkdir -p "$STATE_DIR" "$MODE_DIR"

log(){ printf '[%s] [mode-launch-v15] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }
notify_error(){
  local msg="$1"
  log "ERROR: $msg"
  if command -v kdialog >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    kdialog --title 'MechOS Creator Mode' --error "$msg\n\nLogs:\n$LOG\n$CREATOR_LOG" >/dev/null 2>&1 || true
  fi
}

case "$MODE" in
  gaming|mechscope|creator|desktop) ;;
  *) echo 'Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}' >&2; exit 2 ;;
esac

# Preserve the proven Hotfix 10 launcher for every transition except Creator.
# This keeps physical Gaming/Desktop behavior and existing VM routing unchanged.
if [ "$MODE" != creator ]; then
  [ -x "$BASE" ] || { notify_error "Base mode launcher is missing: $BASE"; exit 1; }
  exec "$BASE" "$@"
fi

# MECHOS_CREATOR_HANDOFF_V15
import_graphics(){
  # Button/shortcut launches may have a reduced environment. Merge the active
  # Plasma session into this process, then publish it to the user manager so a
  # systemd user service can open a window in the current session.
  if systemctl --user show-environment >/dev/null 2>&1; then
    while IFS='=' read -r key value; do
      case "$key" in
        DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|KDE_FULL_SESSION|KDE_SESSION_VERSION)
          if [ -z "${!key:-}" ] && [ -n "$value" ]; then
            printf -v "$key" '%s' "$value"
            export "$key"
          fi
          ;;
      esac
    done < <(systemctl --user show-environment)
  fi
  systemctl --user import-environment \
    DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
    XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION KDE_SESSION_VERSION \
    >/dev/null 2>&1 || true
}

creator_running(){
  pgrep -u "$(id -u)" -f '/usr/local/bin/mechos-creator-mode(\.real)?([[:space:]]|$)' >/dev/null 2>&1
}

creator_stable(){
  # Require Creator to remain present for a short settling period. A service
  # that starts and immediately crashes must not be treated as a valid handoff.
  local i
  for i in $(seq 1 20); do
    creator_running || return 1
    sleep 0.1
  done
  return 0
}

start_creator_unit(){
  local unit="$1"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  if ! systemctl --user start "$unit" >>"$CREATOR_LOG" 2>&1; then
    return 1
  fi
  local i
  for i in $(seq 1 30); do
    creator_running && return 0
    if systemctl --user is-failed --quiet "$unit"; then return 1; fi
    sleep 0.1
  done
  return 1
}

import_graphics
[ -x "$CREATOR" ] || { notify_error 'Creator Mode is missing.'; exit 1; }

if creator_running; then
  log 'Creator Mode is already running; MechScope left untouched'
  exit 0
fi

virt="$(systemd-detect-virt 2>/dev/null || true)"
live=0
if [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; then live=1; fi
unit=mechos-creator-mode.service

if [ -n "$virt" ] && [ "$virt" != none ] && [ "$live" -eq 0 ]; then
  # MECHOS_CREATOR_VM_OVERLAY_V15
  # Match the VM runtime's rendering policy without routing through
  # `mechos-vm-mode-runtime creator`, because that path deliberately stops the
  # MechScope service. Creator is an overlay; MechScope stays alive below it.
  export MECHOS_VM_MODE=1
  export MECHOS_DISABLE_GAMESCOPE=1
  export QT_OPENGL=software
  export LIBGL_ALWAYS_SOFTWARE=1
  export QT_QUICK_BACKEND=software
  export QSG_RHI_BACKEND=software
  systemctl --user import-environment \
    MECHOS_VM_MODE MECHOS_DISABLE_GAMESCOPE QT_OPENGL LIBGL_ALWAYS_SOFTWARE \
    QT_QUICK_BACKEND QSG_RHI_BACKEND >/dev/null 2>&1 || true
  unit=mechos-vm-creator.service
fi

: >"$CREATOR_LOG"
log "Creator handoff requested virtualization=${virt:-none} unit=$unit; MechScope will not be stopped"

if ! start_creator_unit "$unit"; then
  log "$unit did not produce a Creator process; trying an isolated transient user service"
  systemd-run --user --quiet --collect --unit="mechos-creator-overlay-v15-$$" \
    "$CREATOR" >>"$CREATOR_LOG" 2>&1 || true
  for _ in $(seq 1 30); do
    creator_running && break
    sleep 0.1
  done
fi

if ! creator_running || ! creator_stable; then
  {
    echo '--- Creator Mode user service status ---'
    systemctl --user status "$unit" --no-pager 2>&1 || true
    echo '--- end status ---'
  } >>"$CREATOR_LOG"
  notify_error 'Creator Mode could not start. MechScope was kept running so you can continue using Gaming Mode.'
  exit 1
fi

if [ -n "$virt" ] && [ "$virt" != none ] && [ "$live" -eq 0 ]; then
  printf 'creator\n' >"$MODE_DIR/session-mode"
fi
log 'Creator Mode healthy; MechScope preserved underneath for Escape/back navigation'
exit 0
