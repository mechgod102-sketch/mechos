#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX_0314_PACKAGE_REFRESH_STATUS_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BASE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.3-update.tar.zst"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.4-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
SLOT_NAME=0.3.1-hotfix.4
SLOT="$STAGE/usr/local/share/mechos/update-engine/slots/$SLOT_NAME"
RECOVERY="$STAGE/usr/local/share/mechos/update-recovery"

mkdir -p "$(dirname "$BUNDLE")"
[ -s "$BASE" ] || bash "$ROOT/scripts/build-hotfix-0.3.1-3.sh"
[ -s "$BASE" ] || { echo 'MechOS 0.3.1 Hotfix 3 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$BASE" -C "$STAGE"

mkdir -p "$SLOT" "$RECOVERY"

# Hotfix 4 updates only the versioned engine slot. Stable public v38 launchers
# remain the same protected bootstrap files carried by Hotfix 3.
install -m0755 "$ROOT/scripts/mechos-update-helper-core-v39.sh"   "$SLOT/mechos-update-helper-core"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v15.sh"   "$SLOT/mechos-update-transaction"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$SLOT/mechos-update-center-backend.py"
printf '%s\n' "$SLOT_NAME" >"$SLOT/version"

# Keep the independent recovery backend aligned with the current UI behavior.
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$RECOVERY/mechos-update-center-v8.py"

bash -n   "$SLOT/mechos-update-helper-core"   "$SLOT/mechos-update-transaction"
python3 -m py_compile   "$SLOT/mechos-update-center-backend.py"   "$RECOVERY/mechos-update-center-v8.py"

grep -Fq 'MECHOS_UPDATE_HELPER_CORE_V39_PACKAGE_REFRESH_STATUS'   "$SLOT/mechos-update-helper-core"
grep -Fq 'MECHOS_HOTFIX4_PACKAGE_REFRESH_RESULT_UI'   "$SLOT/mechos-update-center-backend.py"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V15_AB_ENGINE_ISOLATION_V1'   "$SLOT/mechos-update-transaction"
grep -Fq 'MECHOS_UPDATE_HELPER_AB_LAUNCHER_V38'   "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'MECHOS_UPDATE_CENTER_AB_LAUNCHER_V38'   "$STAGE/usr/local/bin/mechos-update-center"

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
  'version':'0.3.1-hotfix.4',
  'release_name':'MechOS v0.3.1 Hotfix 4',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Package refresh reliability and result-reporting update. Installs a new A/B Update Engine slot without replacing the protected public launchers. MechOS core OTA success is now reported separately from Arch and Flatpak refresh results. A pacman sync download-* Permission denied failure is repaired conservatively by clearing stale sync download directories and restoring database/sync directory permissions, then retrying once. Unrelated pacman failures are never hidden or auto-repaired. Update Center reports partial success clearly instead of saying all updates installed.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.1-hotfix.4-update.tar.zst',
  'bundle_sha256':sha,
  'signature_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json.sig',
  'signing_key_id':'mechos-stable-2026-01',
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'MechOS 0.3.1 Hotfix 4 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
