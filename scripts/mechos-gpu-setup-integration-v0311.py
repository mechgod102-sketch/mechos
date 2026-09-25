#!/usr/bin/env python3
# MECHOS_GPU_SETUP_INTEGRATION_V0311
from pathlib import Path
import sys

p=Path(sys.argv[1])
text=p.read_text(encoding="utf-8")
marker="# MECHOS_LEGACY_GPU_INTEGRATION_V0311"
if marker in text:
    raise SystemExit(0)

anchor='APPLY=0\n[[ "${1:-}" == "--apply" ]] && APPLY=1\n'
if anchor not in text:
    raise SystemExit("GPU setup apply anchor missing")
text=text.replace(anchor, anchor+marker+'\nLEGACY_GPU_HELPER=/usr/local/bin/mechos-legacy-gpu-setup\nNVIDIA_COMPAT_BRANCH=none\n',1)

old_nvidia='''if grep -qi nvidia <<<"$GPU_LINES"; then
  add_vendor nvidia
  PACKAGES+=(nvidia-open nvidia-utils lib32-nvidia-utils nvidia-prime)
fi
'''
new_nvidia='''if grep -qi nvidia <<<"$GPU_LINES"; then
  add_vendor nvidia
  NVIDIA_COMPAT_BRANCH=current-nvidia-open
  if [[ -x "$LEGACY_GPU_HELPER" ]]; then
    NVIDIA_COMPAT_BRANCH="$("$LEGACY_GPU_HELPER" --branch 2>/dev/null || printf 'manual-generation-check')"
  fi
  case "$NVIDIA_COMPAT_BRANCH" in
    current-nvidia-open)
      # Preserve the existing modern NVIDIA path unchanged.
      PACKAGES+=(nvidia-open nvidia-utils lib32-nvidia-utils nvidia-prime)
      ;;
    nvidia-580xx-dkms|nvidia-470xx-dkms|nvidia-390xx-dkms|nvidia-340xx-dkms|manual-generation-check)
      # Add legacy support without pulling unreviewed AUR PKGBUILDs as root.
      # Nouveau/Mesa provides the safe in-repo fallback; the report identifies
      # the proprietary legacy branch for an explicit user-managed install.
      PACKAGES+=(mesa lib32-mesa xf86-video-nouveau)
      ;;
  esac
fi
'''
if old_nvidia not in text:
    raise SystemExit("modern NVIDIA block missing")
text=text.replace(old_nvidia,new_nvidia,1)

old_amd='''if grep -Eqi 'AMD|ATI|Advanced Micro Devices' <<<"$GPU_LINES"; then
  add_vendor amd
  PACKAGES+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver)
fi
'''
new_amd='''if grep -Eqi 'AMD|ATI|Advanced Micro Devices' <<<"$GPU_LINES"; then
  add_vendor amd
  if grep -Fq 'Kernel driver in use: radeon' <<<"$GPU_LINES"; then
    # Legacy Radeon path: retain Mesa/OpenGL and avoid assuming RADV/Vulkan.
    # MechScope's Vulkan preflight decides whether Gamescope is safe.
    PACKAGES+=(mesa lib32-mesa libva-mesa-driver xf86-video-ati)
  else
    # Preserve the existing AMDGPU + RADV path unchanged.
    PACKAGES+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver)
  fi
fi
'''
if old_amd not in text:
    raise SystemExit("modern AMD block missing")
text=text.replace(old_amd,new_amd,1)

old_modprobe='''if [[ " ${VENDORS[*]} " == *' nvidia '* ]]; then
  install -d -m 755 /etc/modprobe.d
  cat > /etc/modprobe.d/90-mechos-nvidia-drm.conf <<'EOF'
# Required for reliable Gamescope/KMS operation on the proprietary NVIDIA stack.
options nvidia_drm modeset=1
EOF
  echo 'NVIDIA DRM/KMS is configured for the next module load/reboot.'
fi
'''
new_modprobe='''if [[ " ${VENDORS[*]} " == *' nvidia '* ]]; then
  if [[ "$NVIDIA_COMPAT_BRANCH" == current-nvidia-open ]]; then
    install -d -m 755 /etc/modprobe.d
    cat > /etc/modprobe.d/90-mechos-nvidia-drm.conf <<'EOF'
# Required for reliable Gamescope/KMS operation on the proprietary NVIDIA stack.
options nvidia_drm modeset=1
EOF
    echo 'NVIDIA DRM/KMS is configured for the next module load/reboot.'
  else
    rm -f /etc/modprobe.d/90-mechos-nvidia-drm.conf
    echo "Legacy NVIDIA compatibility integrated: $NVIDIA_COMPAT_BRANCH"
    echo 'Using the safe Nouveau/Mesa path unless a matching proprietary legacy branch is installed explicitly.'
  fi
fi
'''
if old_modprobe not in text:
    raise SystemExit("NVIDIA KMS block missing")
text=text.replace(old_modprobe,new_modprobe,1)

old_summary='''echo "GPU packages updated for: ${VENDORS[*]}."
echo 'MechOS will automatically choose the preferred Gamescope Vulkan device at launch.'
'''
new_summary='''echo "GPU packages updated for: ${VENDORS[*]}."
if [[ "$NVIDIA_COMPAT_BRANCH" != none && "$NVIDIA_COMPAT_BRANCH" != current-nvidia-open ]]; then
  echo "Legacy NVIDIA branch: $NVIDIA_COMPAT_BRANCH"
fi
echo 'MechOS will automatically choose the preferred Gamescope Vulkan device at launch.'
'''
if old_summary not in text:
    raise SystemExit("GPU summary block missing")
text=text.replace(old_summary,new_summary,1)

p.write_text(text,encoding="utf-8")
