#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

for f in \
  scripts/mechos-reboot-v14.sh \
  scripts/mechos-update-helper-v14.sh \
  scripts/mechos-update-guard-v14.sh \
  scripts/mechos-update-transaction-v13.sh \
  scripts/mechos-mechscope-update-notify-v14.sh \
  scripts/mechos-hotfix-0.3.0-14-apply.sh \
  scripts/build-hotfix-0.3.0-14.sh; do
  bash -n "$ROOT/$f"
done
python3 -m py_compile \
  "$ROOT/src/mechos_ui/stream_center_v14.py" \
  "$ROOT/src/mechos_ui/fixed_canvas.py" \
  "$ROOT/src/mechos_ui/quick_actions_shell.py" \
  "$ROOT/src/mechos_ui/recovery_shell.py" \
  "$ROOT/scripts/mechos-hotfix14-runtime-patch.py"

grep -Fq 'WA_OpaquePaintEvent' "$ROOT/src/mechos_ui/fixed_canvas.py"
grep -Fq "fillRect(self.rect(), QColor('#020611'))" "$ROOT/src/mechos_ui/fixed_canvas.py"
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_FIXED_CANVAS' "$ROOT/src/mechos_ui/fixed_canvas.py"
grep -Fq 'MECHOS_QUICK_ACTIONS_VISUAL_V14' "$ROOT/src/mechos_ui/quick_actions_shell.py"
grep -Fq 'MECHOS_QUICK_ACTIONS_VISUAL_V9' "$ROOT/src/mechos_ui/quick_actions_shell.py"
grep -Fq 'MECHOS_RECOVERY_VISUAL_V14' "$ROOT/src/mechos_ui/recovery_shell.py"
grep -Fq 'MECHOS_STREAM_CENTER_VISUAL_V14' "$ROOT/src/mechos_ui/stream_center_v14.py"
grep -Fq 'MECHOS_HOTFIX14_ESCAPE_BACK_STREAMCENTER' "$ROOT/src/mechos_ui/stream_center_v14.py"
grep -Fq 'org.freedesktop.login1.Manager Reboot' "$ROOT/scripts/mechos-reboot-v14.sh"
grep -Fq 'MECHOS_UPDATE_HELPER_V14' "$ROOT/scripts/mechos-update-helper-v14.sh"
grep -Fq 'MECHOS_UPDATE_GUARD_V14' "$ROOT/scripts/mechos-update-guard-v14.sh"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V13' "$ROOT/scripts/mechos-update-transaction-v13.sh"
grep -Fq 'sha256sum -c' "$ROOT/scripts/mechos-update-helper-v14.sh"
grep -Fq 'validate_bundle' "$ROOT/scripts/mechos-update-helper-v14.sh"
grep -Fq 'mechos-update-helper-v14' "$ROOT/scripts/mechos-update-guard-v14.sh"
grep -Fq 'mechos-update-center-launcher-v14' "$ROOT/scripts/mechos-update-guard-v14.sh"
grep -Fq 'mechos-update-guard-v14.service' "$ROOT/scripts/build-hotfix-0.3.0-14.sh"
grep -Fq 'mechos-update-helper-v14.sh' "$ROOT/scripts/build-hotfix-0.3.0-14.sh"
grep -Fq 'MECHOS_MECHSCOPE_UPDATE_NOTIFY_V14' "$ROOT/scripts/mechos-mechscope-update-notify-v14.sh"
grep -Fq 'notify-send' "$ROOT/scripts/mechos-mechscope-update-notify-v14.sh"
grep -Fq 'MECHOS_HOTFIX14_REAL_PROGRAM_ICONS_CREATOR' "$ROOT/scripts/mechos-hotfix14-runtime-patch.py"
grep -Fq 'MECHOS_HOTFIX14_REAL_PROGRAM_ICONS_STORE' "$ROOT/scripts/mechos-hotfix14-runtime-patch.py"
grep -Fq 'QIcon.fromTheme' "$ROOT/scripts/mechos-hotfix14-runtime-patch.py"
grep -Fq 'MechScope preserved for Escape/back navigation' "$ROOT/scripts/mechos-hotfix14-runtime-patch.py"

