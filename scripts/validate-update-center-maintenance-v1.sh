#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_UPDATE_CENTER_MAINTENANCE_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 -m py_compile "$ROOT/scripts/mechos-update-center-maintenance-v1.py"
grep -Fq 'MECHOS_UPDATE_CENTER_MAINTENANCE_V1' "$ROOT/scripts/mechos-update-center-maintenance-v1.py"
grep -Fq 'infrastructure-v1' "$ROOT/scripts/mechos-update-center-maintenance-v1.py"
grep -Fq 'MECHOS_RELEASE_VERSION_UNCHANGED=1' "$ROOT/scripts/mechos-update-center-maintenance-v1.py"
grep -Fq 'EXPECTED_KEY_FP = "03ae056eb65a505b8239b8b123b6437eec3afc906b517ff2a3d8e08607fe4391"' "$ROOT/scripts/mechos-update-center-maintenance-v1.py"
grep -Fq 'Existing signing key does not match the pinned MechOS key; refusing silent replacement.' "$ROOT/scripts/mechos-update-center-maintenance-v1.py"
grep -Fq 'MECHOS_UPDATE_HELPER_SELFTEST=1' "$ROOT/scripts/mechos-update-center-maintenance-v1.py"
grep -Fq 'pkexec' "$ROOT/scripts/mechos-update-center-maintenance-v1.py"

# This maintenance tool is separate from normal hotfix builders. The normal
# payload-only freeze must remain enforced.
bash "$ROOT/scripts/validate-update-infrastructure-freeze-v1.sh"

echo 'Updater maintenance v1 source contracts validated.'
