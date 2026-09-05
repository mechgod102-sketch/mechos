#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.15-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/user" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$(dirname "$BUNDLE")"

# Keep the established launcher as the fallback for Gaming/MechScope/Desktop.
# Hotfix 15 owns only the Creator transition so it can guarantee that MechScope
# stays alive until Creator is proven healthy.
install -m0755 "$ROOT/scripts/mechos-mode-launch-v15.sh" \
  "$STAGE/usr/local/bin/mechos-mode-launch"
install -m0755 "$ROOT/scripts/mechos-mode-launch-hotfix10.sh" \
  "$STAGE/usr/local/libexec/mechos-mode-launch-base-v15"
install -m0755 "$ROOT/scripts/mechos-hotfix15-runtime-patch.py" \
  "$STAGE/usr/local/libexec/mechos-hotfix15-runtime-patch"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-15-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-15-apply"

cat >"$STAGE/usr/lib/systemd/user/mechos-creator-mode.service" <<'EOF'
[Unit]
Description=MechOS Creator Mode overlay
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=MECHOS_MODE=creator
ExecStart=/usr/local/bin/mechos-creator-mode
Restart=no
TimeoutStopSec=8
KillMode=control-group
EOF

cat >"$STAGE/usr/lib/systemd/user/mechos-vm-creator.service" <<'EOF'
[Unit]
Description=MechOS Creator Mode overlay in virtual machines
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=MECHOS_MODE=creator
Environment=MECHOS_VM_MODE=1
Environment=MECHOS_DISABLE_GAMESCOPE=1
Environment=QT_OPENGL=software
Environment=LIBGL_ALWAYS_SOFTWARE=1
Environment=QT_QUICK_BACKEND=software
Environment=QSG_RHI_BACKEND=software
ExecStart=/usr/local/bin/mechos-creator-mode
Restart=no
TimeoutStopSec=8
KillMode=control-group
EOF

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-15.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 15 Creator and Unified Store repairs
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-15-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-15-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-15.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-15.service"

# Bundle gates.
bash -n "$STAGE/usr/local/bin/mechos-mode-launch"
bash -n "$STAGE/usr/local/libexec/mechos-mode-launch-base-v15"
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-15-apply"
python3 -m py_compile "$STAGE/usr/local/libexec/mechos-hotfix15-runtime-patch"
grep -Fq 'MECHOS_MODE_LAUNCH_V15' "$STAGE/usr/local/bin/mechos-mode-launch"
grep -Fq 'MECHOS_CREATOR_HANDOFF_V15' "$STAGE/usr/local/bin/mechos-mode-launch"
grep -Fq 'MECHOS_CREATOR_VM_OVERLAY_V15' "$STAGE/usr/local/bin/mechos-mode-launch"
grep -Fq 'MECHOS_HOTFIX15_NATIVE_UNIFIED_STORE' "$STAGE/usr/local/libexec/mechos-hotfix15-runtime-patch"
grep -Fq 'ExecStart=/usr/local/bin/mechos-creator-mode' "$STAGE/usr/lib/systemd/user/mechos-creator-mode.service"
grep -Fq 'QT_OPENGL=software' "$STAGE/usr/lib/systemd/user/mechos-vm-creator.service"
! grep -Eq 'mechos-vm-mode-runtime[[:space:]]+creator' "$STAGE/usr/local/bin/mechos-mode-launch"
! grep -Fq "spawn(['xdg-open'" "$STAGE/usr/local/libexec/mechos-hotfix15-runtime-patch"

rm -f "$BUNDLE" "$SUM"
tar --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime, json, sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.15',
  'release_name':'MechOS v0.3.0 Hotfix 15',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Creator Mode and Unified Store reliability hotfix. Creator Mode is now launched as a verified overlay above MechScope instead of terminating MechScope first. Virtual machines inherit the required software-rendering environment while MechScope remains available underneath, so a failed Creator launch returns an in-MechOS error instead of exposing the desktop. Unified Store browse and search actions no longer hand off to the desktop web browser; Steam routes into the Steam client and Epic/GOG/Amazon routes into Heroic when installed.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.15-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 15 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
