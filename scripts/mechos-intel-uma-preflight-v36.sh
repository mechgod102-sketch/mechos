#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_INTEL_UMA_PREFLIGHT_V36

GPU_BLOCK="$(lspci -nnk 2>/dev/null | grep -A3 -Ei 'VGA|3D|Display' || true)"
if ! grep -qi intel <<<"$GPU_BLOCK"; then
  echo 'Intel graphics not detected.'
  exit 2
fi
if grep -Eqi 'NVIDIA|AMD|ATI|Advanced Micro Devices' <<<"$GPU_BLOCK"; then
  echo 'Hybrid or multi-GPU system detected; Intel UMA integration will not be forced.'
  exit 3
fi

echo 'Intel UMA detected.'
printf '%s\n' "$GPU_BLOCK"

render=''
for vendor in /sys/class/drm/renderD*/device/vendor; do
  [[ -r "$vendor" ]] || continue
  [[ "$(tr '[:upper:]' '[:lower:]' <"$vendor" 2>/dev/null)" == 0x8086 ]] || continue
  candidate="/dev/dri/$(basename "$(dirname "$(dirname "$vendor")")")"
  if [[ -r "$candidate" && -w "$candidate" ]]; then render="$candidate"; break; fi
done

[[ -n "$render" ]] && echo "Intel render node: $render" || echo 'Intel render node missing or inaccessible.'

for pkg in mesa vulkan-intel intel-media-driver gamescope vulkan-tools; do
  if pacman -Q "$pkg" >/dev/null 2>&1; then echo "package:$pkg=installed"; else echo "package:$pkg=missing"; fi
done

if command -v vulkaninfo >/dev/null 2>&1 && timeout 8s vulkaninfo --summary 2>/dev/null | grep -Eqi 'Intel|ANV'; then
  echo 'vulkan:intel=ready'
else
  echo 'vulkan:intel=not-ready'
fi

if [[ -n "$render" ]] && command -v vulkaninfo >/dev/null 2>&1 && timeout 8s vulkaninfo --summary 2>/dev/null | grep -Eqi 'Intel|ANV'; then
  echo 'MechScope Intel UMA Gamescope integration: ready'
  exit 0
fi

echo 'MechScope Intel UMA integration: existing Plasma fallback will be used'
exit 1
