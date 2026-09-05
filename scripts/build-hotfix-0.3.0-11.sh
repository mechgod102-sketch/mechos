#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.11-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/share/mechos/theme" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$(dirname "$BUNDLE")"

install -m 0755 "$ROOT/scripts/mechos-hotfix-0.3.0-11-apply.sh" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-11-apply"
install -m 0755 "$ROOT/scripts/mechos-update-center-reference-v8.py" "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
install -m 0755 "$ROOT/scripts/mechos-final-surface-owner-v8-patch.py" "$STAGE/usr/local/libexec/mechos-final-surface-owner-v8-patch"
install -m 0755 "$ROOT/scripts/mechos-creator-settings-v8-patch.py" "$STAGE/usr/local/libexec/mechos-creator-settings-v8-patch"
install -m 0755 "$ROOT/scripts/mechos-visual-surfaces-v9-patch.py" "$STAGE/usr/local/libexec/mechos-visual-surfaces-v9-patch"
install -m 0755 "$ROOT/scripts/mechos-creator-visual-owner-v10-patch.py" "$STAGE/usr/local/libexec/mechos-creator-visual-owner-v10-patch"
install -m 0755 "$ROOT/scripts/mechos-mechscope-runtime-imports-v11.py" "$STAGE/usr/local/libexec/mechos-mechscope-runtime-imports-v11"
install -m 0755 "$ROOT/scripts/mechos-apply-current-store-v8.sh" "$STAGE/usr/local/libexec/mechos-apply-current-store-v8"
install -m 0755 "$ROOT/scripts/mechos-reference-v5-store-layout.sh" "$STAGE/usr/local/libexec/mechos-reference-v5-store-layout.sh"
install -m 0755 "$ROOT/scripts/mechos-store-qlineedit-patch.py" "$STAGE/usr/local/libexec/mechos-store-qlineedit-patch"
install -m 0755 "$ROOT/scripts/mechos-reboot-hotfix6.sh" "$STAGE/usr/local/bin/mechos-reboot"
install -m 0755 "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh" "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
install -m 0755 "$ROOT/scripts/mechos-mode-launch-hotfix10.sh" "$STAGE/usr/local/bin/mechos-mode-launch"

for f in fixed_canvas.py update_shell.py recovery_shell.py quick_actions_shell.py creator_shell.py creator_visual_shell_v10.py; do
  install -m 0644 "$ROOT/src/mechos_ui/$f" "$STAGE/usr/local/share/mechos/ui/$f"
done
install -m 0644 "$ROOT/src/mechos_ui/reference-v9.qss" "$STAGE/usr/share/mechos/theme/reference-v9.qss"
install -m 0644 "$ROOT/src/mechos_ui/reference-v9.qss" "$STAGE/usr/share/mechos/theme/reference-v5.qss"

cat > "$STAGE/usr/local/bin/mechos-update-center" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
mkdir -p "$STATE_DIR"
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@" 2>>"$STATE_DIR/update-center-launch.log"
EOF
chmod 0755 "$STAGE/usr/local/bin/mechos-update-center"

cat > "$STAGE/usr/share/applications/mechos-update-center.desktop" <<'EOF'
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

cat > "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-11.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 11 VM MechScope repair
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-11-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-11-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-11.service "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-11.service"

for f in \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechos-reboot" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime" \
  "$STAGE/usr/local/bin/mechos-mode-launch" \
  "$STAGE/usr/local/libexec/mechos-apply-current-store-v8" \
  "$STAGE/usr/local/libexec/mechos-reference-v5-store-layout.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-11-apply"; do
  bash -n "$f"
done

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$STAGE/usr/local/libexec/mechos-update-center-v8.py" \
  "$STAGE/usr/local/libexec/mechos-final-surface-owner-v8-patch" \
  "$STAGE/usr/local/libexec/mechos-creator-settings-v8-patch" \
  "$STAGE/usr/local/libexec/mechos-visual-surfaces-v9-patch" \
  "$STAGE/usr/local/libexec/mechos-creator-visual-owner-v10-patch" \
  "$STAGE/usr/local/libexec/mechos-mechscope-runtime-imports-v11" \
  "$STAGE/usr/local/libexec/mechos-store-qlineedit-patch" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/update_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/recovery_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/quick_actions_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_visual_shell_v10.py"

rm -f "$BUNDLE" "$SUM"
tar --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" > "$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime, json, sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.11',
  'release_name':'MechOS v0.3.0 Hotfix 11',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'VM MechScope reliability hotfix. Repairs the runtime rc=1 path seen in Oracle VirtualBox by retrying MechScope with the active Qt platform, XWayland/xcb and native Wayland while keeping software rendering and Gamescope disabled in VMs. Adds a three-second startup health probe, runtime Qt import guard, correct VM log paths and mirrored MechScope startup diagnostics. Also restores a logging Update Center launcher and carries Hotfix 10 Creator graphics and Hotfix 9 storefront/backend authority forward.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.11-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'Hotfix 11 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
