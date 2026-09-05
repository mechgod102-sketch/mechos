#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-11-applied"
LOG=/var/log/mechos-hotfix-0.3.0-11.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 11 apply start"
[ -e "$MARKER" ] && exit 0

is_live(){ [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system Hotfix 11 apply skipped.'; exit 0; }

UPDATE=/usr/local/libexec/mechos-update-center-v8.py
OWNER_PATCH=/usr/local/libexec/mechos-final-surface-owner-v8-patch
SETTINGS_PATCH=/usr/local/libexec/mechos-creator-settings-v8-patch
VISUAL_PATCH=/usr/local/libexec/mechos-visual-surfaces-v9-patch
CREATOR_V10_PATCH=/usr/local/libexec/mechos-creator-visual-owner-v10-patch
MECHSCOPE_IMPORTS=/usr/local/libexec/mechos-mechscope-runtime-imports-v11
STORE_APPLY=/usr/local/libexec/mechos-apply-current-store-v8
STORE_GENERATOR=/usr/local/libexec/mechos-reference-v5-store-layout.sh
QLINE=/usr/local/libexec/mechos-store-qlineedit-patch
REBOOT=/usr/local/bin/mechos-reboot
MODE_LAUNCH=/usr/local/bin/mechos-mode-launch
VM_RUNTIME=/usr/local/bin/mechos-vm-mode-runtime
UI=/usr/local/share/mechos/ui
THEME=/usr/share/mechos/theme/reference-v5.qss

for f in "$UPDATE" "$OWNER_PATCH" "$SETTINGS_PATCH" "$VISUAL_PATCH" "$CREATOR_V10_PATCH" "$MECHSCOPE_IMPORTS" "$STORE_APPLY" "$STORE_GENERATOR" "$QLINE" "$REBOOT" "$MODE_LAUNCH" "$VM_RUNTIME" "$THEME"; do
  [ -f "$f" ] || { echo "ERROR: Hotfix 11 component missing: $f"; exit 51; }
done
for f in fixed_canvas.py update_shell.py recovery_shell.py quick_actions_shell.py creator_shell.py creator_visual_shell_v10.py; do
  [ -f "$UI/$f" ] || { echo "ERROR: canonical GUI source missing: $UI/$f"; exit 52; }
done

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$UPDATE" "$OWNER_PATCH" "$SETTINGS_PATCH" "$VISUAL_PATCH" "$CREATOR_V10_PATCH" \
  "$MECHSCOPE_IMPORTS" "$QLINE" "$UI/fixed_canvas.py" "$UI/update_shell.py" \
  "$UI/recovery_shell.py" "$UI/quick_actions_shell.py" "$UI/creator_shell.py" \
  "$UI/creator_visual_shell_v10.py"
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

RECOVERY="$(resolve_owner mechos-recovery-center Recovery)" || { echo 'ERROR: Recovery Center owner missing'; exit 53; }
QUICK="$(resolve_owner mechos-quick-actions QuickActions)" || { echo 'ERROR: Quick Actions owner missing'; exit 54; }
CREATOR="$(resolve_owner mechos-creator-mode Creator)" || { echo 'ERROR: Creator Mode owner missing'; exit 55; }

# Keep Hotfix 9/10 UI authority while applying the VM runtime repair.
python3 "$OWNER_PATCH" "$RECOVERY" recovery
python3 "$OWNER_PATCH" "$QUICK" quick
python3 "$OWNER_PATCH" "$CREATOR" creator
python3 "$SETTINGS_PATCH" "$CREATOR"

MECHOS_STORE_GENERATOR="$STORE_GENERATOR" bash "$STORE_APPLY" /
if [ -f /usr/local/bin/mechscope.real ]; then MECHSCOPE=/usr/local/bin/mechscope.real; else MECHSCOPE=/usr/local/bin/mechscope; fi
[ -f "$MECHSCOPE" ] || { echo 'ERROR: MechScope owner missing'; exit 56; }

python3 "$VISUAL_PATCH" unified-store "$MECHSCOPE"
python3 "$VISUAL_PATCH" creator "$CREATOR"
if grep -Fq 'QLineEdit' "$MECHSCOPE"; then python3 "$QLINE" "$MECHSCOPE"; fi
if grep -Fq 'QLineEdit' "$CREATOR"; then python3 "$QLINE" "$CREATOR"; fi
python3 "$MECHSCOPE_IMPORTS" "$MECHSCOPE"
python3 "$CREATOR_V10_PATCH" "$CREATOR"

# Keep Update Center recoverable even when this hotfix was installed through
# the command-line update helper because the graphical Update Center was down.
cat > /usr/local/bin/mechos-update-center <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/update-center-launch.log"
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@" 2>>"$LOG"
EOF
chmod 0755 /usr/local/bin/mechos-update-center /usr/local/bin/mechos-mode-launch /usr/local/bin/mechos-vm-mode-runtime
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
bash -n "$VM_RUNTIME"

grep -Fq 'MECHOS_VISUAL_SURFACES_V9' "$THEME"
grep -Fq 'MECHOS_CREATOR_VISUALS_V10' "$UI/creator_visual_shell_v10.py"
grep -Fq 'MECHOS_HOTFIX10_CREATOR_VISUAL_OWNER_V1' "$CREATOR"
grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_IMPORTS_V11' "$MECHSCOPE"
grep -Fq 'MECHOS_VM_MECHSCOPE_QPA_FALLBACK_V3' "$VM_RUNTIME"
grep -Fq 'run_mechscope_attempt xwayland xcb' "$VM_RUNTIME"
grep -Fq 'run_mechscope_attempt wayland wayland' "$VM_RUNTIME"
grep -Fq 'MECHOS_HOTFIX11_VM_FAILURE_LOGS_V1' "$MODE_LAUNCH"
grep -Fq 'vm-mechscope-launch.log' "$MODE_LAUNCH"
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_UNIFIED_STORE' "$MECHSCOPE"

mkdir -p /etc/mechos
printf '0.3.0-hotfix.11\n' > /etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.11/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.11\n' >> /etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 11\n' > /etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix 11 applied: VM MechScope now retries visible Qt backends, records the real VM startup logs, and carries Creator/Store visual authority forward."
