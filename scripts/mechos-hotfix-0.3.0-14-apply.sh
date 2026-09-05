#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX14_APPLY_V1
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

# Patch the installed Quick Actions owner so its outer window is wide enough to
# show the responsive v14 source shell without clipped text.
[ -f /usr/local/bin/mechos-quick-actions ] || { echo 'ERROR: Quick Actions owner missing'; exit 82; }
python3 "$PATCH" quick /usr/local/bin/mechos-quick-actions
python3 - <<'PY'
from pathlib import Path
p=Path('/usr/local/bin/mechos-quick-actions'); compile(p.read_text(encoding='utf-8'),str(p),'exec')
assert 'MECHOS_HOTFIX14_QUICK_WINDOW_V1' in p.read_text(encoding='utf-8')
PY

# Patch the real MechScope implementation: dark backing surface plus one update
# check per gaming session. The helper emits a desktop notification only when
# an update is actually available.
TARGET=/usr/local/bin/mechscope
[ -f /usr/local/bin/mechscope.real ] && TARGET=/usr/local/bin/mechscope.real
[ -f "$TARGET" ] || { echo 'ERROR: MechScope implementation missing'; exit 83; }
python3 "$PATCH" mechscope "$TARGET"
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); compile(p.read_text(encoding='utf-8'),str(p),'exec')
assert 'MECHOS_HOTFIX14_UPDATE_CHECK_V1' in p.read_text(encoding='utf-8')
PY

# Creator Mode transition must not kill MechScope first and expose Plasma.
# Creator is launched and health-checked first; MechScope closes only after the
# Creator window has remained alive for three seconds.
[ -f /usr/local/bin/mechos-mode-launch ] || { echo 'ERROR: mode launcher missing'; exit 84; }
python3 "$PATCH" mode-launch /usr/local/bin/mechos-mode-launch
bash -n /usr/local/bin/mechos-mode-launch
grep -Fq 'MECHOS_HOTFIX14_CREATOR_DIRECT_V1' /usr/local/bin/mechos-mode-launch

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
]:
 p=Path(name); compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY

# Updates themselves must never reboot/log out/power off. Hotfix14 only repairs
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
echo "[$(date -Is)] Hotfix14 applied: dark restart path, responsive Quick Actions, Recovery v14, fullscreen Stream Center, MechScope boot update notification, and safe Creator transition active."
