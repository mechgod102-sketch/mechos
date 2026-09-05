#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-7-applied"
LOG=/var/log/mechos-hotfix-0.3.0-7.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 7 apply start"
[ -e "$MARKER" ] && exit 0

is_live(){
  [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null
}
is_live && { echo "Live ISO detected; installed-system Hotfix 7 repair skipped."; exit 0; }

CENTER=/usr/local/libexec/mechos-update-center-v7.py
STORE_PATCH=/usr/local/libexec/mechos-store-qlineedit-patch
VM_RUNTIME=/usr/local/bin/mechos-vm-mode-runtime
MODE_LAUNCH=/usr/local/bin/mechos-mode-launch

[ -f "$CENTER" ] || { echo "ERROR: Update Center v7 owner missing"; exit 31; }
[ -f "$STORE_PATCH" ] || { echo "ERROR: Creator Store repair helper missing"; exit 32; }
[ -x "$VM_RUNTIME" ] || { echo "ERROR: VM MechScope runtime missing"; exit 33; }
[ -x "$MODE_LAUNCH" ] || { echo "ERROR: VM mode launcher missing"; exit 34; }

PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m py_compile "$CENTER" "$STORE_PATCH"
bash -n "$VM_RUNTIME"
bash -n "$MODE_LAUNCH"
grep -Fq 'MECHOS_UPDATE_CENTER_RECOVERY_V7' "$CENTER"
grep -Fq 'MECHOS_VM_MECHSCOPE_PYTHON_EXEC_V2' "$VM_RUNTIME"
grep -Fq 'MECHOS_HOTFIX5_VM_DIRECT_ROUTER_V1' "$MODE_LAUNCH"

# Hotfix 6 modified the running Update Center owner in place. Preserve whatever
# is currently installed for diagnostics, then replace only the public launcher
# with a small stable wrapper that starts the self-contained v7 owner.
if [ -e /usr/local/bin/mechos-update-center ] && [ ! -e /usr/local/bin/mechos-update-center.pre-hotfix7 ]; then
  cp -a /usr/local/bin/mechos-update-center /usr/local/bin/mechos-update-center.pre-hotfix7 || true
fi
cat > /usr/local/bin/mechos-update-center <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v7.py "$@"
EOF
chmod 0755 /usr/local/bin/mechos-update-center
bash -n /usr/local/bin/mechos-update-center

mkdir -p /usr/share/applications
cat > /usr/share/applications/mechos-update-center.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Update Center
Comment=Check, install, and finish MechOS updates
Exec=/usr/local/bin/mechos-update-center
TryExec=/usr/local/bin/mechos-update-center
Icon=system-software-update
Terminal=false
StartupNotify=true
Categories=System;Settings;
EOF

# Repair the exact NameError shown by Creator Store. Reference Store v5 creates
# QLineEdit widgets but older installed Python owners may not import QLineEdit.
for target in \
  /usr/local/bin/mechscope.real \
  /usr/local/bin/mechscope \
  /usr/local/bin/mechos-creator-mode \
  /usr/local/libexec/mechos-creator-mode-v5.py; do
  if [ -f "$target" ] && grep -Fq 'QLineEdit' "$target"; then
    /usr/bin/python3 "$STORE_PATCH" "$target"
  fi
done

# Reassert a VM-safe Return to MechScope entry. The runtime now detects raw
# Python backends with or without a shebang and always invokes them via python3.
cat > /usr/share/applications/mechos-return-gaming.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Return to MechScope
Comment=Open MechScope using the VM-safe MechOS launcher
Exec=/usr/local/bin/mechos-mode-launch gaming
TryExec=/usr/local/bin/mechos-mode-launch
Icon=applications-games
Terminal=false
StartupNotify=true
Categories=Game;System;
EOF

mkdir -p /etc/mechos
printf '0.3.0-hotfix.7\n' > /etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.7/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.7\n' >> /etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 7\n' > /etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix 7 applied: Update Center launcher replaced with recovery owner; Creator Store QLineEdit import repaired; VM MechScope Python execution repaired."