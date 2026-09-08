#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX26_OOBE_LAUNCHER_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.26-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H25="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.25-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H25" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-25.sh"
[ -s "$H25" ] || { echo 'Hotfix 25 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H25" -C "$STAGE"

mkdir -p "$STAGE/usr/local/bin" "$STAGE/usr/local/libexec" "$STAGE/usr/lib/systemd/system" "$STAGE/etc/systemd/system/multi-user.target.wants"
install -m0755 "$ROOT/scripts/mechos-oobe-start-v26.sh" "$STAGE/usr/local/bin/mechos-oobe-start"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-26-apply.sh" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-26-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-26.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 26 First System Setup launcher repair
After=local-fs.target mechos-hotfix-0.3.0-25.service
Requires=mechos-hotfix-0.3.0-25.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-26-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-26-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-26.service "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-26.service"

bash -n "$STAGE/usr/local/bin/mechos-oobe-start"
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-26-apply"
grep -Fq 'MECHOS_OOBE_START_V26' "$STAGE/usr/local/bin/mechos-oobe-start"
grep -Fq 'systemctl --user show-environment' "$STAGE/usr/local/bin/mechos-oobe-start"
grep -Fq 'QT_QPA_PLATFORM=wayland' "$STAGE/usr/local/bin/mechos-oobe-start"
grep -Fq 'QT_QPA_PLATFORM=xcb' "$STAGE/usr/local/bin/mechos-oobe-start"
grep -Fq 'MECHOS_HOTFIX26_OOBE_LAUNCHER_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-26-apply"

for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-25-apply" \
  "$STAGE/usr/local/libexec/mechos-oobe-rearm-v25" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-24-apply"; do
  [ -e "$required" ] || { echo "Cumulative component missing: $required" >&2; exit 1; }
done

DAY="$(date -u +%F)"
EPOCH="$(date -u -d "$DAY 00:00:00" +%s)"
rm -f "$BUNDLE" "$SUM"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.26',
  'release_name':'MechOS v0.3.0 Hotfix 26',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative First System Setup launcher recovery. Fixes clicks that appeared to do nothing by replacing the OOBE launcher with a graphical-session-aware runtime that restores KDE user-manager display variables, verifies the active Wayland socket, launches the setup UI on Wayland, retries through X11/XWayland on VMware when needed, avoids duplicate OOBE processes, writes a persistent launch log, and shows an on-screen error when setup cannot open. Also rewires the application-menu, KDE autostart, and systemd-user OOBE entries through the repaired launcher. Includes all Hotfix 25 update-version and persistent account-creation recovery fixes.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.26-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 26 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
