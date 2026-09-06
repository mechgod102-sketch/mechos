#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/src/mechos_ui/creator_real_icons_v22.py"
PATCH="$ROOT/scripts/mechos-creator-real-icons-owner-v22-patch.py"
RUNTIME="$ROOT/scripts/mechos-mechscope-runtime-v23.py"
UPDATE_CENTER="$ROOT/scripts/mechos-update-center-reference-v8.py"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-22-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-22.sh"
H15APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-15-apply.sh"
MODE19="$ROOT/scripts/mechos-mode-launch-v19.sh"
ROUTE19="$ROOT/scripts/mechos-shell-route-v19.sh"
HELPER19="$ROOT/scripts/mechos-update-helper-v19.sh"

python3 -m py_compile "$MODULE" "$PATCH" "$RUNTIME" "$UPDATE_CENTER"
bash -n "$APPLY" "$BUILD" "$H15APPLY" "$MODE19" "$ROUTE19" "$HELPER19"

for token in \
  MECHOS_CREATOR_REAL_ICONS_V22 \
  QIcon.fromTheme \
  /usr/share/applications \
  /var/lib/flatpak/exports/share/applications \
  /var/lib/flatpak/appstream; do
  grep -Fq "$token" "$MODULE"
done

grep -Fq 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' "$PATCH"
grep -Fq 'icons.install(shell)' "$PATCH"

# Hotfix17 behavior must now be source-owned so cumulative recovery never needs
# to replay its historical text patcher over a newer Update Center.
grep -Fq 'MECHOS_HOTFIX17_FAILURE_STATE_FIX' "$UPDATE_CENTER"
grep -Fq 'if reboot and not available:' "$UPDATE_CENTER"
grep -Fq 'Nothing should be treated as successfully installed yet.' "$UPDATE_CENTER"

# Regression gate for the VM clean-exit failure: the generated owner can
# terminate a historical startup path with rc=0, while the stable runtime must
# still instantiate MechScope and enter the Qt event loop.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/fake/PyQt6"
cat >"$TMP/fake/PyQt6/__init__.py" <<'PY'
PY
cat >"$TMP/fake/PyQt6/QtWidgets.py" <<'PY'
import time
class QApplication:
    _instance = None
    def __init__(self, args):
        type(self)._instance = self
    @classmethod
    def instance(cls):
        return cls._instance
    def exec(self):
        time.sleep(5)
        return 0
PY
cat >"$TMP/owner.py" <<PY
from pathlib import Path
class MechScope:
    def showFullScreen(self):
        Path(r"$TMP/shown").write_text("shown", encoding="utf-8")
raise SystemExit(0)
PY

set +e
PYTHONPATH="$TMP/fake" \
MECHOS_MECHSCOPE_OWNER="$TMP/owner.py" \
MECHOS_MECHSCOPE_RUNTIME_LOG="$TMP/runtime.log" \
timeout 1s python3 "$RUNTIME"
rc=$?
set -e
[ "$rc" -eq 124 ] || {
  echo "MechScope persistent runtime exited before the event loop stayed active (rc=$rc)" >&2
  cat "$TMP/runtime.log" >&2 2>/dev/null || true
  exit 1
}
[ -s "$TMP/shown" ] || { echo 'MechScope persistent runtime never showed the primary window' >&2; exit 1; }
grep -Fq 'ignored legacy clean SystemExit' "$TMP/runtime.log"
grep -Fq 'running MechScope' "$TMP/runtime.log"

# Hotfix15 compatibility remains required for direct Hotfix14 recovery.
grep -Fq 'MECHOS_HOTFIX15_CUMULATIVE_STORE_DEFER_V22' "$H15APPLY"
grep -Fq 'deferring full Store replacement to cumulative Hotfix21' "$H15APPLY"

for token in \
  MECHOS_MODE_LAUNCH_V15 \
  MECHOS_MODE_LAUNCH_V16 \
  MECHOS_MODE_LAUNCH_V19; do
  grep -Fq "$token" "$MODE19"
done
grep -Fq 'MECHOS_SHELL_ROUTE_V19' "$ROUTE19"
grep -Fq 'MECHOS_HOTFIX17_HELPER_WARNING_FIX' "$HELPER19"

# Hotfix22.4 must not replay the old updater patchers. It runs 15/16 only when
# missing, reconciles 17-20 from final contracts, then runs Store-owner Hotfix21.
grep -Fq 'MECHOS_HOTFIX22_APPLY_V6' "$APPLY"
grep -Fq 'MECHOS_HOTFIX22_FINAL_STATE_RECONCILE_V24' "$APPLY"
grep -Fq 'apply_legacy_layer 15' "$APPLY"
grep -Fq 'apply_legacy_layer 16' "$APPLY"
grep -Fq 'Reconciling cumulative Hotfix 17 from final installed state' "$APPLY"
grep -Fq 'Reconciling cumulative Hotfix 18 from final installed state' "$APPLY"
grep -Fq 'Reconciling cumulative Hotfix 19 from final installed state' "$APPLY"
grep -Fq 'Reconciling cumulative Hotfix 20 from final installed state' "$APPLY"
grep -Fq 'apply_legacy_layer 21' "$APPLY"
! grep -Fq 'apply_legacy_layer 17' "$APPLY"
! grep -Fq 'apply_legacy_layer 18' "$APPLY"
! grep -Fq 'apply_legacy_layer 19' "$APPLY"
! grep -Fq 'apply_legacy_layer 20' "$APPLY"
grep -Fq 'MECHOS_HOTFIX17_FAILURE_STATE_FIX' "$APPLY"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' "$APPLY"
grep -Fq 'MECHOS_HOTFIX22_3_MECHSCOPE_PERSISTENT_RUNTIME' "$APPLY"
grep -Fq 'mechscope-owner-v23.py' "$APPLY"
grep -Fq 'hotfix-0.3.0-22.4-applied' "$APPLY"
grep -Fq "printf '0.3.0-hotfix.22.4" "$APPLY"

grep -Fq 'MechOS-0.3.0-hotfix.21-update.tar.zst' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.22.4-update.tar.zst' "$BUILD"
grep -Fq 'mechos-update-center-reference-v8.py' "$BUILD"
grep -Fq 'MECHOS_HOTFIX17_FAILURE_STATE_FIX' "$BUILD"
grep -Fq 'mechos-mechscope-runtime-v23.py' "$BUILD"
grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_V23' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.22.4'" "$BUILD"
grep -Fq 'ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-22.4-applied' "$BUILD"
! grep -Fq 'Requires=mechos-hotfix-0.3.0-21.service' "$BUILD"
! grep -Fq 'ConditionPathExists=/var/lib/mechos/installed' "$BUILD"

echo 'Hotfix 22.4 final-state reconciliation + MechScope persistent runtime validation passed.'
