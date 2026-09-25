#!/usr/bin/env python3
# MECHOS_LEGACY_GPU_SESSION_PATCH_V0311
from pathlib import Path
import sys

p=Path(sys.argv[1])
text=p.read_text(encoding='utf-8')
marker='# MECHOS_LEGACY_GPU_SESSION_V0311'
if marker in text:
    raise SystemExit(0)

needle='# MECHOS_MECHSCOPE_SESSION_V23_SOURCE_RUNTIME\n'
if needle not in text:
    raise SystemExit('MechScope session marker missing')
text=text.replace(needle, needle+marker+'\n',1)

old="if lspci 2>/dev/null | grep -qi nvidia; then export GBM_BACKEND=nvidia-drm __GLX_VENDOR_LIBRARY_NAME=nvidia; fi"
new="""if lspci -nnk 2>/dev/null | grep -Fq 'Kernel driver in use: nvidia'; then
  export GBM_BACKEND=nvidia-drm __GLX_VENDOR_LIBRARY_NAME=nvidia
  log 'NVIDIA proprietary kernel driver detected; enabling NVIDIA GBM environment'
elif lspci -nnk 2>/dev/null | grep -Fq 'Kernel driver in use: nouveau'; then
  unset GBM_BACKEND __GLX_VENDOR_LIBRARY_NAME 2>/dev/null || true
  log 'Nouveau kernel driver detected; proprietary NVIDIA environment disabled'
fi"""
if old not in text:
    raise SystemExit('NVIDIA environment anchor missing')
text=text.replace(old,new,1)

anchor="if [[ ! -x /usr/bin/gamescope ]]; then log 'Gamescope missing on hardware; using Plasma fallback'; start_plasma_mechscope; fi\n"
block="""if [[ ! -x /usr/bin/gamescope ]]; then log 'Gamescope missing on hardware; using Plasma fallback'; start_plasma_mechscope; fi
if ! command -v vulkaninfo >/dev/null 2>&1; then
  log 'vulkaninfo missing; legacy GPU safety fallback to Plasma'
  start_plasma_mechscope
fi
if ! timeout 8s vulkaninfo --summary >/dev/null 2>&1; then
  log 'Vulkan preflight failed; legacy/non-Vulkan GPU safety fallback to Plasma'
  start_plasma_mechscope
fi
"""
if anchor not in text:
    raise SystemExit('Gamescope fallback anchor missing')
text=text.replace(anchor,block,1)

p.write_text(text,encoding='utf-8')
