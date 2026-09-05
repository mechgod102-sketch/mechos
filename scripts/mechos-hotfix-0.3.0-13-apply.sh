#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX13_STABILITY_APPLY_V1
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-13-applied"
LOG=/var/log/mechos-hotfix-0.3.0-13.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 13 apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

# Patch the actual installed MechScope implementation, not a build-time copy.
TARGET=/usr/local/bin/mechscope
if [ -f /usr/local/bin/mechscope.real ]; then TARGET=/usr/local/bin/mechscope.real; fi
[ -f "$TARGET" ] || { echo 'ERROR: MechScope implementation missing'; exit 71; }
python3 /usr/local/libexec/mechos-hotfix13-mechscope-patch "$TARGET"
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); compile(p.read_text(encoding='utf-8'),str(p),'exec')
t=p.read_text(encoding='utf-8')
for marker in ('MECHOS_HOTFIX13_FULLSCREEN_STORE_V1','MECHOS_HOTFIX13_STORE_PROCESS_V1'):
    if marker not in t: raise SystemExit(f'MechScope marker missing: {marker}')
PY
chmod 0755 "$TARGET"

# Install the future-update transaction policy into the helper. This affects
# later updates; Hotfix 13 itself was already checksum-verified by the older
# updater before this service runs.
[ -x /usr/local/bin/mechos-update-helper ] || { echo 'ERROR: update helper missing'; exit 72; }
python3 /usr/local/libexec/mechos-update-helper-v13-patch /usr/local/bin/mechos-update-helper
bash -n /usr/local/bin/mechos-update-helper
for bad in 'systemctl reboot' 'shutdown -r' 'reboot -f' '/sbin/reboot'; do
  ! grep -Fq "$bad" /usr/local/bin/mechos-update-helper || { echo "ERROR: automatic reboot command found: $bad"; exit 73; }
done

# Validate all system surfaces that Hotfix 13 protects.
[ -x /usr/local/bin/mechos-update-center ] || { echo 'ERROR: Update Center launcher missing'; exit 74; }
[ -x /usr/local/bin/mechos-performance-center ] || { echo 'ERROR: Performance Center launcher missing'; exit 75; }
[ -x /usr/local/libexec/mechos-update-transaction-v13 ] || { echo 'ERROR: transaction engine missing'; exit 76; }
python3 - <<'PY'
from pathlib import Path
for name in ['/usr/local/libexec/mechos-update-center-v8.py','/usr/local/bin/mechos-performance-center']:
    p=Path(name)
    compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
status="$(timeout 8 /usr/local/bin/mechos-update-helper status 2>&1)"
printf '%s\n' "$status" | grep -q '^CURRENT_MECHOS_VERSION='
printf '%s\n' "$status" | grep -q '^REBOOT_REQUIRED='

mkdir -p /etc/mechos
printf '0.3.0-hotfix.13\n' > /etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.13/' /etc/mechos/mechos.conf; else printf 'MECHOS_VERSION=0.3.0-hotfix.13\n' >>/etc/mechos/mechos.conf; fi
fi
printf 'MechOS v0.3.0 Hotfix 13\n' >/etc/system-release
touch "$MARKER"
echo "[$(date -Is)] Hotfix 13 applied. Update transactions protected; Update Center and Performance Center validated; MechScope fullscreen/store patch active."
