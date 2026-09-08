#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MECHSCOPE_SESSION_V20
# MECHOS_MECHSCOPE_SESSION_V21
# MECHOS_MECHSCOPE_SESSION_V22_SINGLE_OWNER
# Hardware-first MechScope session. Gaming Mode remains authoritative until the
# user actually changes session-mode. V22 also makes the hardware session the
# single MechScope owner so KDE/manual fallback paths cannot race it.

MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/session-mode"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG_FILE="$STATE_DIR/mechscope-session-v21.log"
CRASH_MARKER="$STATE_DIR/mechscope-crash-loop-v30"
LOCK_FILE="$STATE_DIR/mechscope-owner-v32.lock"
PUBLIC_MECHSCOPE=/usr/local/bin/mechscope
PERSISTENT_RUNTIME=/usr/local/libexec/mechos-mechscope-runtime-v23
PRESERVED_OWNER=/usr/local/libexec/mechscope-owner-v23.py
RAW_MECHSCOPE=/usr/local/bin/mechscope.real
MECHSCOPE_TARGET=''
declare -a MECHSCOPE_COMMAND=()
mkdir -p "$(dirname "$MODE_FILE")" "$STATE_DIR"

log(){ printf '[%s] [mechscope-session-v21] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG_FILE"; }
mode(){
  if [[ -r "$MODE_FILE" ]]; then tr -d '\r\n[:space:]' <"$MODE_FILE"; else printf 'gaming'; fi
}
gaming_requested(){ [[ "$(mode)" == gaming ]]; }

is_python_target(){
  local target="$1" first
  first="$(head -n1 "$target" 2>/dev/null || true)"
  case "$first" in *python*) return 0 ;; esac
  grep -Eq '^[[:space:]]*(from|import)[[:space:]]+[A-Za-z0-9_\.]+' "$target" 2>/dev/null
}

python_source_check(){
  local target="$1"
  /usr/bin/python3 - "$target" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
source = p.read_text(encoding='utf-8')
compile(source, str(p), 'exec')
PY
}

actual_mechscope(){
  if [[ -f "$PERSISTENT_RUNTIME" && -f "$PRESERVED_OWNER" ]]; then
    printf '%s\n' "$PERSISTENT_RUNTIME"
  elif [[ -f "$PUBLIC_MECHSCOPE" ]]; then
    printf '%s\n' "$PUBLIC_MECHSCOPE"
  elif [[ -f "$RAW_MECHSCOPE" ]]; then
    printf '%s\n' "$RAW_MECHSCOPE"
  else
    return 1
  fi
}

resolve_mechscope_command(){
  local target
  target="$(actual_mechscope)" || { log 'MechScope target missing'; return 1; }
  MECHSCOPE_TARGET="$target"
  if is_python_target "$target"; then
    if ! python_source_check "$target" >>"$LOG_FILE" 2>&1; then
      log "Python source validation failed target=$target"
      return 1
    fi
    MECHSCOPE_COMMAND=(/usr/bin/python3 "$target")
  else
    [[ -x "$target" ]] || { log "MechScope target is not executable target=$target"; return 1; }
    MECHSCOPE_COMMAND=("$target")
  fi
  log "resolved MechScope target=$MECHSCOPE_TARGET interpreter=${MECHSCOPE_COMMAND[0]}"
}

safe_desktop_fallback(){
  local reason="$1"
  printf 'desktop\n' >"$MODE_FILE"
  printf '%s\n' "$reason" >"$CRASH_MARKER"
  log "SAFE FALLBACK: $reason; session-mode changed to desktop to stop restart loop"
  if command -v kdialog >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    kdialog --title 'MechScope Recovery' --error \
      'MechScope crashed repeatedly. MechOS stopped the restart loop and switched this session to Desktop Mode. The crash details are saved in ~/.local/state/mechos/mechscope-session-v21.log.' \
      >/dev/null 2>&1 || true
  fi
}

MODE="$(mode)"
if [[ "$MODE" == desktop ]]; then
  log 'desktop mode requested; starting Plasma'
  exec /usr/bin/startplasma-wayland
fi

if ! resolve_mechscope_command; then
  log 'MechScope could not be resolved; falling back to Plasma'
  printf 'desktop\n' >"$MODE_FILE"
  exec /usr/bin/startplasma-wayland
fi

import_user_environment(){
  systemctl --user import-environment \
    DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
    XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION \
    MECHOS_SESSION_SUPERVISED \
    >/dev/null 2>&1 || true
}

run_locked_mechscope(){
  /usr/bin/flock -n "$LOCK_FILE" "${MECHSCOPE_COMMAND[@]}"
}