# Update installation and the self-healing guard must never trigger reboot,
# logout or poweroff. The separate explicit mechos-reboot helper is excluded.
for f in \
  "$ROOT/scripts/mechos-update-helper-v14.sh" \
  "$ROOT/scripts/mechos-update-guard-v14.sh" \
  "$ROOT/scripts/mechos-update-transaction-v13.sh" \
  "$ROOT/scripts/mechos-hotfix-0.3.0-14-apply.sh"; do
  ! grep -Eq '(^|[;&|[:space:]])systemctl[[:space:]]+reboot([;&|[:space:]]|$)' "$f"
  ! grep -Eq '(^|[;&|[:space:]])shutdown[[:space:]]+-r([;&|[:space:]]|$)' "$f"
  ! grep -Eq '(^|[;&|[:space:]])reboot[[:space:]]+-f([;&|[:space:]]|$)' "$f"
  ! grep -Eq '(^|[;&|[:space:]])loginctl[[:space:]]+terminate-session([;&|[:space:]]|$)' "$f"
done

# Exercise runtime patching against realistic parenthesized class fixtures so
# changes to method/class insertion cannot silently produce invalid installed
# Python or shell files.
cat >"$TMP/quick.py" <<'PY'
class QuickActions(object):
    def __init__(self):
        self.setStyleSheet(STYLE)
        self.setFixedWidth(470)
        self.build()

        screen = QApplication.primaryScreen().availableGeometry()
        self.setGeometry(screen.right() - self.width() + 1, screen.top(), self.width(), screen.height())
    def build(self): pass
PY
python3 "$ROOT/scripts/mechos-hotfix14-runtime-patch.py" quick "$TMP/quick.py"
python3 -m py_compile "$TMP/quick.py"
grep -Fq 'MECHOS_HOTFIX14_ESCAPE_BACK_QUICK' "$TMP/quick.py"

cat >"$TMP/creator.py" <<'PY'
class Creator(object):
    def __init__(self):
        self.stack=None
        self.build()
        self.timer=QTimer(self)
    def build(self): pass
    def select(self,i): pass
PY
python3 "$ROOT/scripts/mechos-hotfix14-runtime-patch.py" creator "$TMP/creator.py"
python3 -m py_compile "$TMP/creator.py"
grep -Fq 'MECHOS_HOTFIX14_REAL_PROGRAM_ICONS_CREATOR' "$TMP/creator.py"
grep -Fq 'MECHOS_HOTFIX14_ESCAPE_BACK_CREATOR' "$TMP/creator.py"

cat >"$TMP/mechscope.py" <<'PY'
class UnifiedStore(object):
    def __init__(self):
        self.ready=True
    def open_selected_launcher(self): pass
class MechScope(object):
    def __init__(self): pass
    def build_ui(self):
        self.ready=True
PY
python3 "$ROOT/scripts/mechos-hotfix14-runtime-patch.py" mechscope "$TMP/mechscope.py"
python3 -m py_compile "$TMP/mechscope.py"
grep -Fq 'MECHOS_HOTFIX14_ESCAPE_BACK_STORE' "$TMP/mechscope.py"
grep -Fq 'MECHOS_HOTFIX14_REAL_PROGRAM_ICONS_STORE' "$TMP/mechscope.py"

cat >"$TMP/mode-launch" <<'SH'
#!/usr/bin/env bash
MODE="${1:-}"
STATE_DIR="${HOME}/.local/state/mechos"
log(){ :; }
notify_error(){ :; }
case "$MODE" in gaming|mechscope|creator|desktop) ;; *) echo 'Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}' >&2; exit 2 ;; esac
exit 0
SH
python3 "$ROOT/scripts/mechos-hotfix14-runtime-patch.py" mode-launch "$TMP/mode-launch"
bash -n "$TMP/mode-launch"
grep -Fq 'MECHOS_HOTFIX14_CREATOR_DIRECT_V1' "$TMP/mode-launch"

echo 'Hotfix 14 source/regression validation passed.'
