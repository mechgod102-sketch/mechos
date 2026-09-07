#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX23_ACCOUNT_REPAIR_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/scripts/mechos-firstboot-update-apply-v23.sh"
bash -n "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh"
bash -n "$ROOT/scripts/build-hotfix-0.3.0-23.sh"
python3 -m py_compile "$ROOT/scripts/mechos-update-center-reference-v8.py"

grep -Fq 'MECHOS_FIRSTBOOT_UPDATE_APPLY_V23' "$ROOT/scripts/mechos-firstboot-update-apply-v23.sh"
grep -Fq 'PKEXEC_UID' "$ROOT/scripts/mechos-firstboot-update-apply-v23.sh"
grep -Fq "[ \"\$origin_user\" = 'mechos-setup' ]" "$ROOT/scripts/mechos-firstboot-update-apply-v23.sh"
grep -Fq 'exec "$HELPER" apply' "$ROOT/scripts/mechos-firstboot-update-apply-v23.sh"
! grep -Fq 'curl ' "$ROOT/scripts/mechos-firstboot-update-apply-v23.sh"
! grep -Fq 'wget ' "$ROOT/scripts/mechos-firstboot-update-apply-v23.sh"

grep -Fq 'MECHOS_HOTFIX23_POSTINSTALL_ACCOUNT_REPAIR_V1' "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh"
grep -Fq 'passwd -d "$SETUP_USER"' "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh"
grep -Fq 'gpasswd -d "$SETUP_USER" wheel' "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh"
grep -Fq 'showFullScreen()' "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh"
grep -Fq 'mechos-oobe-finish-reboot' "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh"
grep -Fq '99-mechos-final-user.conf' "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh"
grep -Fq 'userdel -r "$SETUP_USER"' "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh"
grep -Fq 'mechos-firstboot-update-apply' "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh"
grep -Fq 'Relogin=false' "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh"

grep -Fq 'FIRSTBOOT_APPLY = "/usr/local/libexec/mechos-firstboot-update-apply"' "$ROOT/scripts/mechos-update-center-reference-v8.py"
grep -Fq 'user == "mechos-setup" and firstboot' "$ROOT/scripts/mechos-update-center-reference-v8.py"
grep -Fq 'pkexec' "$ROOT/scripts/mechos-update-center-reference-v8.py"

grep -Fq "'version':'0.3.0-hotfix.23'" "$ROOT/scripts/build-hotfix-0.3.0-23.sh"
grep -Fq 'MechOS-0.3.0-hotfix.22.6-update.tar.zst' "$ROOT/scripts/build-hotfix-0.3.0-23.sh"
grep -Fq 'MechOS-0.3.0-hotfix.23-update.tar.zst' "$ROOT/scripts/build-hotfix-0.3.0-23.sh"
grep -Fq 'requires_reboot' "$ROOT/scripts/build-hotfix-0.3.0-23.sh"

printf 'Hotfix 23 source validation passed.\n'
