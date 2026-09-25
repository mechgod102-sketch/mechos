#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX_0315_GT730_MECHSCOPE_UPDATE_HEALTH_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BASE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.4-update.tar.zst"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.5-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
SLOT_NAME=0.3.1-hotfix.5
SLOT="$STAGE/usr/local/share/mechos/update-engine/slots/$SLOT_NAME"
RECOVERY="$STAGE/usr/local/share/mechos/update-recovery"

mkdir -p "$(dirname "$BUNDLE")"
[ -s "$BASE" ] || bash "$ROOT/scripts/build-hotfix-0.3.1-4.sh"
[ -s "$BASE" ] || { echo 'MechOS 0.3.1 Hotfix 4 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$BASE" -C "$STAGE"

mkdir -p "$SLOT" "$RECOVERY" "$STAGE/usr/local/bin"

# Permanent source-level MechScope legacy-GPU fix. Do not rely on the old
# Hotfix 1 one-shot patch marker; every future cumulative bundle now carries
# the correct session implementation directly.
install -m0755 "$ROOT/scripts/mechscope-session-v20.sh"   "$STAGE/usr/local/bin/mechscope-session"
install -m0755 "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"   "$STAGE/usr/local/bin/mechos-legacy-gpu-setup"

# New A/B Update Center slot. Protected public v38 launchers remain untouched.
install -m0755 "$ROOT/scripts/mechos-update-helper-core-v39.sh"   "$SLOT/mechos-update-helper-core"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v15.sh"   "$SLOT/mechos-update-transaction"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$SLOT/mechos-update-center-backend.py"
printf '%s\n' "$SLOT_NAME" >"$SLOT/version"

install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$RECOVERY/mechos-update-center-v8.py"

bash -n   "$STAGE/usr/local/bin/mechscope-session"   "$STAGE/usr/local/bin/mechos-legacy-gpu-setup"   "$SLOT/mechos-update-helper-core"   "$SLOT/mechos-update-transaction"
python3 -m py_compile   "$SLOT/mechos-update-center-backend.py"   "$RECOVERY/mechos-update-center-v8.py"

grep -Fq 'MECHOS_MECHSCOPE_SESSION_V24_GPU_CAPABILITY'   "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'Kernel driver in use: nouveau'   "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'Vulkan preflight failed GPU='   "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'MECHOS_INTEL_UMA_INTEGRATION_V36'   "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'gt730-mixed-generation'   "$STAGE/usr/local/bin/mechos-legacy-gpu-setup"
grep -Fq 'MECHOS_HOTFIX5_HELPER_HEALTH_FIRST_V1'   "$SLOT/mechos-update-center-backend.py"
grep -Fq 'MECHOS_UPDATE_HELPER_CORE_V39_PACKAGE_REFRESH_STATUS'   "$SLOT/mechos-update-helper-core"
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
  'version':'0.3.1-hotfix.5',
  'release_name':'MechOS v0.3.1 Hotfix 5',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'GT 730 MechScope and Update Center health-check reliability hotfix. Permanently integrates driver-aware NVIDIA handling, Intel UMA handling and Vulkan capability fallback into the source-owned MechScope session so cumulative updates cannot undo legacy GPU support. Treats GeForce GT 730 as a mixed-generation family and chooses the session path from the loaded kernel driver and Vulkan capability instead of the marketing name alone. Update Center now tests the helper itself first, invokes privileged self-repair only when helper health actually fails, and distinguishes helper failure from feed/network/signature status failures. Delivered through a new A/B updater slot without replacing protected public launchers.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.1-hotfix.5-update.tar.zst',
  'bundle_sha256':sha,
  'signature_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json.sig',
  'signing_key_id':'mechos-stable-2026-01',
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'MechOS 0.3.1 Hotfix 5 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
