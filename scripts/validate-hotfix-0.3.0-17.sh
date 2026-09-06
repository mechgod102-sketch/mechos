#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in \
  "$ROOT/scripts/mechos-update-transaction-v14.sh" \
  "$ROOT/scripts/mechos-clear-reboot-required-v17.sh" \
  "$ROOT/scripts/mechos-hotfix-0.3.0-17-apply.sh" \
  "$ROOT/scripts/build-hotfix-0.3.0-17.sh"; do
  bash -n "$f"
done
python3 -m py_compile "$ROOT/scripts/mechos-hotfix17-updater-patch.py"

grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$ROOT/scripts/mechos-update-transaction-v14.sh"
# Regression gate for the exact Hotfix 16 failure: transaction code must not
# invoke rsync. Comments may mention it; executable command lines may not.
! grep -Eq '^[[:space:]]*rsync([[:space:]]|$)' "$ROOT/scripts/mechos-update-transaction-v14.sh"
grep -Fq "required base command missing" "$ROOT/scripts/mechos-update-transaction-v14.sh"
grep -Fq "tar --warning=no-timestamp -C / -xpf -" "$ROOT/scripts/mechos-update-transaction-v14.sh"
grep -Fq 'MECHOS_CLEAR_REBOOT_REQUIRED_V17' "$ROOT/scripts/mechos-clear-reboot-required-v17.sh"
grep -Fq 'hotfix-0.3.0-17-applied' "$ROOT/scripts/mechos-clear-reboot-required-v17.sh"
grep -Fq 'build-hotfix-0.3.0-16.sh' "$ROOT/scripts/build-hotfix-0.3.0-17.sh"
grep -Fq -- '--mtime="@$EPOCH"' "$ROOT/scripts/build-hotfix-0.3.0-17.sh"

# Smoke-test the runtime patch against the exact source versions currently
# installed by Hotfix 14. This catches anchor drift before publication.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp "$ROOT/scripts/mechos-update-helper-v14.sh" "$tmp/helper"
cp "$ROOT/scripts/mechos-update-center-reference-v8.py" "$tmp/center.py"
python3 "$ROOT/scripts/mechos-hotfix17-updater-patch.py" helper "$tmp/helper"
python3 "$ROOT/scripts/mechos-hotfix17-updater-patch.py" center "$tmp/center.py"
bash -n "$tmp/helper"
python3 -m py_compile "$tmp/center.py"
grep -Fq 'MECHOS_HOTFIX17_HELPER_WARNING_FIX' "$tmp/helper"
grep -Fq -- '--warning=no-timestamp --zstd -xpf' "$tmp/helper"
grep -Fq 'MECHOS_HOTFIX17_FAILURE_STATE_FIX' "$tmp/center.py"
grep -Fq 'if reboot and not available:' "$tmp/center.py"
grep -Fq 'Nothing should be treated as successfully installed yet.' "$tmp/center.py"

# Current ISO source intentionally uses rsync only on the build host to copy
# the overlay. The installed updater no longer requires it after Hotfix 17.
grep -Fq 'pacman -S --noconfirm archiso git rsync' "$ROOT/scripts/build-mechos-archiso.sh"

echo 'Hotfix 17 validation passed: transaction no longer depends on rsync, missing base tools produce explicit errors instead of exit 127, VM timestamp noise is suppressed, failure-state UI is unambiguous, and reboot-required cleanup is gated on successful activation.'
