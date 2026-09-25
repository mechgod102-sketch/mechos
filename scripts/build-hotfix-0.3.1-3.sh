#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX_0313_AB_UPDATE_ENGINE_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BASE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.2-update.tar.zst"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.3-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
SLOT_NAME=0.3.1-hotfix.3
ENGINE="$STAGE/usr/local/share/mechos/update-engine"
SLOT="$ENGINE/slots/$SLOT_NAME"
RECOVERY="$STAGE/usr/local/share/mechos/update-recovery"

mkdir -p "$(dirname "$BUNDLE")"
[ -s "$BASE" ] || bash "$ROOT/scripts/build-hotfix-0.3.1-2.sh"
[ -s "$BASE" ] || { echo 'MechOS 0.3.1 Hotfix 2 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$BASE" -C "$STAGE"

mkdir -p   "$STAGE/usr/local/bin"   "$STAGE/usr/local/libexec"   "$STAGE/usr/local/share/mechos/update-engine/slots"   "$SLOT" "$RECOVERY"   "$STAGE/usr/lib/systemd/system"   "$STAGE/etc/systemd/system/multi-user.target.wants"

# Stable public bootstrap launchers. Transaction v15 installs these only for
# pre-A/B systems or when a launcher is missing/corrupt; healthy v38 launchers
# are protected from ordinary future hotfixes.
install -m0755 "$ROOT/scripts/mechos-update-helper-launcher-v38.sh"   "$STAGE/usr/local/bin/mechos-update-helper"
install -m0755 "$ROOT/scripts/mechos-update-center-launcher-v38.sh"   "$STAGE/usr/local/bin/mechos-update-center"
install -m0755 "$ROOT/scripts/mechos-reboot-v14.sh"   "$STAGE/usr/local/bin/mechos-reboot"

# New engine slot. The active slot is selected only after all slot files pass
# syntax/contract validation.
install -m0755 "$ROOT/scripts/mechos-update-helper-core-v38.sh"   "$SLOT/mechos-update-helper-core"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v15.sh"   "$SLOT/mechos-update-transaction"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$SLOT/mechos-update-center-backend.py"
printf '%s\n' "$SLOT_NAME" >"$SLOT/version"

# Old helpers need a familiar staged transaction filename to migrate into A/B.
# The file carries both V14 compatibility and V15 isolation markers.
install -m0755 "$ROOT/scripts/mechos-update-transaction-v15.sh"   "$STAGE/usr/local/libexec/mechos-update-transaction-v14"

install -m0755 "$ROOT/scripts/mechos-update-engine-switch-v38.sh"   "$STAGE/usr/local/libexec/mechos-update-engine-switch-v38"
install -m0755 "$ROOT/scripts/mechos-update-self-repair-v0313.sh"   "$STAGE/usr/local/libexec/mechos-update-self-repair-v0313"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.1-3-apply.sh"   "$STAGE/usr/local/libexec/mechos-hotfix-0.3.1-3-apply"

# Recovery copies are independent of the active slot.
install -m0755 "$ROOT/scripts/mechos-update-helper-launcher-v38.sh"   "$RECOVERY/mechos-update-helper-launcher-v38"
install -m0755 "$ROOT/scripts/mechos-update-center-launcher-v38.sh"   "$RECOVERY/mechos-update-center-launcher-v38"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$RECOVERY/mechos-update-center-v8.py"
install -m0755 "$ROOT/scripts/mechos-update-helper-v37.sh"   "$RECOVERY/mechos-update-helper-v37.sh"
install -m0755 "$ROOT/scripts/mechos-reboot-v14.sh"   "$RECOVERY/mechos-reboot"
install -m0644 "$ROOT/updates/mechos-update-signing-public.pem"   "$RECOVERY/mechos-update-signing-public.pem"

cat >"$STAGE/usr/lib/systemd/system/mechos-update-self-repair.service" <<'EOF'
[Unit]
Description=Verify and recover MechOS A/B Update Engine
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-update-self-repair-v0313 --repair
EOF

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.1-3.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.1 Hotfix 3 A/B Update Engine migration
After=local-fs.target mechos-update-self-repair.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.1-3-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.1-3-apply

[Install]
WantedBy=multi-user.target
EOF

ln -sfn /usr/lib/systemd/system/mechos-update-self-repair.service   "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-update-self-repair.service"
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.1-3.service   "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.1-3.service"

bash -n   "$STAGE/usr/local/bin/mechos-update-helper"   "$STAGE/usr/local/bin/mechos-update-center"   "$SLOT/mechos-update-helper-core"   "$SLOT/mechos-update-transaction"   "$STAGE/usr/local/libexec/mechos-update-engine-switch-v38"   "$STAGE/usr/local/libexec/mechos-update-self-repair-v0313"   "$STAGE/usr/local/libexec/mechos-hotfix-0.3.1-3-apply"
python3 -m py_compile "$SLOT/mechos-update-center-backend.py"

grep -Fq 'MECHOS_UPDATE_HELPER_AB_LAUNCHER_V38' "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'MECHOS_UPDATE_CENTER_AB_LAUNCHER_V38' "$STAGE/usr/local/bin/mechos-update-center"
grep -Fq 'MECHOS_UPDATE_HELPER_CORE_V38_AB_ENGINE' "$SLOT/mechos-update-helper-core"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V15_AB_ENGINE_ISOLATION_V1' "$SLOT/mechos-update-transaction"
grep -Fq 'MECHOS_UPDATE_ENGINE_SWITCH_V38' "$STAGE/usr/local/libexec/mechos-update-engine-switch-v38"
grep -Fq 'MECHOS_UPDATE_SELF_REPAIR_V0313_AB_ENGINE' "$STAGE/usr/local/libexec/mechos-update-self-repair-v0313"

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
  'version':'0.3.1-hotfix.3',
  'release_name':'MechOS v0.3.1 Hotfix 3',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'A/B Update Engine isolation hotfix. Migrates Update Center to stable public launchers plus versioned engine slots. Ordinary cumulative hotfixes can no longer overwrite a healthy active update helper or Update Center launcher. Engine changes are validated in a new slot and activated atomically; the previous slot is retained for recovery and transaction rollback restores the prior engine link if postflight fails. Includes A/B-aware self-repair and keeps Hotfix 1 legacy GPU and Hotfix 2 updater recovery features.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.1-hotfix.3-update.tar.zst',
  'bundle_sha256':sha,
  'signature_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json.sig',
  'signing_key_id':'mechos-stable-2026-01',
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'MechOS 0.3.1 Hotfix 3 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
