#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MECHSCOPE_SESSION_V20
# MECHOS_MECHSCOPE_SESSION_V21
# MECHOS_MECHSCOPE_SESSION_V22_SINGLE_OWNER
# MECHOS_MECHSCOPE_SESSION_V23_SOURCE_RUNTIME
# MECHOS_MECHSCOPE_SESSION_V24_GPU_CAPABILITY
# MECHOS_MECHSCOPE_SESSION_V25_PLASMA_READY_HANDOFF
# MECHOS_INTEL_UMA_INTEGRATION_V36
# MECHOS_LEGACY_GPU_SESSION_V0311

MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/session-mode"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG_FILE="$STATE_DIR/mechscope-session-v23.log"
CRASH_MARKER="$STATE_DIR/mechscope-crash-loop-v33"
LOCK_FILE="$STATE_DIR/mechscope-owner-v32.lock"
SOURCE_RUNTIME=/usr/local/libexec/mechos-mechscope-source-runtime-v33
PUBLIC_MECHSCOPE=/usr/local/bin/mechscope
FALLBACK_REQUEST="$STATE_DIR/plasma-fallback-request-v25"
MECHSCOPE_TARGET=''
declare -a MECHSCOPE_COMMAND=()
mkdir -p "$(dirname "$MODE_FILE")" "$STATE_DIR"

log(){ printf '[%s] [mechscope-session-v23] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG_FILE"; }
mode(){ if [[ -r "$MODE_FILE" ]]; then tr -d '\r\n[:space:]' <"$MODE_FILE"; else printf 'gaming'; fi; }
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
p=Path(sys.argv[1]); compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
}

actual_mechscope(){
  # Installed hardware must use the complete source-owned runtime. Never route
  # automatic Gaming Mode startup back through generated mechscope.real.
  if [[ -f "$SOURCE_RUNTIME" ]]; then
    printf '%s\n' "$SOURCE_RUNTIME"
  elif [[ ! -f /var/lib/mechos/installed && -f "$PUBLIC_MECHSCOPE" ]]; then
    printf '%s\n' "$PUBLIC_MECHSCOPE"
  else
    return 1
  fi
}

resolve_mechscope_command(){
  local target
  target="$(actual_mechscope)" || { log 'source-owned MechScope runtime missing'; return 1; }
  MECHSCOPE_TARGET="$target"
  if is_python_target "$target"; then
    if ! python_source_check "$target" >>"$LOG_FILE" 2>&1; then
      log "Python source validation failed target=$target"; return 1
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
  log "SAFE FALLBACK: $reason; session-mode changed to desktop"
  if command -v kdialog >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    kdialog --title 'MechScope Recovery' --error \
      'MechScope could not remain running. MechOS stopped the restart loop and switched to Desktop Mode. See ~/.local/state/mechos/mechscope-session-v23.log.' \
      >/dev/null 2>&1 || true
  fi
}

MODE="$(mode)"
if [[ "$MODE" == desktop ]]; then
  rm -f "$FALLBACK_REQUEST"
  log 'desktop mode requested; starting Plasma'
  exec /usr/bin/startplasma-wayland
fi
if ! resolve_mechscope_command; then
  log 'source-owned MechScope could not be resolved; falling back to Plasma desktop'
  rm -f "$FALLBACK_REQUEST"
  printf 'desktop\n' >"$MODE_FILE"
  exec /usr/bin/startplasma-wayland
fi

start_plasma_mechscope(){
  export MECHOS_DISABLE_GAMESCOPE=1 MECHOS_SESSION_SUPERVISED=1
  export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE DESKTOP_SESSION=plasma
  printf 'requested=%s\n' "$(date -Is 2>/dev/null || date)" >"$FALLBACK_REQUEST"
  log 'requesting Plasma-ready MechScope fallback; Plasma autostart will own the visible launch'
  exec /usr/bin/startplasma-wayland
}

GPU_BLOCK="$(lspci -nnk 2>/dev/null | grep -A4 -Ei 'VGA|3D|Display' || true)"
GPU_DRIVERS="$(printf '%s\n' "$GPU_BLOCK" | sed -n 's/^[[:space:]]*Kernel driver in use: //p' | sort -u | xargs || true)"
GPU_NAME="$(printf '%s\n' "$GPU_BLOCK" | sed -n '/VGA\|3D\|Display/{s/^[^:]*: //;p;q}' || true)"
log "GPU preflight name=${GPU_NAME:-unknown} drivers=${GPU_DRIVERS:-unknown}"

VIRT="$(systemd-detect-virt 2>/dev/null || true)"
if [[ -n "$VIRT" && "$VIRT" != none ]]; then
  export MECHOS_VM_MODE=1 QT_OPENGL=software LIBGL_ALWAYS_SOFTWARE=1 QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software
  log "virtualization=$VIRT; bypassing Gamescope"; start_plasma_mechscope
fi
if [[ ! -x /usr/bin/gamescope ]]; then
  log 'Gamescope missing on hardware; using Plasma fallback'
  start_plasma_mechscope
fi

