#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX14_APPLY_V2
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-14-applied"
LOG=/var/log/mechos-hotfix-0.3.0-14.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 14 apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

PATCH=/usr/local/libexec/mechos-hotfix14-runtime-patch
[ -x "$PATCH" ] || { echo 'ERROR: Hotfix14 runtime patch missing'; exit 81; }

# Quick Actions: widen the real outer window and make Escape close the overlay.
[ -f /usr/local/bin/mechos-quick-actions ] || { echo 'ERROR: Quick Actions owner missing'; exit 82; }
python3 "$PATCH" quick /usr/local/bin/mechos-quick-actions
python3 - <<'PY'
from pathlib import Path
p=Path('/usr/local/bin/mechos-quick-actions'); compile(p.read_text(encoding='utf-8'),str(p),'exec')
t=p.read_text(encoding='utf-8'); assert 'MECHOS_HOTFIX14_QUICK_WINDOW_V1' in t and 'MECHOS_HOTFIX14_ESCAPE_BACK_QUICK' in t
PY

# MechScope: dark backing, one update check per gaming session, notification
# when updates exist, and Escape/back from the separate Unified Store.
TARGET=/usr/local/bin/mechscope
[ -f /usr/local/bin/mechscope.real ] && TARGET=/usr/local/bin/mechscope.real
[ -f "$TARGET" ] || { echo 'ERROR: MechScope implementation missing'; exit 83; }
python3 "$PATCH" mechscope "$TARGET"
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); compile(p.read_text(encoding='utf-8'),str(p),'exec')
t=p.read_text(encoding='utf-8'); assert 'MECHOS_HOTFIX14_UPDATE_CHECK_V1' in t and 'MECHOS_HOTFIX14_ESCAPE_BACK_STORE' in t
PY

# Creator transition: never close MechScope first. Creator runs above it, so
# Escape can return to the prior MechScope surface instead of revealing Plasma.
[ -f /usr/local/bin/mechos-mode-launch ] || { echo 'ERROR: mode launcher missing'; exit 84; }
python3 "$PATCH" mode-launch /usr/local/bin/mechos-mode-launch
bash -n /usr/local/bin/mechos-mode-launch
grep -Fq 'MECHOS_HOTFIX14_CREATOR_DIRECT_V1' /usr/local/bin/mechos-mode-launch

# Back-navigation policy for standalone fullscreen centers. Escape returns to
# the previous surface by closing only the foreground window. Creator uses its
# Dashboard as the first back target, then closes to MechScope on the next Esc.
[ -f /usr/local/bin/mechos-creator-mode ] && python3 "$PATCH" creator /usr/local/bin/mechos-creator-mode
[ -f /usr/local/bin/mechos-recovery-center ] && python3 "$PATCH" escape /usr/local/bin/mechos-recovery-center Recovery
[ -f /usr/local/bin/mechos-performance-center ] && python3 "$PATCH" escape /usr/local/bin/mechos-performance-center PerformanceCenter
[ -f /usr/local/libexec/mechos-update-center-v8.py ] && python3 "$PATCH" escape /usr/local/libexec/mechos-update-center-v8.py UpdateCenter

# Validate the immediately replaced visual/session surfaces.
for f in \
  /usr/local/bin/mechos-reboot \
  /usr/local/bin/mechos-stream-center \
  /usr/local/bin/mechos-mechscope-update-check \
  /usr/local/share/mechos/ui/fixed_canvas.py \
  /usr/local/share/mechos/ui/quick_actions_shell.py \
  /usr/local/share/mechos/ui/recovery_shell.py; do
  [ -e "$f" ] || { echo "ERROR: missing Hotfix14 surface $f"; exit 85; }
done
bash -n /usr/local/bin/mechos-reboot
bash -n /usr/local/bin/mechos-mechscope-update-check
python3 - <<'PY'
from pathlib import Path
for name in [
 '/usr/local/bin/mechos-stream-center',
 '/usr/local/share/mechos/ui/fixed_canvas.py',
 '/usr/local/share/mechos/ui/quick_actions_shell.py',
 '/usr/local/share/mechos/ui/recovery_shell.py',
 '/usr/local/libexec/mechos-update-center-v8.py',
 '/usr/local/bin/mechos-performance-center',
]:
 p=Path(name)
 if p.is_file(): compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY

# Updates themselves must never reboot/log out/power off. Hotfix14 repairs only
# the user-invoked Restart button via /usr/local/bin/mechos-reboot.
for bad in 'shutdown -r' 'reboot -f' '/sbin/reboot'; do
  ! grep -Fq "$bad" /usr/local/bin/mechos-update-helper || { echo "ERROR: automatic reboot command in updater: $bad"; exit 86; }
done

mkdir -p /etc/mechos
printf '0.3.0-hotfix.14\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.14/' /etc/mechos/mechos.conf; else printf 'MECHOS_VERSION=0.3.0-hotfix.14\n' >>/etc/mechos/mechos.conf; fi
fi
printf 'MechOS v0.3.0 Hotfix 14\n' >/etc/system-release
touch "$MARKER"
echo "[$(date -Is)] Hotfix14 applied: dark restart path, responsive Quick Actions, Recovery v14, fullscreen Stream Center, MechScope boot update notification, safe Creator transition, and Escape back navigation active."
