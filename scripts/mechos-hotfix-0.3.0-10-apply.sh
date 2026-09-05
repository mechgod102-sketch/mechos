#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-10-applied"
LOG=/var/log/mechos-hotfix-0.3.0-10.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 10 apply start"
[ -e "$MARKER" ] && exit 0

is_live(){ [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system Hotfix 10 apply skipped.'; exit 0; }

UPDATE=/usr/local/libexec/mechos-update-center-v8.py
OWNER_PATCH=/usr/local/libexec/mechos-final-surface-owner-v8-patch
SETTINGS_PATCH=/usr/local/libexec/mechos-creator-settings-v8-patch
VISUAL_PATCH=/usr/local/libexec/mechos-visual-surfaces-v9-patch
CREATOR_V10_PATCH=/usr/local/libexec/mechos-creator-visual-owner-v10-patch
STORE_APPLY=/usr/local/libexec/mechos-apply-current-store-v8
STORE_GENERATOR=/usr/local/libexec/mechos-reference-v5-store-layout.sh
QLINE=/usr/local/libexec/mechos-store-qlineedit-patch
REBOOT=/usr/local/bin/mechos-reboot
MODE_LAUNCH=/usr/local/bin/mechos-mode-launch
VM_RUNTIME=/usr/local/bin/mechos-vm-mode-runtime
UI=/usr/local/share/mechos/ui
THEME=/usr/share/mechos/theme/reference-v5.qss

for f in "$UPDATE" "$OWNER_PATCH" "$SETTINGS_PATCH" "$VISUAL_PATCH" "$CREATOR_V10_PATCH" "$STORE_APPLY" "$STORE_GENERATOR" "$QLINE" "$REBOOT" "$MODE_LAUNCH" "$VM_RUNTIME" "$THEME"; do
  [ -f "$f" ] || { echo "ERROR: Hotfix 10 component missing: $f"; exit 41; }
done
for f in fixed_canvas.py update_shell.py recovery_shell.py quick_actions_shell.py creator_shell.py creator_visual_shell_v10.py; do
  [ -f "$UI/$f" ] || { echo "ERROR: canonical GUI source missing: $UI/$f"; exit 42; }
done

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$UPDATE" "$OWNER_PATCH" "$SETTINGS_PATCH" "$VISUAL_PATCH" "$CREATOR_V10_PATCH" "$QLINE" \
  "$UI/fixed_canvas.py" "$UI/update_shell.py" "$UI/recovery_shell.py" \
  "$UI/quick_actions_shell.py" "$UI/creator_shell.py" "$UI/creator_visual_shell_v10.py"
for f in "$STORE_APPLY" "$STORE_GENERATOR" "$REBOOT" "$MODE_LAUNCH" "$VM_RUNTIME"; do bash -n "$f"; done

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

RECOVERY="$(resolve_owner mechos-recovery-center Recovery)" || { echo 'ERROR: Recovery Center owner missing'; exit 43; }
QUICK="$(resolve_owner mechos-quick-actions QuickActions)" || { echo 'ERROR: Quick Actions owner missing'; exit 44; }
CREATOR="$(resolve_owner mechos-creator-mode Creator)" || { echo 'ERROR: Creator Mode owner missing'; exit 45; }

# Reassert the Hotfix 9 visual/backend baseline first so Hotfix 10 can be
# safely applied from older installed builds as a self-contained update.
python3 "$OWNER_PATCH" "$RECOVERY" recovery
python3 "$OWNER_PATCH" "$QUICK" quick
python3 "$OWNER_PATCH" "$CREATOR" creator
python3 "$SETTINGS_PATCH" "$CREATOR"

MECHOS_STORE_GENERATOR="$STORE_GENERATOR" bash "$STORE_APPLY" /
if [ -f /usr/local/bin/mechscope.real ]; then MECHSCOPE=/usr/local/bin/mechscope.real; else MECHSCOPE=/usr/local/bin/mechscope; fi
[ -f "$MECHSCOPE" ] || { echo 'ERROR: MechScope owner missing'; exit 46; }

python3 "$VISUAL_PATCH" unified-store "$MECHSCOPE"
python3 "$VISUAL_PATCH" creator "$CREATOR"
if grep -Fq 'QLineEdit' "$MECHSCOPE"; then python3 "$QLINE" "$MECHSCOPE"; fi
if grep -Fq 'QLineEdit' "$CREATOR"; then python3 "$QLINE" "$CREATOR"; fi

# Hotfix 10 wins last for Creator Mode. It swaps the home/dashboard to the
# graphical shell while leaving every existing Creator page/backend available.
python3 "$CREATOR_V10_PATCH" "$CREATOR"

# Keep the stable Update Center launcher on the verified v8 backend.
cat > /usr/local/bin/mechos-update-center <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@"
EOF
chmod 0755 /usr/local/bin/mechos-update-center /usr/local/bin/mechos-mode-launch
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

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$UPDATE" "$RECOVERY" "$QUICK" "$CREATOR" "$MECHSCOPE" "$UI/creator_visual_shell_v10.py"
bash -n /usr/local/bin/mechos-update-center
bash -n "$MODE_LAUNCH"

grep -Fq 'MECHOS_VISUAL_SURFACES_V9' "$THEME"
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_FIXED_CANVAS' "$UI/fixed_canvas.py"
grep -Fq 'MECHOS_QUICK_ACTIONS_VISUAL_V9' "$UI/quick_actions_shell.py"
grep -Fq 'MECHOS_CREATOR_VISUALS_V10' "$UI/creator_visual_shell_v10.py"
grep -Fq 'MECHOS_HOTFIX10_CREATOR_VISUAL_OWNER_V1' "$CREATOR"
grep -Fq 'MECHOS_HOTFIX10_PHYSICAL_MECHSCOPE_FALLBACK_V1' "$MODE_LAUNCH"
grep -Fq 'controller produced no MechScope process' "$MODE_LAUNCH"
grep -Fq 'direct fallback: MechScope launch healthy' "$MODE_LAUNCH"
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_UNIFIED_STORE' "$MECHSCOPE"

mkdir -p /etc/mechos
printf '0.3.0-hotfix.10\n' > /etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.10/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.10\n' >> /etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 10\n' > /etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix 10 applied: Creator Mode now has generated graphical visuals and MechScope has a physical-session direct fallback with detailed launch diagnostics."
