#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX_0311_LEGACY_GPU_UPDATE_RELIABILITY_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n   "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"   "$ROOT/scripts/mechos-hotfix-0.3.1-1-apply.sh"   "$ROOT/scripts/build-hotfix-0.3.1-1.sh"   "$ROOT/scripts/mechos-update-helper-v37.sh"
python3 -m py_compile   "$ROOT/scripts/mechos-legacy-gpu-session-patch-v0311.py"   "$ROOT/scripts/mechos-legacy-gpu-control-patch-v0311.py"   "$ROOT/scripts/mechos-gpu-setup-integration-v0311.py"   "$ROOT/scripts/mechos-update-center-reference-v8.py"

grep -Fq 'MECHOS_LEGACY_GPU_SETUP_V0311' "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"
grep -Fq 'nvidia-580xx-dkms' "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"
grep -Fq 'nvidia-470xx-dkms' "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"
grep -Fq 'nvidia-390xx-dkms' "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"
grep -Fq 'nvidia-340xx-dkms' "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"
grep -Fq 'AMDGPU + Mesa/RADV' "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"
grep -Fq 'legacy radeon + Mesa/OpenGL' "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"

# Additive integration regression: retain the modern package paths while adding
# legacy branches into the existing universal GPU setup.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp "$ROOT/overlay/rootfs/usr/local/bin/mechos-gpu-setup" "$tmp/mechos-gpu-setup"
python3 "$ROOT/scripts/mechos-gpu-setup-integration-v0311.py" "$tmp/mechos-gpu-setup"
bash -n "$tmp/mechos-gpu-setup"
grep -Fq 'MECHOS_LEGACY_GPU_INTEGRATION_V0311' "$tmp/mechos-gpu-setup"
grep -Fq 'PACKAGES+=(nvidia-open nvidia-utils lib32-nvidia-utils nvidia-prime)' "$tmp/mechos-gpu-setup"
grep -Fq 'PACKAGES+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver)' "$tmp/mechos-gpu-setup"
grep -Fq 'xf86-video-nouveau' "$tmp/mechos-gpu-setup"
grep -Fq 'xf86-video-ati' "$tmp/mechos-gpu-setup"

cp "$ROOT/scripts/mechscope-session-v20.sh" "$tmp/mechscope-session"
python3 "$ROOT/scripts/mechos-intel-uma-session-patch-v36.py" "$tmp/mechscope-session"
python3 "$ROOT/scripts/mechos-legacy-gpu-session-patch-v0311.py" "$tmp/mechscope-session"
bash -n "$tmp/mechscope-session"
grep -Fq 'MECHOS_INTEL_UMA_INTEGRATION_V36' "$tmp/mechscope-session"
grep -Fq 'MECHOS_LEGACY_GPU_SESSION_V0311' "$tmp/mechscope-session"
grep -Fq 'Kernel driver in use: nvidia' "$tmp/mechscope-session"
grep -Fq 'Kernel driver in use: nouveau' "$tmp/mechscope-session"
grep -Fq 'Vulkan preflight failed' "$tmp/mechscope-session"

cp "$ROOT/scripts/mechos-031-control-suite.py" "$tmp/control.py"
python3 "$ROOT/scripts/mechos-legacy-gpu-control-patch-v0311.py" "$tmp/control.py"
python3 -m py_compile "$tmp/control.py"
grep -Fq 'MECHOS_LEGACY_GPU_CONTROL_V0311' "$tmp/control.py"
grep -Fq 'Legacy GPU Report' "$tmp/control.py"

grep -Fq "'version':'0.3.1-hotfix.1'" "$ROOT/scripts/build-hotfix-0.3.1-1.sh"
grep -Fq 'MechOS-0.3.1-update.tar.zst' "$ROOT/scripts/build-hotfix-0.3.1-1.sh"
grep -Fq 'Refusing MechOS downgrade' "$ROOT/scripts/mechos-update-helper-v37.sh"
grep -Fq 'timeout=30' "$ROOT/scripts/mechos-update-center-reference-v8.py"

echo 'MechOS 0.3.1 Hotfix 1 additive legacy GPU and updater reliability contracts validated.'
