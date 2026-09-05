#!/usr/bin/env bash
set -Eeuo pipefail

# MECHOS_VM_MECHSCOPE_PYTHON_EXEC_V2
MODE="${1:-boot}"
STATE=/var/lib/mechos
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
MODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mechos"
MODE_FILE="$MODE_DIR/session-mode"
LOG="$STATE_DIR/vm-mode-runtime.log"
APP_LOG="$STATE_DIR/vm-mechscope-launch.log"
mkdir -p "$STATE_DIR" "$MODE_DIR"

log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -z "$virt" ] || [ "$virt" = none ]; then
  log "not a VM; declining VM runtime mode=$MODE"
  exit 3
fi
if [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; then
  log "Live ISO detected; installed VM runtime disabled"
  exit 0
fi

# Account creation remains authoritative. Do not let a VM launcher bypass OOBE.
if [ -e "$STATE/installed" ] && [ ! -e "$STATE/oobe-complete" ]; then
  if [ "$(id -un)" = mechos-setup ] && [ -x /usr/local/bin/mechos-oobe-start ]; then
    log "OOBE incomplete; routing setup account to account creation"
    exec /usr/local/bin/mechos-oobe-start
  fi
  log "OOBE incomplete for user=$(id -un); MechScope launch blocked"
  if command -v kdialog >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    kdialog --title 'MechOS First Setup' --error 'Account creation is still pending. Restart MechOS to enter the protected setup session.' >/dev/null 2>&1 || true
  fi
  exit 20
fi

export MECHOS_VM_MODE=1
export MECHOS_DISABLE_GAMESCOPE=1
export QT_OPENGL=software
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export QSG_RHI_BACKEND=software

import_graphics(){
  if systemctl --user show-environment >/dev/null 2>&1; then
    while IFS='=' read -r key value; do
      case "$key" in
        DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|KDE_FULL_SESSION|KDE_SESSION_VERSION)
          printf -v "$key" '%s' "$value"; export "$key" ;;
      esac
    done < <(systemctl --user show-environment)
    systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
      XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION KDE_SESSION_VERSION \
      MECHOS_VM_MODE MECHOS_DISABLE_GAMESCOPE QT_OPENGL LIBGL_ALWAYS_SOFTWARE \
      QT_QUICK_BACKEND QSG_RHI_BACKEND >/dev/null 2>&1 || true
  fi
}

wait_for_graphics(){
  local i
  for i in $(seq 1 80); do
    import_graphics
    if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then return 0; fi
    sleep 0.25
  done
  log "graphical environment never became ready"
  return 1
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
  case "$first" in
    *python*) return 0 ;;
  esac
  # Older installed payloads can contain raw Python at mechscope.real without a
  # shebang. Detect that source instead of asking /bin/sh to interpret it.
  grep -Eq '^[[:space:]]*(from|import)[[:space:]]+[A-Za-z0-9_\.]+' "$target" 2>/dev/null
}

python_health_check(){
  local target="$1"
  if is_python_target "$target"; then
    PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m py_compile "$target" >>"$APP_LOG" 2>&1 || {
      log "MechScope Python health check failed target=$target"
      return 1
    }
  fi
}

mechscope_running(){
  pgrep -u "$(id -u)" -f '/usr/local/bin/mechscope(\.real)?([[:space:]]|$)' >/dev/null 2>&1
}

launch_mechscope(){
  local target pid i
  local -a command
  target="$(actual_mechscope)" || { log "MechScope executable missing"; return 1; }
  python_health_check "$target" || return 1

  systemctl --user stop mechos-vm-mechscope.service >/dev/null 2>&1 || true

  if mechscope_running; then
    log "MechScope already running"
    return 0
  fi

  : >"$APP_LOG"
  if is_python_target "$target"; then
    command=(/usr/bin/python3 "$target")
    log "launching Python MechScope in Plasma VM session target=$target virt=$virt"
  else
    [ -x "$target" ] || { log "MechScope target is not executable target=$target"; return 1; }
    command=("$target")
    log "launching executable MechScope in Plasma VM session target=$target virt=$virt"
  fi

  nohup "${command[@]}" >>"$APP_LOG" 2>&1 </dev/null &
  pid=$!
  for i in $(seq 1 30); do
    sleep 0.1
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      wait "$pid" >/dev/null 2>&1 || true
      log "MechScope exited during startup; see $APP_LOG"
      return 1
    fi
    if [ "$i" -ge 10 ]; then
      printf '%s\n' "$pid" > "$STATE_DIR/mechscope.pid"
      log "MechScope launch healthy pid=$pid command=${command[*]}"
      return 0
    fi
  done
  return 0
}

launch_creator(){
  [ -x /usr/local/bin/mechos-creator-mode ] || return 1
  nohup /usr/local/bin/mechos-creator-mode >>"$STATE_DIR/vm-creator-launch.log" 2>&1 </dev/null &
  local pid=$!
  sleep 1
  kill -0 "$pid" >/dev/null 2>&1
}

wait_for_graphics || exit 4

case "$MODE" in
  boot)
    MODE=gaming
    if [ -r "$MODE_FILE" ]; then MODE="$(tr -d '[:space:]' < "$MODE_FILE")"; fi
    case "$MODE" in gaming|creator|desktop) ;; *) MODE=gaming ;; esac
    ;;
  start|mechscope) MODE=gaming ;;
  gaming|creator|desktop|stop) ;;
  *) log "invalid mode=$MODE"; exit 2 ;;
esac

case "$MODE" in
  gaming)
    printf 'gaming\n' > "$MODE_FILE"
    launch_mechscope
    ;;
  creator)
    printf 'creator\n' > "$MODE_FILE"
    pkill -u "$(id -u)" -f '/usr/local/bin/mechscope(\.real)?([[:space:]]|$)' >/dev/null 2>&1 || true
    launch_creator
    ;;
  desktop)
    printf 'desktop\n' > "$MODE_FILE"
    systemctl --user stop mechos-vm-mechscope.service mechos-vm-creator.service >/dev/null 2>&1 || true
    pkill -u "$(id -u)" -f '/usr/local/bin/mechscope(\.real)?([[:space:]]|$)' >/dev/null 2>&1 || true
    ;;
  stop)
    systemctl --user stop mechos-vm-mechscope.service mechos-vm-creator.service >/dev/null 2>&1 || true
    ;;
esac
