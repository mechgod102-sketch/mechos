#!/usr/bin/env python3
# MECHOS_INTEL_UMA_PATCH_V36
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: mechos-intel-uma-session-patch-v36 TARGET")

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
marker = "# MECHOS_INTEL_UMA_INTEGRATION_V36"
if marker in text:
    raise SystemExit(0)

anchor = "if lspci 2>/dev/null | grep -qi nvidia; then export GBM_BACKEND=nvidia-drm __GLX_VENDOR_LIBRARY_NAME=nvidia; fi"
if anchor not in text:
    raise SystemExit("MechScope session NVIDIA anchor missing")

integration = r'''if lspci 2>/dev/null | grep -qi nvidia; then export GBM_BACKEND=nvidia-drm __GLX_VENDOR_LIBRARY_NAME=nvidia; fi

# MECHOS_INTEL_UMA_INTEGRATION_V36
# Integration only: AMD, NVIDIA and hybrid paths keep their existing behavior.
MECHOS_INTEL_UMA=0
MECHOS_INTEL_RENDER_NODE=''
GPU_BLOCK="$(lspci -nnk 2>/dev/null | grep -A3 -Ei 'VGA|3D|Display' || true)"
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
    log 'Intel UMA Gamescope preflight unavailable; using existing supervised Plasma fallback'
    start_plasma_mechscope
  fi

  unset STEAM_GAMESCOPE_VRR_SUPPORTED STEAM_GAMESCOPE_HDR_SUPPORTED STEAM_GAMESCOPE_VIRTUAL_WHITE
  MECHOS_ENABLE_VRR=0
  MECHOS_HDR=0
  export MECHOS_ENABLE_VRR MECHOS_HDR
fi'''
text = text.replace(anchor, integration, 1)

args_anchor = 'ARGS=(-e -f); [[ "${MECHOS_ENABLE_VRR:-0}" == 1 ]] && ARGS+=(--adaptive-sync); [[ "${MECHOS_HDR:-0}" == 1 ]] && ARGS+=(--hdr-enabled)'
if args_anchor not in text:
    raise SystemExit("MechScope Gamescope argument anchor missing")
args_new = r'''ARGS=(-e -f); [[ "${MECHOS_ENABLE_VRR:-0}" == 1 ]] && ARGS+=(--adaptive-sync); [[ "${MECHOS_HDR:-0}" == 1 ]] && ARGS+=(--hdr-enabled)
if [[ "$MECHOS_INTEL_UMA" == 1 ]]; then
  ARGS=(-f)
  log 'Intel UMA integration: conservative fullscreen Gamescope arguments enabled'
fi'''
text = text.replace(args_anchor, args_new, 1)

p.write_text(text, encoding="utf-8")
