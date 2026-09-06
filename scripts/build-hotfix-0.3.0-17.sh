#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.17-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H16="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.16-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

# Hotfix 17 remains cumulative with the Creator/Store and single-window fixes.
bash "$ROOT/scripts/build-hotfix-0.3.0-16.sh"
[ -s "$H16" ] || { echo 'Hotfix 16 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H16" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

# Replace the path used by the installed v14 helper with the rsync-free v14
# transaction engine. Keep an explicit v14 copy for diagnostics/future helper
# migrations as well.
install -m0755 "$ROOT/scripts/mechos-update-transaction-v14.sh" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v14.sh" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
install -m0755 "$ROOT/scripts/mechos-hotfix17-updater-patch.py" \
  "$STAGE/usr/local/libexec/mechos-hotfix17-updater-patch"
install -m0755 "$ROOT/scripts/mechos-clear-reboot-required-v17.sh" \
  "$STAGE/usr/local/libexec/mechos-clear-reboot-required-v17"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-17-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-17-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-17.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 17 updater runtime repair
After=local-fs.target mechos-hotfix-0.3.0-16.service
Requires=mechos-hotfix-0.3.0-16.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-17-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-17-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-17.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-17.service"

cat >"$STAGE/usr/lib/systemd/system/mechos-reboot-required-clear-v17.service" <<'EOF'
[Unit]
Description=Clear satisfied MechOS update restart state
After=mechos-hotfix-0.3.0-17.service
Requires=mechos-hotfix-0.3.0-17.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-clear-reboot-required-v17

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-reboot-required-clear-v17.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-reboot-required-clear-v17.service"

bash -n "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
bash -n "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
bash -n "$STAGE/usr/local/libexec/mechos-clear-reboot-required-v17"
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-17-apply"
python3 -m py_compile "$STAGE/usr/local/libexec/mechos-hotfix17-updater-patch"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
! grep -Eq '^[[:space:]]*rsync[[:space:]]' "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
grep -Fq 'MECHOS_HOTFIX17_UPDATER_PATCH' "$STAGE/usr/local/libexec/mechos-hotfix17-updater-patch"
grep -Fq 'After=local-fs.target mechos-hotfix-0.3.0-16.service' "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-17.service"

# Keep bundle mtimes deterministic and safely behind the build time. This
# prevents a slightly lagging VirtualBox guest clock from filling Update Center
# with harmless "time stamp ... in the future" warnings.
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
  'version':'0.3.0-hotfix.17',
  'release_name':'MechOS v0.3.0 Hotfix 17',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Updater runtime repair. Replaces the transaction engine with a base-system-only tar copy path so future MechOS updates do not depend on rsync and cannot fail with shell exit 127 when rsync is absent. Future bundle extraction suppresses harmless guest-clock timestamp warnings, failed installs no longer display a contradictory success message, and reboot-required state is cleared after the requested restart is actually completed. Hotfix 17 is cumulative and retains the Hotfix 15 Creator/Unified Store repairs and Hotfix 16 single-window MechOS shell.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.17-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 17 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