export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=gamescope XDG_SESSION_DESKTOP=MechScope DESKTOP_SESSION=mechscope MECHOS_SESSION_SUPERVISED=1
export STEAM_ALLOW_DRIVE_UNMOUNT=1 STEAM_GAMESCOPE_TEARING_SUPPORTED=1 STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT=1
export STEAM_GAMESCOPE_COLOR_MANAGED=1 STEAM_MULTIPLE_XWAYLANDS=1 STEAM_DISABLE_AUDIO_DEVICE_SWITCHING=1
export STEAM_UPDATEUI_PNG_BACKGROUND=/usr/share/backgrounds/mechos/mechscope-loading.png
[[ "${MECHOS_ENABLE_VRR:-0}" == 1 ]] && export STEAM_GAMESCOPE_VRR_SUPPORTED=1
if [[ "${MECHOS_HDR:-0}" == 1 ]]; then export STEAM_GAMESCOPE_HDR_SUPPORTED=1 STEAM_GAMESCOPE_VIRTUAL_WHITE=1; fi

if grep -Fq 'Kernel driver in use: nvidia' <<<"$GPU_BLOCK"; then
  export GBM_BACKEND=nvidia-drm __GLX_VENDOR_LIBRARY_NAME=nvidia
  log 'NVIDIA proprietary kernel driver detected; enabling NVIDIA GBM environment'
elif grep -Fq 'Kernel driver in use: nouveau' <<<"$GPU_BLOCK"; then
  unset GBM_BACKEND __GLX_VENDOR_LIBRARY_NAME 2>/dev/null || true
  log 'Nouveau kernel driver detected; proprietary NVIDIA environment disabled'
fi

# Intel-only UMA integration. Preserve AMD/NVIDIA/hybrid behavior.
MECHOS_INTEL_UMA=0
MECHOS_INTEL_RENDER_NODE=''
if grep -qi intel <<<"$GPU_BLOCK" && ! grep -Eqi 'NVIDIA|AMD|ATI|Advanced Micro Devices' <<<"$GPU_BLOCK"; then
  MECHOS_INTEL_UMA=1
  export MECHOS_INTEL_UMA
  for vendor in /sys/class/drm/renderD*/device/vendor; do
    [[ -r "$vendor" ]] || continue
    [[ "$(tr '[:upper:]' '[:lower:]' <"$vendor" 2>/dev/null)" == 0x8086 ]] || continue
    candidate="/dev/dri/$(basename "$(dirname "$(dirname "$vendor")")")"
    if [[ -r "$candidate" && -w "$candidate" ]]; then
      MECHOS_INTEL_RENDER_NODE="$candidate"
      break
    fi
  done
  log "Intel UMA detected render-node=$MECHOS_INTEL_RENDER_NODE"

  intel_vulkan_ok=0
  if command -v vulkaninfo >/dev/null 2>&1; then
    if timeout 8s vulkaninfo --summary 2>>"$LOG_FILE" | grep -Eqi 'Intel|ANV'; then
      intel_vulkan_ok=1
    fi
  fi

  if [[ -z "$MECHOS_INTEL_RENDER_NODE" || "$intel_vulkan_ok" -ne 1 ]]; then
    log 'Intel UMA Gamescope preflight unavailable; using supervised Plasma fallback'
    start_plasma_mechscope
  fi

  unset STEAM_GAMESCOPE_VRR_SUPPORTED STEAM_GAMESCOPE_HDR_SUPPORTED STEAM_GAMESCOPE_VIRTUAL_WHITE
  MECHOS_ENABLE_VRR=0
  MECHOS_HDR=0
  export MECHOS_ENABLE_VRR MECHOS_HDR
fi

# Capability gate for legacy/non-Vulkan GPUs such as mixed-generation GT 730
# cards. A failed Gamescope prerequisite must not prevent MechScope itself from
# opening; run it inside supervised Plasma instead.
if ! command -v vulkaninfo >/dev/null 2>&1; then
  log "vulkaninfo missing for GPU=${GPU_NAME:-unknown} drivers=${GPU_DRIVERS:-unknown}; using supervised Plasma fallback"
  start_plasma_mechscope
fi
if ! timeout 8s vulkaninfo --summary >>"$LOG_FILE" 2>&1; then
  log "Vulkan preflight failed GPU=${GPU_NAME:-unknown} drivers=${GPU_DRIVERS:-unknown}; using supervised Plasma fallback"
  start_plasma_mechscope
fi

run_gamescope(){
  local label="$1"; shift
  local rc=0
  log "starting source-owned Gamescope attempt=$label target=$MECHSCOPE_TARGET interpreter=${MECHSCOPE_COMMAND[0]}"
  set +e
  /usr/bin/gamescope "$@" -- /usr/bin/flock -n "$LOCK_FILE" "${MECHSCOPE_COMMAND[@]}" >>"$LOG_FILE" 2>&1
  rc=$?
  set -e
  if ! gaming_requested; then log "Gamescope attempt=$label exited rc=$rc after intentional mode transition"; return 0; fi
  log "Gamescope attempt=$label exited rc=$rc while Gaming Mode active; recoverable failure"
  return 90
}

ARGS=(-e -f)
[[ "${MECHOS_ENABLE_VRR:-0}" == 1 ]] && ARGS+=(--adaptive-sync)
[[ "${MECHOS_HDR:-0}" == 1 ]] && ARGS+=(--hdr-enabled)
if [[ "$MECHOS_INTEL_UMA" == 1 ]]; then
  ARGS=(-f)
  log 'Intel UMA integration: conservative fullscreen Gamescope arguments enabled'
fi
rm -f "$FALLBACK_REQUEST"
if run_gamescope primary "${ARGS[@]}"; then exit 0; fi
if gaming_requested && run_gamescope conservative -f; then exit 0; fi
if gaming_requested; then log 'Gamescope ended; switching to supervised Plasma fallback'; start_plasma_mechscope; fi
exit 0
