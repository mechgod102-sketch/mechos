#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MECHSCOPE_SESSION_V19
# Hardware-first MechScope session with conservative Gamescope flags and a
# Plasma-hosted fallback. VRR/HDR are opt-in so unsupported displays no longer
# prevent the MechScope UI from opening.

MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/session-mode"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG_FILE="$STATE_DIR/mechscope-session-v19.log"
mkdir -p "$(dirname "$MODE_FILE")" "$STATE_DIR"

log(){ printf '[%s] [mechscope-session-v19] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG_FILE"; }

if [[ -r "$MODE_FILE" ]]; then
  MODE="$(tr -d '\r\n' <"$MODE_FILE")"
else
  MODE=gaming
fi

if [[ "$MODE" == desktop ]]; then
  log 'desktop mode requested; starting Plasma'
  exec /usr/bin/startplasma-wayland
fi

MECHSCOPE=/usr/local/bin/mechscope
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

start_plasma_mechscope(){
  export MECHOS_DISABLE_GAMESCOPE=1
  export XDG_SESSION_TYPE=wayland
  export XDG_CURRENT_DESKTOP=KDE
  export XDG_SESSION_DESKTOP=KDE
  export DESKTOP_SESSION=plasma
  log 'starting MechScope inside Plasma fallback'
  (
    sleep 2
    import_user_environment
    "$MECHSCOPE" >>"$LOG_FILE" 2>&1 || log "MechScope direct process exited rc=$?"
  ) &
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
export STEAM_ALLOW_DRIVE_UNMOUNT=1
export STEAM_GAMESCOPE_TEARING_SUPPORTED=1
export STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT=1
export STEAM_GAMESCOPE_COLOR_MANAGED=1
export STEAM_MULTIPLE_XWAYLANDS=1
export STEAM_DISABLE_AUDIO_DEVICE_SWITCHING=1
export STEAM_UPDATEUI_PNG_BACKGROUND=/usr/share/backgrounds/mechos/mechscope-loading.png

# Do not advertise VRR/HDR unless explicitly enabled. Hotfix 18-era sessions
# enabled adaptive sync by default, which can reject unsupported display paths.
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
  log "starting Gamescope attempt=$label args=$*"
  set +e
  /usr/bin/gamescope "$@" -- "$MECHSCOPE" >>"$LOG_FILE" 2>&1
  local rc=$?
  set -e
  log "Gamescope attempt=$label exited rc=$rc"
  return "$rc"
}

# First try the Steam-integrated fullscreen path, but only add display features
# the user explicitly enabled.
ARGS=(-e -f)
[[ "${MECHOS_ENABLE_VRR:-0}" == 1 ]] && ARGS+=(--adaptive-sync)
[[ "${MECHOS_HDR:-0}" == 1 ]] && ARGS+=(--hdr-enabled)
if run_gamescope primary "${ARGS[@]}"; then
  exit 0
fi

# Retry once with the smallest practical argument set. This catches hardware
# where -e, VRR, HDR or a driver-specific feature causes Gamescope startup to
# fail even though basic Gamescope works.
if run_gamescope conservative -f; then
  exit 0
fi

log 'all Gamescope attempts failed; preserving access through Plasma fallback'
start_plasma_mechscope
