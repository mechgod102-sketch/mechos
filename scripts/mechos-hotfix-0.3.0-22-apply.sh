#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX22_APPLY_V1
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-22-applied"
LOG=/var/log/mechos-hotfix-0.3.0-22.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 22 apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

MODULE=/usr/local/share/mechos/ui/creator_real_icons_v22.py
PATCH=/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch
[ -f "$MODULE" ] || { echo "ERROR: Creator real-icon module missing: $MODULE"; exit 90; }
[ -x "$PATCH" ] || { echo "ERROR: Creator owner patch missing: $PATCH"; exit 91; }
python3 -m py_compile "$MODULE" "$PATCH"

TARGET=/usr/local/bin/mechos-creator-mode
[ -f /usr/local/bin/mechos-creator-mode.real ] && TARGET=/usr/local/bin/mechos-creator-mode.real
[ -f "$TARGET" ] || { echo 'ERROR: Creator Mode implementation missing'; exit 92; }

grep -Fq 'MECHOS_HOTFIX10_CREATOR_VISUAL_OWNER_V1' "$TARGET" || {
  echo 'ERROR: Creator visual owner v10 is not active; refusing an unsafe icon-only patch.'
  exit 93
}
python3 "$PATCH" "$TARGET"
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
compile(t,str(p),'exec')
assert 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' in t
assert "creator_real_icons_v22.py" in t
assert 'icons.install(shell)' in t
PY

grep -Fq 'MECHOS_CREATOR_REAL_ICONS_V22' "$MODULE"
grep -Fq '/var/lib/flatpak/appstream' "$MODULE"
grep -Fq '/var/lib/flatpak/exports/share/applications' "$MODULE"
grep -Fq 'QIcon.fromTheme' "$MODULE"

mkdir -p /etc/mechos
printf '0.3.0-hotfix.22\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.22/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.22\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 22\n' >/etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix 22 applied: Creator Mode and Creator Store now prefer application-owned desktop/theme/AppStream icons and use generated MechOS badges only as fallback."
