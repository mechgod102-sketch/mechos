#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.21-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H20="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.20-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H20" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-20.sh"
[ -s "$H20" ] || { echo 'Hotfix 20 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H20" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

install -m0755 "$ROOT/scripts/mechos-hotfix21-unified-store-patch.py" \
  "$STAGE/usr/local/libexec/mechos-hotfix21-unified-store-patch"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-21-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-21-apply"

# Carry the native catalog/provider helpers explicitly so Hotfix 21 never
# depends on a partial older cumulative payload.
install -m0755 "$ROOT/scripts/mechos-game-catalog-v15.py" \
  "$STAGE/usr/local/libexec/mechos-game-catalog-v15"
install -m0755 "$ROOT/scripts/mechos-provider-bootstrap-v15.sh" \
  "$STAGE/usr/local/libexec/mechos-provider-bootstrap-v15"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-21.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 21 native Unified Store repair
After=local-fs.target mechos-hotfix-0.3.0-20.service
Requires=mechos-hotfix-0.3.0-20.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-21-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-21-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sf /usr/lib/systemd/system/mechos-hotfix-0.3.0-21.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-21.service"

python3 -m py_compile \
  "$STAGE/usr/local/libexec/mechos-hotfix21-unified-store-patch" \
  "$STAGE/usr/local/libexec/mechos-game-catalog-v15"
bash -n \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-21-apply" \
  "$STAGE/usr/local/libexec/mechos-provider-bootstrap-v15"

grep -Fq 'MECHOS_HOTFIX21_UNIFIED_STORE_PATCH' "$STAGE/usr/local/libexec/mechos-hotfix21-unified-store-patch"
grep -Fq 'MECHOS_HOTFIX21_APPLY_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-21-apply"
grep -Fq 'After=local-fs.target mechos-hotfix-0.3.0-20.service' "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-21.service"

# The cumulative bundle must retain the root-safe transaction and public updater trio.
for required in \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/bin/mechos-reboot" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-20-apply"; do
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
  'version':'0.3.0-hotfix.21',
  'release_name':'MechOS v0.3.0 Hotfix 21',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Unified Store native-page repair. Replaces the legacy V5 Store class that still opened desktop-browser URLs with a redesigned in-shell game browser. Search results render directly inside Unified Store, provider filters stay in MechOS, compatibility help is internal, Steam game launch uses the native Steam client, and missing Steam/Heroic providers are bootstrapped only when an explicit provider action is chosen. Hotfix 21 is cumulative with Hotfixes 15-20 including root-safe updates, Creator Mode direct launch, hardware MechScope fallback, and updater recovery.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.21-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 21 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
