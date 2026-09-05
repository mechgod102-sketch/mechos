#!/usr/bin/env bash
set -Eeuo pipefail

# MECHOS_HOTFIX10_PHYSICAL_MECHSCOPE_FALLBACK_V1
# MECHOS_HOTFIX11_VM_FAILURE_LOGS_V1
MODE="${1:-}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/mode-shortcut.log"
APP_LOG="$STATE_DIR/mechscope-launch.log"
VM_LOG="$STATE_DIR/vm-mode-runtime.log"
VM_APP_LOG="$STATE_DIR/vm-mechscope-launch.log"
mkdir -p "$STATE_DIR"

log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }
notify_error(){
  local msg="$1"
  log "ERROR: $msg"
  if command -v kdialog >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    kdialog --title 'MechOS Mode Launcher' --error "$msg\n\nLogs:\n$LOG\n$APP_LOG" >/dev/null 2>&1 || true
  fi
}
notify_vm_error(){
  local msg="$1"
  log "ERROR: $msg"
  if command -v kdialog >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    kdialog --title 'MechOS Mode Launcher' --error "$msg\n\nVM logs:\n$LOG\n$VM_LOG\n$VM_APP_LOG" >/dev/null 2>&1 || true
  fi
}

case "$MODE" in
  gaming|mechscope|creator|desktop) ;;
  *) echo 'Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}' >&2; exit 2 ;;
esac

REQUESTED_MODE="$MODE"

import_graphics(){
  # Shortcut launches can arrive with a reduced environment. Merge the active
  # Plasma session into this process without replacing valid current values.
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

actual_mechscope(){
  if [ -f /usr/local/bin/mechscope.real ]; then
    printf '%s\n' /usr/local/bin/mechscope.real
  elif [ -f /usr/local/bin/mechscope ]; then
    printf '%s\n' /usr/local/bin/mechscope
  else
    return 1
  fi
}

is_python_target(){
  local target="$1" first
  first="$(head -n1 "$target" 2>/dev/null || true)"
  case "$first" in *python*) return 0 ;; esac
  grep -Eq '^[[:space:]]*(from|import)[[:space:]]+[A-Za-z0-9_\.]+' "$target" 2>/dev/null
}

mechscope_running(){
  pgrep -u "$(id -u)" -f '/usr/local/bin/mechscope(\.real)?([[:space:]]|$)' >/dev/null 2>&1
}

wait_for_mechscope(){
  local i
  for i in $(seq 1 50); do
    mechscope_running && return 0
    sleep 0.1
  done
  return 1
}

launch_mechscope_direct(){
  local target pid
  local -a command
  target="$(actual_mechscope)" || { log 'direct fallback: MechScope target missing'; return 1; }

  if is_python_target "$target"; then
    if ! PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m py_compile "$target" >>"$APP_LOG" 2>&1; then
      log "direct fallback: Python health check failed target=$target"
      return 1
    fi
    command=(/usr/bin/python3 "$target")
  else
    [ -x "$target" ] || { log "direct fallback: target is not executable target=$target"; return 1; }
    command=("$target")
  fi

  import_graphics
  log "direct fallback: launching MechScope target=$target session=${XDG_SESSION_TYPE:-unknown} wayland=${WAYLAND_DISPLAY:-none} display=${DISPLAY:-none}"
  : >"$APP_LOG"
  nohup "${command[@]}" >>"$APP_LOG" 2>&1 </dev/null &
  pid=$!

  for _ in $(seq 1 25); do
    sleep 0.1
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      wait "$pid" >/dev/null 2>&1 || true
      log "direct fallback: MechScope exited during startup pid=$pid"
      if [ -s "$APP_LOG" ]; then
        { echo '--- MechScope startup tail ---'; tail -n 20 "$APP_LOG"; echo '--- end startup tail ---'; } >>"$LOG"
      fi
      return 1
    fi
  done
  printf '%s\n' "$pid" >"$STATE_DIR/mechscope.pid"
  log "direct fallback: MechScope launch healthy pid=$pid command=${command[*]}"
  return 0
}

import_graphics
virt="$(systemd-detect-virt 2>/dev/null || true)"
live=0
if [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; then live=1; fi
log "request mode=$REQUESTED_MODE virtualization=${virt:-none} live=$live session=${XDG_SESSION_TYPE:-unknown} wayland=${WAYLAND_DISPLAY:-none} display=${DISPLAY:-none}"

# Installed VMs use the dedicated software-rendered runtime. Keep this path
# separate so the physical fallback below never forces software rendering on
# real hardware.
if [ -n "$virt" ] && [ "$virt" != none ] && [ "$live" -eq 0 ]; then
  runtime=/usr/local/bin/mechos-vm-mode-runtime
  [ -x "$runtime" ] || { notify_vm_error 'MechOS VM mode runtime is missing.'; exit 1; }
  log "virtualization=$virt; routing mode=$REQUESTED_MODE to VM runtime"
  if "$runtime" "$REQUESTED_MODE" >>"$LOG" 2>&1; then
    log "VM mode=$REQUESTED_MODE launch accepted"
    exit 0
  else
    rc=$?
    notify_vm_error "$REQUESTED_MODE could not be started in the virtual machine (runtime rc=$rc)."
    exit "$rc"
  fi
fi

CONTROL=/usr/local/bin/mechos-gaming-layer-control

case "$REQUESTED_MODE" in
  gaming|mechscope)
    # First preserve the normal accelerated gaming-layer path. If the
    # controller is missing, returns an error, or claims success without a
    # MechScope process appearing, fall back to the real MechScope target in
    # the current Plasma session with hardware acceleration left untouched.
    controller_rc=127
    if [ -x "$CONTROL" ]; then
      log "physical/non-virtual session; requesting accelerated controller start"
      if "$CONTROL" start >>"$LOG" 2>&1; then
        controller_rc=0
      else
        controller_rc=$?
        log "controller start failed rc=$controller_rc"
      fi
      if wait_for_mechscope; then
        log "MechScope visible after controller start"
        exit 0
      fi
      log "controller produced no MechScope process within 5 seconds; activating direct fallback"
    else
      log "mode controller missing; activating direct MechScope fallback"
    fi

    if launch_mechscope_direct; then
      log "MechScope direct fallback accepted after controller rc=$controller_rc"
      exit 0
    fi
    notify_error "MechScope could not be started. Controller rc=$controller_rc and the direct fallback also failed."
    exit 1
    ;;

  creator)
    [ -x "$CONTROL" ] || { notify_error 'MechOS mode controller is missing.'; exit 1; }
    if "$CONTROL" creator >>"$LOG" 2>&1; then
      log 'Creator Mode launch request accepted'
      exit 0
    else
      rc=$?
      notify_error "Creator Mode could not be started (rc=$rc)."
      exit "$rc"
    fi
    ;;

  desktop)
    [ -x "$CONTROL" ] || { notify_error 'MechOS mode controller is missing.'; exit 1; }
    if "$CONTROL" desktop >>"$LOG" 2>&1; then
      log 'Desktop Mode launch request accepted'
      exit 0
    else
      rc=$?
      notify_error "Desktop Mode could not be started (rc=$rc)."
      exit "$rc"
    fi
    ;;
esac
