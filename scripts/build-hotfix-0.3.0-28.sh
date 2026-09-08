#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX28_VM_MECHSCOPE_LAUNCH_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.28-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H27="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.27-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H27" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-27.sh"
[ -s "$H27" ] || { echo 'Hotfix 27 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H27" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$STAGE/usr/share/applications"

# Explicitly carry the latest VM runtime instead of relying on an older binary
# inherited through HF21-HF27. This is the core repair for systems whose stale
# VMware launcher executed raw Python mechscope.real through /bin/sh.
install -m0755 "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
install -m0755 "$ROOT/scripts/mechos-mode-launch-v19.sh" \
  "$STAGE/usr/local/bin/mechos-mode-launch"
install -m0755 "$ROOT/scripts/mechos-mechscope-runtime-v23.py" \
  "$STAGE/usr/local/libexec/mechos-mechscope-runtime-v23"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-28-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-28-apply"

cat >"$STAGE/usr/share/applications/mechos-return-gaming.desktop" <<'EOF'
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
chmod 0644 "$STAGE/usr/share/applications/mechos-return-gaming.desktop"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-28.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 28 VM MechScope launch repair
After=local-fs.target mechos-hotfix-0.3.0-27.service
Requires=mechos-hotfix-0.3.0-27.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-28-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-28-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-28.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-28.service"

bash -n "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
bash -n "$STAGE/usr/local/bin/mechos-mode-launch"
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-28-apply"
python3 -m py_compile "$STAGE/usr/local/libexec/mechos-mechscope-runtime-v23"

grep -Fq 'MECHOS_VM_MECHSCOPE_PERSISTENT_RUNTIME_V5' "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
grep -Fq 'command=(/usr/bin/python3 "$target")' "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
grep -Fq '/usr/local/libexec/mechos-mechscope-runtime-v23' "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
grep -Fq 'MECHOS_MODE_LAUNCH_VM_DIRECT_V28' "$STAGE/usr/local/bin/mechos-mode-launch"
grep -Fq 'MECHOS_HOTFIX28_VM_MECHSCOPE_LAUNCH_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-28-apply"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$STAGE/usr/share/applications/mechos-return-gaming.desktop"

for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-27-apply" \
  "$STAGE/usr/local/share/mechos/ui/oobe_shell.py" \
  "$STAGE/usr/local/bin/mechos-oobe-start" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14"; do
  [ -e "$required" ] || { echo "Cumulative component missing: $required" >&2; exit 1; }
done

DAY="$(date -u +%F)"
EPOCH="$(date -u -d "$DAY 00:00:00" +%s)"
rm -f "$BUNDLE" "$SUM"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
  --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.28',
  'release_name':'MechOS v0.3.0 Hotfix 28',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative VMware/VM MechScope launch repair. Replaces stale VM runtimes that executed raw Python /usr/local/bin/mechscope.real as shell code, causing from/import command-not-found errors and failed Wayland/X11 retries. VM mode changes now route directly through the current Plasma-hosted runtime, prefer the persistent Hotfix 22.6+ MechScope runtime when its owner exists, explicitly invoke Python targets through /usr/bin/python3, retain Wayland/XWayland fallback, and restore the Return to MechScope launcher. Includes all Hotfix 27 OOBE UI crash fixes.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.28-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 28 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
