#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX15_APPLY_V1
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-15-applied"
LOG=/var/log/mechos-hotfix-0.3.0-15.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 15 apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

for f in \
  /usr/local/bin/mechos-mode-launch \
  /usr/local/libexec/mechos-mode-launch-base-v15 \
  /usr/local/libexec/mechos-hotfix15-runtime-patch; do
  [ -x "$f" ] || { echo "ERROR: Hotfix15 component missing: $f"; exit 90; }
done
bash -n /usr/local/bin/mechos-mode-launch
bash -n /usr/local/libexec/mechos-mode-launch-base-v15

grep -Fq 'MECHOS_MODE_LAUNCH_V15' /usr/local/bin/mechos-mode-launch
grep -Fq 'MECHOS_CREATOR_HANDOFF_V15' /usr/local/bin/mechos-mode-launch
grep -Fq 'MECHOS_CREATOR_VM_OVERLAY_V15' /usr/local/bin/mechos-mode-launch

# Creator Mode must exist and be syntactically healthy before the handoff is
# accepted. This prevents a mode switch from hiding MechScope when Creator is
# absent or already broken.
[ -x /usr/local/bin/mechos-creator-mode ] || { echo 'ERROR: Creator Mode executable missing'; exit 91; }
if [ -f /usr/local/bin/mechos-creator-mode.real ]; then
  python3 - <<'PY'
from pathlib import Path
p=Path('/usr/local/bin/mechos-creator-mode.real')
compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
elif head -n1 /usr/local/bin/mechos-creator-mode | grep -q python; then
  python3 - <<'PY'
from pathlib import Path
p=Path('/usr/local/bin/mechos-creator-mode')
compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
fi

for unit in \
  /usr/lib/systemd/user/mechos-creator-mode.service \
  /usr/lib/systemd/user/mechos-vm-creator.service; do
  [ -f "$unit" ] || { echo "ERROR: Creator user service missing: $unit"; exit 92; }
  grep -Fq 'ExecStart=/usr/local/bin/mechos-creator-mode' "$unit"
done

# Patch the installed Unified Store owner. Hotfix 15 removes xdg-open from the
# user-facing browse/search actions so store navigation stays in Steam/Heroic.
TARGET=/usr/local/bin/mechscope
[ -f /usr/local/bin/mechscope.real ] && TARGET=/usr/local/bin/mechscope.real
[ -f "$TARGET" ] || { echo 'ERROR: MechScope implementation missing'; exit 93; }
python3 /usr/local/libexec/mechos-hotfix15-runtime-patch store "$TARGET"
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
compile(t,str(p),'exec')
assert 'MECHOS_HOTFIX15_NATIVE_UNIFIED_STORE' in t
assert "spawn(['xdg-open', url.format(query=self.query())])" not in t
assert "spawn(['xdg-open', url.format(query=q)])" not in t
PY

# The v15 Creator path is intentionally an overlay. It must not delegate the
# Creator transition to the old VM runtime because that runtime stops MechScope.
! grep -Eq 'mechos-vm-mode-runtime[[:space:]]+creator' /usr/local/bin/mechos-mode-launch

mkdir -p /etc/mechos
printf '0.3.0-hotfix.15\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.15/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.15\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 15\n' >/etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix15 applied: Creator starts and is health-checked above MechScope; VM Creator uses software rendering without stopping MechScope; Unified Store uses native Steam/Heroic launch paths instead of the desktop browser."
