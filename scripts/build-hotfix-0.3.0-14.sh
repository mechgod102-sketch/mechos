#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.14-update.tar.zst"
SUM="$BUNDLE.sha256"; MANIFEST="$ROOT/updates/stable.json"
mkdir -p \
  "$STAGE/usr/local/bin" "$STAGE/usr/local/libexec" "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/lib/systemd/system" "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$(dirname "$BUNDLE")"

# Immediate replacements. In particular mechos-reboot is replaced as soon as
# the update bundle is extracted, so the Restart button that completes Hotfix14
# uses the repaired direct-logind path rather than the old Plasma logout route.
install -m0755 "$ROOT/scripts/mechos-reboot-v14.sh" "$STAGE/usr/local/bin/mechos-reboot"
install -m0755 "$ROOT/src/mechos_ui/stream_center_v14.py" "$STAGE/usr/local/bin/mechos-stream-center"
install -m0755 "$ROOT/scripts/mechos-mechscope-update-notify-v14.sh" "$STAGE/usr/local/bin/mechos-mechscope-update-check"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py" "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
install -m0755 "$ROOT/scripts/mechos-performance-center-v13.py" "$STAGE/usr/local/bin/mechos-performance-center"
cat >"$STAGE/usr/local/bin/mechos-update-center" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/update-center-v14-launch.log"
mkdir -p "$(dirname "$LOG")"
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@" >>"$LOG" 2>&1
EOF
chmod 0755 "$STAGE/usr/local/bin/mechos-update-center"

for f in fixed_canvas.py quick_actions_shell.py recovery_shell.py update_shell.py performance_shell.py; do
  install -m0644 "$ROOT/src/mechos_ui/$f" "$STAGE/usr/local/share/mechos/ui/$f"
done

# Runtime patch + next-boot activation. Generated owners such as MechScope,
# Creator Mode and Recovery Center are patched against the exact installed copy
# after the user explicitly chooses Restart.
install -m0755 "$ROOT/scripts/mechos-hotfix14-runtime-patch.py" "$STAGE/usr/local/libexec/mechos-hotfix14-runtime-patch"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-14-apply.sh" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-14-apply"
cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-14.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 14 visual and session repairs
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-14-applied
[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-14-apply
[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-14.service "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-14.service"

# Bundle gates.
bash -n "$STAGE/usr/local/bin/mechos-reboot"
bash -n "$STAGE/usr/local/bin/mechos-mechscope-update-check"
bash -n "$STAGE/usr/local/bin/mechos-update-center"
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-14-apply"
python3 -m py_compile \
  "$STAGE/usr/local/bin/mechos-stream-center" \
  "$STAGE/usr/local/libexec/mechos-update-center-v8.py" \
  "$STAGE/usr/local/bin/mechos-performance-center" \
  "$STAGE/usr/local/libexec/mechos-hotfix14-runtime-patch" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/quick_actions_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/recovery_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/update_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/performance_shell.py"
grep -Fq 'MECHOS_REBOOT_V14' "$STAGE/usr/local/bin/mechos-reboot"
grep -Fq 'MECHOS_STREAM_CENTER_VISUAL_V14' "$STAGE/usr/local/bin/mechos-stream-center"
grep -Fq 'MECHOS_HOTFIX14_ESCAPE_BACK_STREAMCENTER' "$STAGE/usr/local/bin/mechos-stream-center"
grep -Fq 'MECHOS_MECHSCOPE_UPDATE_NOTIFY_V14' "$STAGE/usr/local/bin/mechos-mechscope-update-check"
grep -Fq 'MECHOS_QUICK_ACTIONS_VISUAL_V14' "$STAGE/usr/local/share/mechos/ui/quick_actions_shell.py"
grep -Fq 'MECHOS_RECOVERY_VISUAL_V14' "$STAGE/usr/local/share/mechos/ui/recovery_shell.py"
grep -Fq 'MECHOS_VISUAL_SURFACES_V14_FIXED_CANVAS' "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"
grep -Fq 'MECHOS_HOTFIX14_ESCAPE_BACK_CREATOR' "$STAGE/usr/local/libexec/mechos-hotfix14-runtime-patch"
grep -Fq 'MECHOS_HOTFIX14_CREATOR_DIRECT_V1' "$STAGE/usr/local/libexec/mechos-hotfix14-runtime-patch"
grep -Fq 'MECHOS_HOTFIX14_REAL_PROGRAM_ICONS_CREATOR' "$STAGE/usr/local/libexec/mechos-hotfix14-runtime-patch"
grep -Fq 'MECHOS_HOTFIX14_REAL_PROGRAM_ICONS_STORE' "$STAGE/usr/local/libexec/mechos-hotfix14-runtime-patch"
grep -Fq 'QIcon.fromTheme' "$STAGE/usr/local/libexec/mechos-hotfix14-runtime-patch"
# Updates may require a restart but must never perform one automatically.
for bad in 'shutdown -r' 'reboot -f' '/sbin/reboot'; do
  ! grep -R -Fq "$bad" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-14-apply"
done

rm -f "$BUNDLE" "$SUM"
tar --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE"|awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"
python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
 'schema':1,'channel':'stable','version':'0.3.0-hotfix.14','release_name':'MechOS v0.3.0 Hotfix 14',
 'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
 'notes':'Visual, navigation and session-stability hotfix. Redesigns and widens Quick Actions so controls no longer clip; refreshes Recovery Center visuals; replaces the small desktop Stream Center with a responsive fullscreen MechOS surface; explicitly paints dark backing pixels to eliminate white GUI margins; replaces the Restart button backend with a direct logind-first reboot path to avoid the blank/white Plasma logout transition; makes MechScope automatically check for updates once per gaming session and display a desktop notification only when updates are available; keeps MechScope alive behind Creator Mode so Creator no longer dumps the user to Plasma; adds Escape/back navigation across Quick Actions, Unified Store, Creator Mode, Recovery, Performance, Update Center and Stream Center; and uses each locally installed program/Flatpak actual desktop/theme icon in Creator Mode, Creator Store and Unified Store instead of imitation logo glyphs when that real icon is available. Updates remain manual and never reboot, log out or power off automatically.',
 'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.14-update.tar.zst',
 'bundle_sha256':sha,'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 14 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
