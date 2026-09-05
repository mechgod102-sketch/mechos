#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-9-applied"
LOG=/var/log/mechos-hotfix-0.3.0-9.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 9 apply start"
[ -e "$MARKER" ] && exit 0

is_live(){ [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system Hotfix 9 apply skipped.'; exit 0; }

UPDATE=/usr/local/libexec/mechos-update-center-v8.py
OWNER_PATCH=/usr/local/libexec/mechos-final-surface-owner-v8-patch
SETTINGS_PATCH=/usr/local/libexec/mechos-creator-settings-v8-patch
VISUAL_PATCH=/usr/local/libexec/mechos-visual-surfaces-v9-patch
STORE_APPLY=/usr/local/libexec/mechos-apply-current-store-v8
STORE_GENERATOR=/usr/local/libexec/mechos-reference-v5-store-layout.sh
QLINE=/usr/local/libexec/mechos-store-qlineedit-patch
REBOOT=/usr/local/bin/mechos-reboot
UI=/usr/local/share/mechos/ui
THEME=/usr/share/mechos/theme/reference-v5.qss

for f in "$UPDATE" "$OWNER_PATCH" "$SETTINGS_PATCH" "$VISUAL_PATCH" "$STORE_APPLY" "$STORE_GENERATOR" "$QLINE" "$REBOOT" "$THEME"; do
  [ -f "$f" ] || { echo "ERROR: Hotfix 9 component missing: $f"; exit 31; }
done
for f in fixed_canvas.py update_shell.py recovery_shell.py quick_actions_shell.py creator_shell.py; do
  [ -f "$UI/$f" ] || { echo "ERROR: canonical GUI source missing: $UI/$f"; exit 32; }
done
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$UPDATE" "$OWNER_PATCH" "$SETTINGS_PATCH" "$VISUAL_PATCH" "$QLINE"
bash -n "$STORE_APPLY"; bash -n "$STORE_GENERATOR"; bash -n "$REBOOT"

resolve_owner(){
  local name="$1" cls="$2" candidate
  for candidate in \
    "/usr/local/bin/$name.real" \
    "/usr/local/bin/$name" \
    "/usr/local/libexec/${name}-v5.py"; do
    [ -f "$candidate" ] || continue
    grep -Fq "class $cls(" "$candidate" && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

RECOVERY="$(resolve_owner mechos-recovery-center Recovery)" || { echo 'ERROR: Recovery Center owner missing'; exit 33; }
QUICK="$(resolve_owner mechos-quick-actions QuickActions)" || { echo 'ERROR: Quick Actions owner missing'; exit 34; }
CREATOR="$(resolve_owner mechos-creator-mode Creator)" || { echo 'ERROR: Creator Mode owner missing'; exit 35; }

python3 "$OWNER_PATCH" "$RECOVERY" recovery
python3 "$OWNER_PATCH" "$QUICK" quick
python3 "$OWNER_PATCH" "$CREATOR" creator
python3 "$SETTINGS_PATCH" "$CREATOR"

MECHOS_STORE_GENERATOR="$STORE_GENERATOR" bash "$STORE_APPLY" /
if [ -f /usr/local/bin/mechscope.real ]; then MECHSCOPE=/usr/local/bin/mechscope.real; else MECHSCOPE=/usr/local/bin/mechscope; fi
[ -f "$MECHSCOPE" ] || { echo 'ERROR: MechScope owner missing'; exit 36; }

python3 "$VISUAL_PATCH" unified-store "$MECHSCOPE"
python3 "$VISUAL_PATCH" creator "$CREATOR"
if grep -Fq 'QLineEdit' "$MECHSCOPE"; then python3 "$QLINE" "$MECHSCOPE"; fi
if grep -Fq 'QLineEdit' "$CREATOR"; then python3 "$QLINE" "$CREATOR"; fi

# Keep the stable Update Center launcher on the verified v8 backend.
cat > /usr/local/bin/mechos-update-center <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@"
EOF
chmod 0755 /usr/local/bin/mechos-update-center
mkdir -p /usr/share/applications
cat > /usr/share/applications/mechos-update-center.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Update Center
Comment=System Update Control
Exec=/usr/local/bin/mechos-update-center
TryExec=/usr/local/bin/mechos-update-center
Icon=system-software-update
Terminal=false
StartupNotify=true
Categories=System;Settings;
EOF

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$UPDATE" "$RECOVERY" "$QUICK" "$CREATOR" "$MECHSCOPE"
bash -n /usr/local/bin/mechos-update-center

grep -Fq 'MECHOS_VISUAL_SURFACES_V9' "$THEME"
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_FIXED_CANVAS' "$UI/fixed_canvas.py"
grep -Fq 'MECHOS_QUICK_ACTIONS_VISUAL_V9' "$UI/quick_actions_shell.py"
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_QUICK_ACTIONS_WIRING' "$QUICK"
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_CREATOR_STORE' "$CREATOR"
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_CREATOR_SETTINGS' "$CREATOR"
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_UNIFIED_STORE' "$MECHSCOPE"
grep -Fq 'SYSTEM UPDATE CONTROL' "$UI/update_shell.py"
grep -Fq 'RECOVERY CENTER' "$UI/recovery_shell.py"

mkdir -p /etc/mechos
printf '0.3.0-hotfix.9\n' > /etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.9/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.9\n' >> /etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 9\n' > /etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix 9 applied: actual visual design synchronized across modes, settings, Quick Actions and storefronts with real backend wiring preserved."
