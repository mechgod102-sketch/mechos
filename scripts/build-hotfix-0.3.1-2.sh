#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX_0312_UPDATE_SELF_REPAIR_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BASE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.1-update.tar.zst"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.2-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
RECOVERY="$STAGE/usr/local/share/mechos/update-recovery"

mkdir -p "$(dirname "$BUNDLE")"
[ -s "$BASE" ] || bash "$ROOT/scripts/build-hotfix-0.3.1-1.sh"
[ -s "$BASE" ] || { echo 'MechOS 0.3.1 Hotfix 1 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$BASE" -C "$STAGE"

mkdir -p   "$STAGE/usr/local/bin"   "$STAGE/usr/local/libexec"   "$RECOVERY"   "$STAGE/usr/lib/systemd/system"   "$STAGE/etc/systemd/system/multi-user.target.wants"

# Reassert the current signed updater and patched Update Center backend.
install -m0755 "$ROOT/scripts/mechos-update-helper-v37.sh"   "$STAGE/usr/local/bin/mechos-update-helper"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$STAGE/usr/local/libexec/mechos-update-center-v8-rescue.py"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v14.sh"   "$STAGE/usr/local/libexec/mechos-update-transaction-v14"

# Trusted local recovery payload. These are deliberately stored separately from
# the public entry points so a damaged public updater can restore itself without
# downloading unsigned replacement scripts from the network.
install -m0755 "$ROOT/scripts/mechos-update-helper-v37.sh"   "$RECOVERY/mechos-update-helper-v37.sh"
install -m0755 "$ROOT/scripts/mechos-update-center-rescue-launcher-v0312.sh"   "$RECOVERY/mechos-update-center"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$RECOVERY/mechos-update-center-v8.py"
install -m0755 "$ROOT/scripts/mechos-reboot-v14.sh"   "$RECOVERY/mechos-reboot"
install -m0644 "$ROOT/updates/mechos-update-signing-public.pem"   "$RECOVERY/mechos-update-signing-public.pem"

install -m0755 "$ROOT/scripts/mechos-update-self-repair-v0312.sh"   "$STAGE/usr/local/libexec/mechos-update-self-repair-v0312"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.1-2-apply.sh"   "$STAGE/usr/local/libexec/mechos-hotfix-0.3.1-2-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-update-self-repair.service" <<'EOF'
[Unit]
Description=Verify and repair MechOS Update Center critical files
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-update-self-repair-v0312 --repair
EOF

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.1-2.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.1 Hotfix 2 Update Center self-repair
After=local-fs.target mechos-update-self-repair.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.1-2-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.1-2-apply

[Install]
WantedBy=multi-user.target
EOF

ln -sfn /usr/lib/systemd/system/mechos-update-self-repair.service   "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-update-self-repair.service"
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.1-2.service   "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.1-2.service"

bash -n   "$STAGE/usr/local/bin/mechos-update-helper"   "$STAGE/usr/local/libexec/mechos-update-transaction-v14"   "$STAGE/usr/local/libexec/mechos-update-self-repair-v0312"   "$STAGE/usr/local/libexec/mechos-hotfix-0.3.1-2-apply"   "$RECOVERY/mechos-update-center"   "$RECOVERY/mechos-reboot"
python3 -m py_compile   "$STAGE/usr/local/libexec/mechos-update-center-v8.py"   "$RECOVERY/mechos-update-center-v8.py"

grep -Fq 'MECHOS_UPDATE_SELF_REPAIR_V0312'   "$STAGE/usr/local/libexec/mechos-update-self-repair-v0312"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14_0312_SELF_REPAIR_V1'   "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
grep -Fq 'mechos-update-self-repair-v0312'   "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
grep -Fq 'MECHOS_UPDATE_HELPER_V37_SIGNED_MANIFEST_V1'   "$RECOVERY/mechos-update-helper-v37.sh"
openssl pkey -pubin -in "$RECOVERY/mechos-update-signing-public.pem" -noout

for required in   "$STAGE/usr/local/bin/mechos-update-center"   "$STAGE/usr/local/bin/mechos-update-helper"   "$STAGE/usr/local/bin/mechos-reboot"   "$STAGE/usr/local/libexec/mechos-update-transaction-v14"   "$STAGE/usr/local/libexec/mechos-update-self-repair-v0312"   "$STAGE/usr/local/bin/mechos-legacy-gpu-setup"; do
  [ -e "$required" ] || { echo "Cumulative component missing: $required" >&2; exit 1; }
done

DAY="$(date -u +%F)"
EPOCH="$(date -u -d "$DAY 00:00:00" +%s)"
rm -f "$BUNDLE" "$SUM"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner   --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.1-hotfix.2',
  'release_name':'MechOS v0.3.1 Hotfix 2',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Update Center self-repair hotfix. Adds a trusted local recovery payload for the signed update helper, Update Center launcher/backend, reboot helper and signing public key; verifies and repairs missing or non-executable updater components at boot and from the Update Center GUI; restores a missing pinned signing key while refusing silent replacement of a mismatched key; and runs recovery before transaction postflight so damaged updater files can no longer make an otherwise valid cumulative update roll back.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.1-hotfix.2-update.tar.zst',
  'bundle_sha256':sha,
  'signature_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json.sig',
  'signing_key_id':'mechos-stable-2026-01',
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'MechOS 0.3.1 Hotfix 2 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
