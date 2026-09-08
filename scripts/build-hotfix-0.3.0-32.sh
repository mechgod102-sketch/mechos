#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX32_SINGLE_MECHSCOPE_OWNER_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.32-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H31="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.31-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H31" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-31.sh"
[ -s "$H31" ] || { echo 'Hotfix 31 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H31" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

install -m0755 "$ROOT/scripts/mechscope-session-v20.sh" \
  "$STAGE/usr/local/bin/mechscope-session"
install -m0755 "$ROOT/scripts/mechos-mechscope-safe-launch-v31.sh" \
  "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31"
install -m0755 "$ROOT/scripts/mechos-session-autostart-v31.sh" \
  "$STAGE/usr/local/libexec/mechos-session-autostart-v31"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-32-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-32-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-32.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 32 single-owner MechScope recovery
After=local-fs.target mechos-hotfix-0.3.0-31.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-32-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-32-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-32.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-32.service"

bash -n \
  "$STAGE/usr/local/bin/mechscope-session" \
  "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31" \
  "$STAGE/usr/local/libexec/mechos-session-autostart-v31" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-32-apply"
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V22_SINGLE_OWNER' "$STAGE/usr/local/bin/mechscope-session"
grep -Fq '/usr/bin/flock -n "$LOCK_FILE"' "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'MECHOS_MECHSCOPE_SINGLE_OWNER_V32' "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31"
grep -Fq 'MECHOS_SESSION_SINGLE_OWNER_V32' "$STAGE/usr/local/libexec/mechos-session-autostart-v31"
grep -Fq 'MECHOS_HOTFIX32_SINGLE_MECHSCOPE_OWNER_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-32-apply"

for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-31-apply" \
  "$STAGE/usr/local/libexec/mechos-mechscope-runtime-v23" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/oobe_shell.py" \
  "$STAGE/usr/local/bin/mechos-update-helper"; do
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
  'version':'0.3.0-hotfix.32',
  'release_name':'MechOS v0.3.0 Hotfix 32',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative physical-hardware MechScope single-owner recovery. Fixes a race where the supervised Gamescope/Plasma hardware session and the legacy KDE graphical autostart could both launch MechScope during Plasma startup, producing duplicate instances and an apparent crash/restart loop even after the Hotfix 31 Python-wrapper repair. The canonical hardware session now owns a shared flock lock, KDE fallback exits whenever a supervised MechScope session is active, the safe launcher suppresses duplicate owners, and historical duplicate system autostarts that directly spawn MechScope are disabled. Includes all Hotfix 31 Python wrapper, Hotfix 30 crash-loop, Creator icon, VMware, OOBE and updater repairs.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.32-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 32 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
