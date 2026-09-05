#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.5-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$STAGE/etc/xdg/autostart" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/wayland-sessions" \
  "$(dirname "$BUNDLE")"

install -m 0755 "$ROOT/scripts/mechos-hotfix-0.3.0-5-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-5-apply"
install -m 0755 "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
install -m 0755 "$ROOT/scripts/mechos-mode-launch-hotfix5.sh" \
  "$STAGE/usr/local/bin/mechos-mode-launch"

cat > "$STAGE/etc/xdg/autostart/mechos-vm-mode-runtime.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS VM Mode Runtime
Comment=Restore the selected MechOS mode after Plasma is ready in a virtual machine
Exec=/usr/local/bin/mechos-vm-mode-runtime boot
TryExec=/usr/local/bin/mechos-vm-mode-runtime
Terminal=false
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
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

cat > "$STAGE/usr/share/wayland-sessions/mechscope.desktop" <<'EOF'
[Desktop Entry]
Name=MechScope
Comment=MechOS Gaming Mode
Exec=/usr/local/bin/mechscope-session
TryExec=/usr/local/bin/mechscope-session
Type=Application
DesktopNames=MechScope
EOF

cat > "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-5.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 5 VM MechScope launch repair
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-5-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-5-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-5.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-5.service"

bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-5-apply"
bash -n "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
bash -n "$STAGE/usr/local/bin/mechos-mode-launch"

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
  'version':'0.3.0-hotfix.5',
  'release_name':'MechOS v0.3.0 Hotfix 5',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Repairs MechScope launching on upgraded VirtualBox/VMware/QEMU installs by shipping the complete VM launcher/runtime pair and routing VM mode switches directly to the Plasma-hosted MechScope runtime instead of depending on a stale gaming-layer controller. The runtime preserves the first-run OOBE gate, prefers the real MechScope UI backend when a tutorial wrapper is present, performs a Python health check, records a dedicated launch log, and leaves physical-hardware Gamescope routing unchanged.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.5-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'Hotfix 5 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
