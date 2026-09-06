#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX21_APPLY_V1
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-21-applied"
LOG=/var/log/mechos-hotfix-0.3.0-21.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 21 apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

PATCH=/usr/local/libexec/mechos-hotfix21-unified-store-patch
CATALOG=/usr/local/libexec/mechos-game-catalog-v15
BOOTSTRAP=/usr/local/libexec/mechos-provider-bootstrap-v15
for f in "$PATCH" "$CATALOG" "$BOOTSTRAP"; do
  [ -x "$f" ] || { echo "ERROR: Hotfix 21 component missing: $f"; exit 90; }
done
python3 -m py_compile "$PATCH" "$CATALOG"
bash -n "$BOOTSTRAP"

TARGET=/usr/local/bin/mechscope
[ -f /usr/local/bin/mechscope.real ] && TARGET=/usr/local/bin/mechscope.real
[ -f "$TARGET" ] || { echo 'ERROR: MechScope implementation missing'; exit 91; }

python3 "$PATCH" "$TARGET"
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
compile(t,str(p),'exec')
start=t.find('class UnifiedStore(')
end=t.find('\nclass ',start+1)
if end < 0: end=len(t)
s=t[start:end]
assert 'MECHOS_HOTFIX21_UNIFIED_STORE_NATIVE_PAGE' in s
assert 'ONE STORE. NO BROWSER HANDOFF.' in s
assert 'mechos-game-catalog-v15' in s
assert 'mechos-provider-bootstrap-v15' in s
assert "spawn(['xdg-open'" not in s
assert 'webbrowser.' not in s
assert 'dialog.exec()' not in s
PY

mkdir -p /etc/mechos
printf '0.3.0-hotfix.21\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.21/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.21\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 21\n' >/etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix 21 applied: Unified Store is a native in-shell game browser; search no longer launches the desktop browser; native providers bootstrap on explicit provider actions."
