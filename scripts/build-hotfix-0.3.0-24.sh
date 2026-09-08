#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX24_MECHSCOPE_AUTOLAUNCH_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.24-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H23="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.23-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H23" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-23.sh"
[ -s "$H23" ] || { echo 'Hotfix 23 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H23" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-24-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-24.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 24 MechScope session/autolaunch repair
After=local-fs.target mechos-hotfix-0.3.0-23.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-24-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-24-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-24.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-24.service"

bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-24-apply"
grep -Fq 'MECHOS_HOTFIX24_MECHSCOPE_AUTOLAUNCH_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-24-apply"
grep -Fq 'Session=mechscope.desktop' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-24-apply"
grep -Fq 'MECHOS_VM_MODE_RUNTIME_V24' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-24-apply"
grep -Fq 'MECHOS_SESSION_AUTOSTART_V24' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-24-apply"

# Preserve Hotfix 23 account recovery and the cumulative updater core.
for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-23-apply" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v13" \
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
  'version':'0.3.0-hotfix.24',
  'release_name':'MechOS v0.3.0 Hotfix 24',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative MechScope startup recovery update. Corrects the Hotfix 23 post-OOBE SDDM handoff from the obsolete mechos-gaming.desktop session name to the installed mechscope.desktop session, restores automatic MechScope startup after login, and replaces the affected VMware VM Gaming launcher with a direct graphical-session runtime that preserves Plasma as compositor, imports the active display environment, launches MechScope with software rendering on Wayland, and retries through X11 when needed. Includes the complete Hotfix 23 account-creation recovery and cumulative updater protections.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.24-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 24 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
