#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX36_INTEL_UMA_INTEGRATION_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/scripts/mechos-intel-uma-preflight-v36.sh" "$ROOT/scripts/mechos-hotfix-0.3.0-36-apply.sh" "$ROOT/scripts/build-hotfix-0.3.0-36.sh"
python3 -m py_compile "$ROOT/scripts/mechos-intel-uma-session-patch-v36.py"
grep -Fq 'MECHOS_INTEL_UMA_PATCH_V36' "$ROOT/scripts/mechos-intel-uma-session-patch-v36.py"
grep -Fq 'MECHOS_INTEL_UMA_PREFLIGHT_V36' "$ROOT/scripts/mechos-intel-uma-preflight-v36.sh"
grep -Fq 'MECHOS_HOTFIX36_INTEL_UMA_INTEGRATION_V1' "$ROOT/scripts/mechos-hotfix-0.3.0-36-apply.sh"
grep -Fq 'MechOS-0.3.0-hotfix.35-update.tar.zst' "$ROOT/scripts/build-hotfix-0.3.0-36.sh"
grep -Fq "'version':'0.3.0-hotfix.36'" "$ROOT/scripts/build-hotfix-0.3.0-36.sh"

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
cp "$ROOT/scripts/mechscope-session-v20.sh" "$tmp"
python3 "$ROOT/scripts/mechos-intel-uma-session-patch-v36.py" "$tmp"
bash -n "$tmp"
grep -Fq 'MECHOS_INTEL_UMA_INTEGRATION_V36' "$tmp"
grep -Fq 'GBM_BACKEND=nvidia-drm' "$tmp"
grep -Fq 'run_gamescope primary' "$tmp"
grep -Fq 'run_gamescope conservative' "$tmp"
grep -Fq 'start_plasma_mechscope' "$tmp"
echo 'Hotfix 36 Intel UMA integration source contracts validated.'
