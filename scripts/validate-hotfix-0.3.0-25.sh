#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX25_UPDATE_OOBE_RECOVERY_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in \
  "$ROOT/scripts/mechos-update-transaction-v25.sh" \
  "$ROOT/scripts/mechos-update-helper-v25.sh" \
  "$ROOT/scripts/mechos-oobe-rearm-v25.sh" \
  "$ROOT/scripts/mechos-hotfix-0.3.0-25-apply.sh" \
  "$ROOT/scripts/build-hotfix-0.3.0-25.sh"; do
  bash -n "$f"
done

TX="$ROOT/scripts/mechos-update-transaction-v25.sh"
HELPER="$ROOT/scripts/mechos-update-helper-v25.sh"
REARM="$ROOT/scripts/mechos-oobe-rearm-v25.sh"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-25-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-25.sh"

grep -Fq 'MECHOS_UPDATE_TRANSACTION_V25_RELEASE_COMMIT_V1' "$TX"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' "$TX"
grep -Fq 'restore_root' "$TX"
grep -Fq 'etc/mechos/release' "$TX"
grep -Fq 'mv -f "$RELEASE_TMP" "$RELEASE"' "$TX"
grep -Fq 'release commit verification failed' "$TX"
grep -Fq 'transaction committed for $VERSION; release marker verified' "$TX"

grep -Fq 'MECHOS_UPDATE_HELPER_V25_RELEASE_COMMIT_V1' "$HELPER"
grep -Fq 'commit_release_version "$latest"' "$HELPER"
grep -Fq 'MECHOS_RELEASE_COMMITTED=' "$HELPER"
grep -Fq '"$stage/usr/local/libexec/mechos-update-transaction-v14"' "$HELPER"

grep -Fq 'MECHOS_OOBE_REARM_V25' "$REARM"
grep -Fq '[ ! -f "$STATE/oobe-complete" ] || exit 0' "$REARM"
grep -Fq 'passwd -d "$SETUP_USER"' "$REARM"
grep -Fq 'gpasswd -d "$SETUP_USER" wheel' "$REARM"
grep -Fq 'User=mechos-setup' "$REARM"
grep -Fq 'Relogin=false' "$REARM"
grep -Fq 'ConditionPathExists=!/var/lib/mechos/oobe-complete' "$REARM"

grep -Fq 'MECHOS_HOTFIX25_UPDATE_OOBE_RECOVERY_V1' "$APPLY"
grep -Fq 'Session=mechscope.desktop' "$APPLY"
grep -Fq '"$REARM"' "$APPLY"

grep -Fq "version':'0.3.0-hotfix.25" "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.24-update.tar.zst' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.25-update.tar.zst' "$BUILD"
grep -Fq 'mechos-update-transaction-v25.sh' "$BUILD"
grep -Fq '"$STAGE/usr/local/libexec/mechos-update-transaction-v14"' "$BUILD"
grep -Fq 'mechos-oobe-rearm-v25.service' "$BUILD"
grep -Fq 'ConditionPathExists=!/var/lib/mechos/oobe-complete' "$BUILD"
grep -Fq 'requires_reboot' "$BUILD"

# Ordering regression: release write must happen after updater and MechScope
# postflight checks, not before them.
python3 - "$TX" <<'PY'
from pathlib import Path
import sys
t=Path(sys.argv[1]).read_text()
post=t.index("[ -x /usr/local/bin/mechos-performance-center ]")
commit=t.index('mv -f "$RELEASE_TMP" "$RELEASE"')
verified=t.index('release marker verified')
assert post < commit < verified
PY

printf 'Hotfix 25 source validation passed.\n'
