#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX25_UPDATE_OOBE_RECOVERY_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.25-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H24="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.24-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H24" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-24.sh"
[ -s "$H24" ] || { echo 'Hotfix 24 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H24" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

# Critical bootstrap: older installed helpers prefer the staged v14 transaction.
# Ship Hotfix 25's self-contained engine at both compatibility paths so a
# machine still reporting Hotfix 21 can commit the new release during this very
# update, before the new helper is installed.
install -m0755 "$ROOT/scripts/mechos-update-transaction-v25.sh" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v25.sh" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
install -m0755 "$ROOT/scripts/mechos-update-helper-v25.sh" \
  "$STAGE/usr/local/bin/mechos-update-helper"
install -m0755 "$ROOT/scripts/mechos-oobe-rearm-v25.sh" \
  "$STAGE/usr/local/libexec/mechos-oobe-rearm-v25"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-25-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-25-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-25.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 25 updater completion and OOBE recovery
After=local-fs.target mechos-hotfix-0.3.0-24.service
Requires=mechos-hotfix-0.3.0-24.service
Before=mechos-oobe-rearm-v25.service sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-25-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-25-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-25.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-25.service"

cat >"$STAGE/usr/lib/systemd/system/mechos-oobe-rearm-v25.service" <<'EOF'
[Unit]
Description=Re-arm incomplete MechOS account creation until OOBE completes
After=local-fs.target mechos-hotfix-0.3.0-25.service
Requires=mechos-hotfix-0.3.0-25.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/oobe-complete

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-oobe-rearm-v25

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-oobe-rearm-v25.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-oobe-rearm-v25.service"

for f in \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v13" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/libexec/mechos-oobe-rearm-v25" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-25-apply"; do
  bash -n "$f"
done

grep -Fq 'MECHOS_UPDATE_TRANSACTION_V25_RELEASE_COMMIT_V1' "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
grep -Fq 'mv -f "$RELEASE_TMP" "$RELEASE"' "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
grep -Fq 'MECHOS_UPDATE_HELPER_V25_RELEASE_COMMIT_V1' "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'MECHOS_OOBE_REARM_V25' "$STAGE/usr/local/libexec/mechos-oobe-rearm-v25"
grep -Fq 'ConditionPathExists=!/var/lib/mechos/oobe-complete' \
  "$STAGE/usr/lib/systemd/system/mechos-oobe-rearm-v25.service"

# Preserve all cumulative account/session/update repairs from Hotfix 24.
for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-24-apply" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-23-apply" \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechos-reboot" \
  "$STAGE/usr/local/bin/mechscope-session" \
  "$STAGE/usr/local/libexec/mechos-oobe-apply"; do
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
  'version':'0.3.0-hotfix.25',
  'release_name':'MechOS v0.3.0 Hotfix 25',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative update completion and first-boot account recovery. Fixes successful updates that remained displayed as an older hotfix by atomically committing and verifying /etc/mechos/release only after the OS transaction passes postflight checks. The staged transaction is self-contained so systems stuck on Hotfix 21 can recover during the Hotfix 25 update itself while preserving the Hotfix 20 root-permission safety guard and rollback behavior. Also adds a persistent pre-login OOBE recovery guard that re-creates the temporary mechos-setup transport, SDDM route, narrow polkit authorization and graphical autostart on every boot until /var/lib/mechos/oobe-complete exists; completed systems are returned to the real-user MechScope sign-in path. Includes all Hotfix 24 fixes.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.25-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 25 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
