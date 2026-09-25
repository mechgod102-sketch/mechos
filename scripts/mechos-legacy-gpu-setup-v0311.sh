#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_LEGACY_GPU_SETUP_V0311

APPLY=0
MODE="${1:-}"
case "$MODE" in
  --apply|--apply-open-source) APPLY=1 ;;
  --report|"") ;;
  --branch) ;;
  *) echo "Usage: mechos-legacy-gpu-setup [--report|--branch|--apply-open-source]" >&2; exit 2 ;;
esac

GPU_LINES="$(lspci -nnk 2>/dev/null | grep -A4 -Ei 'VGA|3D|Display' || true)"
DRIVERS="$(printf '%s\n' "$GPU_LINES" | sed -n 's/^[[:space:]]*Kernel driver in use: //p' | sort -u | xargs || true)"
NVIDIA=0
AMD=0
grep -qi nvidia <<<"$GPU_LINES" && NVIDIA=1
grep -Eqi 'AMD|ATI|Advanced Micro Devices' <<<"$GPU_LINES" && AMD=1

nvidia_branch(){
  local text="$1"
  if grep -Eqi 'GeForce (RTX|GTX 16)|Quadro RTX|TITAN RTX|Tesla T4' <<<"$text"; then
    printf 'current-nvidia-open'; return
  fi
  if grep -Eqi 'GeForce GTX (10[0-9]{2}|9[0-9]{2}|750([[:space:]]Ti)?)|TITAN (V|Xp)' <<<"$text"; then
    printf 'nvidia-580xx-dkms'; return
  fi
  if grep -Eqi 'GeForce GTX (6[0-9]{2}|7(1[0-9]|2[0-9]|3[0-9]|4[0-9]|6[0-9]|7[0-9]|8[0-9])[0-9]?)|GeForce GT 7(1|2|3|4)[0-9]|Quadro K[0-9]' <<<"$text"; then
    printf 'nvidia-470xx-dkms'; return
  fi
  if grep -Eqi 'GeForce (GTX|GTS|GT) (4[0-9]{2}|5[0-9]{2})' <<<"$text"; then
    printf 'nvidia-390xx-dkms'; return
  fi
  if grep -Eqi 'GeForce (8[0-9]{3}|9[0-9]{3}|(GTX|GTS|GT) [23][0-9]{2})' <<<"$text"; then
    printf 'nvidia-340xx-dkms'; return
  fi
  printf 'manual-generation-check'
}

BRANCH="none"
if [[ "$NVIDIA" -eq 1 ]]; then
  BRANCH="$(nvidia_branch "$GPU_LINES")"
fi

if [[ "$MODE" == "--branch" ]]; then
  printf '%s\n' "$BRANCH"
  exit 0
fi

echo 'MechOS legacy GPU compatibility report'
echo "Kernel graphics drivers: ${DRIVERS:-none detected}"
printf '%s\n' "${GPU_LINES:-No display adapter detected}"

if [[ "$NVIDIA" -eq 1 ]]; then
  echo
  echo "NVIDIA compatibility branch: $BRANCH"
  case "$BRANCH" in
    current-nvidia-open)
      echo 'This GPU appears to be from the current NVIDIA open-kernel-module generations.'
      ;;
    nvidia-580xx-dkms)
      echo 'Legacy NVIDIA branch detected: Maxwell/Pascal/Volta class. Proprietary legacy package is AUR-managed and is not auto-installed by MechOS.'
      ;;
    nvidia-470xx-dkms)
      echo 'Legacy NVIDIA branch detected: common Kepler class. Proprietary legacy package is AUR-managed and is not auto-installed by MechOS.'
      ;;
    nvidia-390xx-dkms)
      echo 'Legacy NVIDIA branch detected: common Fermi class. Proprietary legacy package is AUR-managed and is not auto-installed by MechOS.'
      ;;
    nvidia-340xx-dkms)
      echo 'Legacy NVIDIA branch detected: common Tesla-era class. Proprietary legacy package is AUR-managed and is not auto-installed by MechOS.'
      ;;
    *)
      echo 'NVIDIA generation could not be mapped safely from the PCI model string. MechOS will preserve the current driver and use the desktop fallback if Vulkan is unavailable.'
      ;;
  esac
  if grep -qw nouveau <<<"$DRIVERS"; then
    echo 'Active NVIDIA kernel driver: nouveau (open-source legacy fallback).'
  elif grep -qw nvidia <<<"$DRIVERS"; then
    echo 'Active NVIDIA kernel driver: nvidia proprietary.'
  fi
fi

if [[ "$AMD" -eq 1 ]]; then
  echo
  if grep -qw amdgpu <<<"$DRIVERS"; then
    echo 'AMD compatibility path: AMDGPU + Mesa/RADV.'
  elif grep -qw radeon <<<"$DRIVERS"; then
    echo 'AMD compatibility path: legacy radeon + Mesa/OpenGL. Gamescope is allowed only when Vulkan preflight succeeds.'
  else
    echo 'AMD compatibility path: driver not resolved; MechOS will keep the existing kernel driver and use safe fallback behavior.'
  fi
fi

if command -v vulkaninfo >/dev/null 2>&1; then
  if timeout 8s vulkaninfo --summary >/tmp/mechos-legacy-gpu-vulkan.$$ 2>&1; then
    echo 'Vulkan preflight: PASS'
    sed -n '1,60p' /tmp/mechos-legacy-gpu-vulkan.$$
  else
    echo 'Vulkan preflight: FAIL — MechScope will use supervised Plasma fallback.'
  fi
  rm -f /tmp/mechos-legacy-gpu-vulkan.$$
else
  echo 'Vulkan preflight: vulkaninfo missing — MechScope will use supervised Plasma fallback until Vulkan support is installed.'
fi

[[ "$APPLY" -eq 1 ]] || exit 0
[[ -f /var/lib/mechos/installed ]] || { echo 'Not an installed MechOS system; no packages changed.' >&2; exit 1; }
[[ ! -e /run/archiso/bootmnt ]] || { echo 'Live ISO detected; no packages changed.'; exit 0; }
if [[ "$(id -u)" -ne 0 ]]; then exec sudo "$0" --apply-open-source; fi

PACKAGES=(mesa lib32-mesa vulkan-tools)
if [[ "$AMD" -eq 1 ]]; then
  if grep -qw amdgpu <<<"$DRIVERS"; then
    PACKAGES+=(vulkan-radeon lib32-vulkan-radeon libva-mesa-driver)
  else
    PACKAGES+=(xf86-video-ati)
  fi
fi
if [[ "$NVIDIA" -eq 1 && ! " $DRIVERS " =~ " nvidia " ]]; then
  PACKAGES+=(xf86-video-nouveau)
  pacman -Si vulkan-nouveau >/dev/null 2>&1 && PACKAGES+=(vulkan-nouveau)
  pacman -Si lib32-vulkan-nouveau >/dev/null 2>&1 && PACKAGES+=(lib32-vulkan-nouveau)
fi

declare -A SEEN=()
UNIQUE=()
for pkg in "${PACKAGES[@]}"; do
  [[ -n "${SEEN[$pkg]:-}" ]] && continue
  SEEN[$pkg]=1
  UNIQUE+=("$pkg")
done

pacman -Syu --needed --noconfirm "${UNIQUE[@]}"
echo 'Legacy open-source GPU compatibility packages installed.'
echo 'MechOS did not install AUR NVIDIA proprietary legacy packages automatically.'
