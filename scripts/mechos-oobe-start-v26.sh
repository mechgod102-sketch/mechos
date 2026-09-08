#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_OOBE_START_V26

STATE=/var/lib/mechos
OOBE=/usr/local/bin/mechos-oobe
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/oobe-start.log"
mkdir -p "$(dirname "$LOG")"

log(){ printf '[%s] [oobe-v26] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }
visible_error(){
  local msg="$1"
  log "ERROR: $msg"
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --error "$msg\n\nLog: $LOG" --title 'MechOS First System Setup' >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical 'MechOS First System Setup' "$msg — log: $LOG" >/dev/null 2>&1 || true
  fi
}

[ -e "$STATE/installed" ] || exit 0
if [ -e "$STATE/oobe-complete" ]; then
  visible_error 'First System Setup is already complete.'
  exit 0
fi
if [ "$(id -un)" != mechos-setup ]; then
  visible_error 'First System Setup must run from the temporary MechOS setup session.'
  exit 3
fi
if [ ! -x "$OOBE" ]; then
  visible_error 'The First System Setup application is missing.'
  exit 4
fi

# If the launcher is called from systemd --user or an application shortcut,
# recover the graphical environment KDE exported to the user manager.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
restore_graphics_env(){
  local line key value
  while IFS= read -r line; do
    case "$line" in
      DISPLAY=*|WAYLAND_DISPLAY=*|DBUS_SESSION_BUS_ADDRESS=*|XDG_SESSION_TYPE=*|XDG_CURRENT_DESKTOP=*|KDE_FULL_SESSION=*)
        key="${line%%=*}"; value="${line#*=}"; export "$key=$value" ;;
    esac
  done < <(systemctl --user show-environment 2>/dev/null || true)
}

wait_for_graphics(){
  local i
  for i in $(seq 1 80); do
    restore_graphics_env
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
      return 0
    fi
    if [ -n "${DISPLAY:-}" ]; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

# Avoid spawning duplicates when autostart and a manual click happen together.
if pgrep -u "$(id -u)" -f '(^|[[:space:]])(/usr/bin/python3[[:space:]]+)?/usr/local/bin/mechos-oobe([[:space:]]|$)' >/dev/null 2>&1; then
  log 'OOBE is already running; duplicate launch ignored'
  exit 0
fi

if ! wait_for_graphics; then
  visible_error 'The graphical session is not ready, so First System Setup could not open.'
  exit 5
fi

systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION >/dev/null 2>&1 || true
log "launch request session=${XDG_SESSION_TYPE:-unknown} wayland=${WAYLAND_DISPLAY:-none} display=${DISPLAY:-none} runtime=$XDG_RUNTIME_DIR"

run_candidate(){
  local platform="$1" pid i rc=0
  log "trying Qt platform=$platform"
  env QT_QPA_PLATFORM="$platform" "$OOBE" >>"$LOG" 2>&1 &
  pid=$!
  for i in $(seq 1 12); do
    if kill -0 "$pid" 2>/dev/null; then
      sleep 0.25
      continue
    fi
    wait "$pid" 2>/dev/null || rc=$?
    log "platform=$platform exited during startup rc=$rc"
    return "${rc:-1}"
  done
  log "platform=$platform window process is active pid=$pid"
  wait "$pid"
}

# VMware Plasma normally provides Wayland first. If Qt cannot attach to that
# compositor, retry through X11/XWayland instead of failing silently.
if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
  set +e
  run_candidate wayland
  rc=$?
  set -e
  [ "$rc" -eq 0 ] && exit 0
  log "Wayland launch failed rc=$rc; checking X11 fallback"
fi

restore_graphics_env
if [ -n "${DISPLAY:-}" ]; then
  set +e
  run_candidate xcb
  rc=$?
  set -e
  [ "$rc" -eq 0 ] && exit 0
  visible_error "First System Setup failed to start through both available display paths (last rc=$rc)."
  exit "$rc"
fi

visible_error 'First System Setup could not find a usable Wayland or X11 display.'
exit 6
