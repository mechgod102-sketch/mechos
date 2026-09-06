#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX22_APPLY_V5
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-22.3-applied"
LOG=/var/log/mechos-hotfix-0.3.0-22.3.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 22.3 cumulative apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

# Hotfix 22.3 remains the cumulative activation point for Hotfixes 15-21.
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

# MECHOS_HOTFIX22_3_MECHSCOPE_PERSISTENT_RUNTIME
# Cumulative patching can leave a syntactically valid generated MechScope owner
# whose historical __main__ path returns 0 immediately. Preserve the final
# patched owner and make a small stable runtime own QApplication.exec() itself.
RUNTIME=/usr/local/libexec/mechos-mechscope-runtime-v23
OWNER=/usr/local/libexec/mechscope-owner-v23.py
MECH_TARGET=/usr/local/bin/mechscope
[ -f /usr/local/bin/mechscope.real ] && MECH_TARGET=/usr/local/bin/mechscope.real

[ -x "$RUNTIME" ] || { echo "ERROR: MechScope persistent runtime missing: $RUNTIME"; exit 94; }
python3 -m py_compile "$RUNTIME"

if grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_V23' "$MECH_TARGET" 2>/dev/null; then
  [ -f "$OWNER" ] || { echo 'ERROR: MechScope runtime already installed but preserved owner is missing'; exit 95; }
else
  [ -f "$MECH_TARGET" ] || { echo "ERROR: MechScope implementation missing: $MECH_TARGET"; exit 96; }
  install -D -m0755 "$MECH_TARGET" "$OWNER"
fi

python3 - "$OWNER" <<'PY'
from pathlib import Path
import ast,sys
p=Path(sys.argv[1])
text=p.read_text(encoding='utf-8')
compile(text,str(p),'exec')
tree=ast.parse(text,str(p))
classes={node.name for node in tree.body if isinstance(node,ast.ClassDef)}
if 'MechScope' not in classes:
    raise SystemExit('preserved MechScope owner has no top-level MechScope class')
PY

install -m0755 "$RUNTIME" "$MECH_TARGET"
grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_V23' "$MECH_TARGET"
grep -Fq 'QApplication.instance()' "$MECH_TARGET"
grep -Fq 'app.exec()' "$MECH_TARGET"
echo "[$(date -Is)] MechScope persistent runtime installed target=$MECH_TARGET owner=$OWNER"

mkdir -p /etc/mechos
printf '0.3.0-hotfix.22.3\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.22.3/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.22.3\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 22.3\n' >/etc/system-release

rm -f "$STATE/reboot-required"
touch "$MARKER"
echo "[$(date -Is)] Hotfix 22.3 applied: cumulative Hotfixes 15-21 are active; Creator real icons remain enabled; MechScope now runs through a persistent Qt runtime that preserves the patched owner and cannot silently exit through a stale generated __main__ path."
