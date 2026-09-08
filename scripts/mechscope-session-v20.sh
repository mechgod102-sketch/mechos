#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MECHSCOPE_SESSION_V20
# Hardware-first MechScope session. Gaming Mode remains authoritative until the
# user actually changes session-mode; a clean child exit while still in gaming
# is treated as an early shell failure instead of a successful SDDM session end.

MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/session-mode"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG_FILE="$STATE_DIR/mechscope-session-v20.log"
MECHSCOPE=/usr/local/bin/mechscope
mkdir -p "$(dirname "$MODE_FILE")" "$STATE_DIR"

log(){ printf '[%s] [mechscope-session-v20] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG_FILE"; }
mode(){
  if [[ -r "$MODE_FILE" ]]; then tr -d '\r\n[:space:]' <"$MODE_FILE"; else printf 'gaming'; fi
}
gaming_requested(){ [[ "$(mode)" == gaming ]]; }

MODE="$(mode)"
if [[ "$MODE" == desktop ]]; then
  log 'desktop mode requested; starting Plasma'
  exec /usr/bin/startplasma-wayland
fi

if [[ ! -x "$MECHSCOPE" ]]; then
  log 'MechScope executable missing; falling back to Plasma'
  exec /usr/bin/startplasma-wayland
fi

import_user_environment(){
  systemctl --user import-environment \
    DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
    XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION \
    >/dev/null 2>&1 || true
}

plasma_mechscope_supervisor(){
  local crashes=0 rc=0
  sleep 2
  while gaming_requested; do
    import_user_environment
    log "Plasma fallback: starting supervised MechScope attempt=$((crashes+1))"
    set +e
    "$MECHSCOPE" >>"$LOG_FILE" 2>&1
    rc=$?
    set -e

    if ! gaming_requested; then
      log "MechScope exited rc=$rc after intentional mode transition mode=$(mode)"
      return 0
    fi

    crashes=$((crashes+1))
    log "MechScope exited rc=$rc while Gaming Mode remains active; restart=$crashes"
    sleep $(( crashes < 5 ? crashes : 5 ))
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
  log "starting Gamescope attempt=$label args=$*"
  set +e
  /usr/bin/gamescope "$@" -- "$MECHSCOPE" >>"$LOG_FILE" 2>&1
  rc=$?
  set -e

  if ! gaming_requested; then
    log "Gamescope attempt=$label exited rc=$rc after intentional mode transition mode=$(mode)"
    return 0
  fi

  # rc=0 is NOT success if the user never left Gaming Mode. It means the
  # compositor/MechScope child disappeared and SDDM would otherwise tear down
  # the whole gaming session.
  log "Gamescope attempt=$label exited rc=$rc while Gaming Mode remains active; treating as recoverable failure"
  return 90
}

ARGS=(-e -f)
[[ "${MECHOS_ENABLE_VRR:-0}" == 1 ]] && ARGS+=(--adaptive-sync)
[[ "${MECHOS_HDR:-0}" == 1 ]] && ARGS+=(--hdr-enabled)

if run_gamescope primary "${ARGS[@]}"; then
  exit 0
fi

# Only retry if Gaming Mode is still requested; otherwise the first attempt
# already completed a legitimate mode switch.
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
