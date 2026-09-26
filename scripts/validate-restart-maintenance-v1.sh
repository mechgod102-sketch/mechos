#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_RESTART_MAINTENANCE_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n   "$ROOT/scripts/mechos-powerctl-v1.sh"   "$ROOT/scripts/mechos-reboot-frozen-v1.sh"
python3 -m py_compile "$ROOT/scripts/mechos-restart-maintenance-v1.py"

grep -Fq 'MECHOS_POWERCTL_V1_FROZEN' "$ROOT/scripts/mechos-powerctl-v1.sh"
grep -Fq 'MECHOS_REBOOT_FROZEN_V1' "$ROOT/scripts/mechos-reboot-frozen-v1.sh"
grep -Fq 'MECHOS_RESTART_MAINTENANCE_V1' "$ROOT/scripts/mechos-restart-maintenance-v1.py"
grep -Fq 'MECHOS_POWERCTL_SELFTEST=1' "$ROOT/scripts/mechos-powerctl-v1.sh"
grep -Fq 'logoutAndReboot' "$ROOT/scripts/mechos-powerctl-v1.sh"
grep -Fq 'org.freedesktop.login1.Manager Reboot' "$ROOT/scripts/mechos-powerctl-v1.sh"
grep -Fq 'pkexec /usr/bin/systemctl reboot' "$ROOT/scripts/mechos-powerctl-v1.sh"
! grep -Fq 'loginctl reboot' "$ROOT/scripts/mechos-powerctl-v1.sh"

# Self-test must never trigger an actual reboot.
out="$(bash "$ROOT/scripts/mechos-powerctl-v1.sh" selftest)"
grep -Fq 'MECHOS_POWERCTL_SELFTEST=1' <<<"$out"

echo 'Frozen restart infrastructure source contracts validated.'
