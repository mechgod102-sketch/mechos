#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.20-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H19="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.19-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

bash "$ROOT/scripts/build-hotfix-0.3.0-19.sh"
[ -s "$H19" ] || { echo 'Hotfix 19 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H19" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

# Keep the proven v14 transaction implementation as the core, but never expose
# it directly again. The v20 wrapper normalizes the stage-root metadata before
# invoking it and restores/verifies `/` afterward.
install -m0755 "$ROOT/scripts/mechos-update-transaction-v14.sh" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-core-v20"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v20.sh" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v20.sh" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-20-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-20-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-20.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 20 root-permission transaction safety repair
After=local-fs.target mechos-hotfix-0.3.0-19.service
Requires=mechos-hotfix-0.3.0-19.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-20-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-20-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-20.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-20.service"

for f in \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v13" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-core-v20" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-20-apply"; do
  bash -n "$f"
done

grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$STAGE/usr/local/libexec/mechos-update-transaction-core-v20"
grep -Fq 'chmod "$ROOT_MODE" "$STAGE"' "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
grep -Fq 'chmod "$ROOT_MODE" /' "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
grep -Fq 'After=local-fs.target mechos-hotfix-0.3.0-19.service' "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-20.service"

# Keep Hotfix 19 recovery/mode repairs in the cumulative payload.
for required in \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/bin/mechos-reboot" \
  "$STAGE/usr/local/bin/mechos-update-rescue" \
  "$STAGE/usr/local/bin/mechos-mode-launch" \
  "$STAGE/usr/local/bin/mechscope-session" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-19-apply"; do
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
  'version':'0.3.0-hotfix.20',
  'release_name':'MechOS v0.3.0 Hotfix 20',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Critical update transaction safety repair. Prevents mktemp staging-directory permissions from being applied to the installed root directory during tar-based updates, restores and verifies root-directory metadata after every transaction, and refuses to report success if normal users could lose root traversal. Hotfix 20 is cumulative with Hotfixes 15-19, including updater rescue, Creator Mode direct launch and hardware MechScope fallback repairs.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.20-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 20 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
