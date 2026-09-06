#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX22_APPLY_V3
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-22.1-applied"
LOG=/var/log/mechos-hotfix-0.3.0-22.1.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 22.1 cumulative apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

# Hotfix 22.1 is the recovery/cumulative activation point for Hotfixes 15-21.
# Older units may already have applied some layers; marker checks keep this
# idempotent. A direct jump from Hotfix 14, original Hotfix 22, or a partially
# activated system receives every missing layer in order before 22.1 finalizes.
apply_layer(){
  local n="$1"
  local layer_marker="$STATE/hotfix-0.3.0-${n}-applied"
  local helper="/usr/local/libexec/mechos-hotfix-0.3.0-${n}-apply"
  if [ -e "$layer_marker" ]; then
    echo "[$(date -Is)] Hotfix ${n} already active; skipping"
    return 0
  fi
  [ -x "$helper" ] || { echo "ERROR: cumulative Hotfix ${n} helper missing: $helper"; exit $((120 + n)); }
  echo "[$(date -Is)] Activating cumulative Hotfix ${n}"
  "$helper"
  [ -e "$layer_marker" ] || { echo "ERROR: Hotfix ${n} helper returned without creating $layer_marker"; exit $((140 + n)); }
}

for n in 15 16 17 18 19 20 21; do
  apply_layer "$n"
done

for n in 15 16 17 18 19 20 21; do
  [ -e "$STATE/hotfix-0.3.0-${n}-applied" ] || { echo "ERROR: cumulative activation incomplete at Hotfix ${n}"; exit 170; }
done

echo "[$(date -Is)] Hotfixes 15-21 confirmed active; applying Hotfix 22 icon layer"

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
printf '0.3.0-hotfix.22.1\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.22.1/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.22.1\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 22.1\n' >/etc/system-release

rm -f "$STATE/reboot-required"
touch "$MARKER"
echo "[$(date -Is)] Hotfix 22.1 applied: Hotfixes 15-21 are active and Creator Mode/Creator Store prefer application-owned desktop/theme/AppStream icons with generated MechOS badges only as fallback."