plasma_mechscope_supervisor(){
  local crashes=0 rc=0
  sleep 2
  while gaming_requested; do
    import_user_environment
    log "Plasma fallback: starting single-owner MechScope attempt=$((crashes+1)) target=$MECHSCOPE_TARGET"
    set +e
    run_locked_mechscope >>"$LOG_FILE" 2>&1
    rc=$?
    set -e

    if ! gaming_requested; then
      log "MechScope exited rc=$rc after intentional mode transition mode=$(mode)"
      return 0
    fi

    crashes=$((crashes+1))
    log "MechScope exited rc=$rc while Gaming Mode remains active; restart=$crashes"
    if (( crashes >= 3 )); then
      safe_desktop_fallback "MechScope target $MECHSCOPE_TARGET exited three consecutive times (last rc=$rc)"
      return 0
    fi
    sleep "$crashes"
  done
  log "Plasma fallback supervisor stopping mode=$(mode)"
}

start_plasma_mechscope(){
  export MECHOS_DISABLE_GAMESCOPE=1
  export MECHOS_SESSION_SUPERVISED=1
  export XDG_SESSION_TYPE=wayland
  export XDG_CURRENT_DESKTOP=KDE
  export XDG_SESSION_DESKTOP=KDE
  export DESKTOP_SESSION=plasma
  log 'starting MechScope inside supervised Plasma fallback'
  plasma_mechscope_supervisor &
  exec /usr/bin/startplasma-wayland
}

VIRT="$(systemd-detect-virt 2>/dev/null || true)"
if [[ -n "$VIRT" && "$VIRT" != none ]]; then
  export MECHOS_VM_MODE=1
  export QT_OPENGL=software
  export LIBGL_ALWAYS_SOFTWARE=1
  export QT_QUICK_BACKEND=software
  export QSG_RHI_BACKEND=software
  log "virtualization=$VIRT; bypassing Gamescope"
  start_plasma_mechscope
fi

if [[ ! -x /usr/bin/gamescope ]]; then
  log 'Gamescope missing on hardware; using Plasma fallback'
  start_plasma_mechscope
fi

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=gamescope
export XDG_SESSION_DESKTOP=MechScope
export DESKTOP_SESSION=mechscope
export MECHOS_SESSION_SUPERVISED=1
export STEAM_ALLOW_DRIVE_UNMOUNT=1
export STEAM_GAMESCOPE_TEARING_SUPPORTED=1
export STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT=1
export STEAM_GAMESCOPE_COLOR_MANAGED=1
export STEAM_MULTIPLE_XWAYLANDS=1
export STEAM_DISABLE_AUDIO_DEVICE_SWITCHING=1
export STEAM_UPDATEUI_PNG_BACKGROUND=/usr/share/backgrounds/mechos/mechscope-loading.png

if [[ "${MECHOS_ENABLE_VRR:-0}" == 1 ]]; then
  export STEAM_GAMESCOPE_VRR_SUPPORTED=1
fi
if [[ "${MECHOS_HDR:-0}" == 1 ]]; then
  export STEAM_GAMESCOPE_HDR_SUPPORTED=1
  export STEAM_GAMESCOPE_VIRTUAL_WHITE=1
fi
if lspci 2>/dev/null | grep -qi nvidia; then
  export GBM_BACKEND=nvidia-drm
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi

run_gamescope(){
  local label="$1"; shift
  local rc=0
  log "starting single-owner Gamescope attempt=$label args=$* target=$MECHSCOPE_TARGET interpreter=${MECHSCOPE_COMMAND[0]}"
  set +e
  /usr/bin/gamescope "$@" -- /usr/bin/flock -n "$LOCK_FILE" "${MECHSCOPE_COMMAND[@]}" >>"$LOG_FILE" 2>&1
  rc=$?
  set -e

  if ! gaming_requested; then
    log "Gamescope attempt=$label exited rc=$rc after intentional mode transition mode=$(mode)"
    return 0
  fi

  log "Gamescope attempt=$label exited rc=$rc while Gaming Mode remains active; treating as recoverable failure"
  return 90
}

ARGS=(-e -f)
[[ "${MECHOS_ENABLE_VRR:-0}" == 1 ]] && ARGS+=(--adaptive-sync)
[[ "${MECHOS_HDR:-0}" == 1 ]] && ARGS+=(--hdr-enabled)

if run_gamescope primary "${ARGS[@]}"; then
  exit 0
fi
if gaming_requested; then
  if run_gamescope conservative -f; then
    exit 0
  fi
fi
if gaming_requested; then
  log 'Gamescope ended while Gaming Mode remained active; switching to supervised Plasma fallback'
  start_plasma_mechscope
fi

log "Gaming session completed after mode transition mode=$(mode)"
exit 0
