#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.7-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$(dirname "$BUNDLE")"

install -m 0755 "$ROOT/scripts/mechos-hotfix-0.3.0-7-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-7-apply"
install -m 0755 "$ROOT/scripts/mechos-update-center-recovery-v7.py" \
  "$STAGE/usr/local/libexec/mechos-update-center-v7.py"
install -m 0755 "$ROOT/scripts/mechos-store-qlineedit-patch.py" \
  "$STAGE/usr/local/libexec/mechos-store-qlineedit-patch"
install -m 0755 "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
install -m 0755 "$ROOT/scripts/mechos-mode-launch-hotfix5.sh" \
  "$STAGE/usr/local/bin/mechos-mode-launch"
install -m 0755 "$ROOT/scripts/mechos-reboot-hotfix6.sh" \
  "$STAGE/usr/local/bin/mechos-reboot"

cat > "$STAGE/usr/local/bin/mechos-update-center" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v7.py "$@"
EOF
chmod 0755 "$STAGE/usr/local/bin/mechos-update-center"

cat > "$STAGE/usr/share/applications/mechos-update-center.desktop" <<'EOF'
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

cat > "$STAGE/usr/share/applications/mechos-return-gaming.desktop" <<'EOF'
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

cat > "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-7.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 7 VM recovery repairs
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-7-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-7-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-7.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-7.service"

bash -n "$STAGE/usr/local/bin/mechos-update-center"
bash -n "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
bash -n "$STAGE/usr/local/bin/mechos-mode-launch"
bash -n "$STAGE/usr/local/bin/mechos-reboot"
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-7-apply"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$STAGE/usr/local/libexec/mechos-update-center-v7.py" \
  "$STAGE/usr/local/libexec/mechos-store-qlineedit-patch"

rm -f "$BUNDLE" "$SUM"
tar --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" > "$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.7',
  'release_name':'MechOS v0.3.0 Hotfix 7',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Recovery hotfix for upgraded VM installs. Replaces the broken Update Center launcher with a self-contained stable owner, repairs Creator Store QLineEdit imports, and fixes VirtualBox/VMware/QEMU MechScope launching when the installed backend is raw Python without a shebang. Preserves the Hotfix 6 reboot helper.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.7-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'Hotfix 7 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
