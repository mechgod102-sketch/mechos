#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HARDWARE_STABLE_SEED_V22_6

PHASE="${1:-final}"
[ "$PHASE" = final ] || exit 0

ROOT=/workspace/archlive/airootfs
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
BUNDLE=/workspace/updates/bundles/MechOS-0.3.0-hotfix.22.6-update.tar.zst
SUM="$BUNDLE.sha256"
MANIFEST=/workspace/updates/stable.json
VERIFY=/workspace/scripts/mechos-hardware-verify-v22.sh
EXPECTED_VERSION=0.3.0-hotfix.22.6
EXPECTED_SHA=0e4f838d070be7343ab65ccbe5c3e06f75af84067ecd852cf87df9b13fc1e106

log(){ printf '[MechOS Hardware Stable] %s\n' "$*"; }
fail(){ printf '[MechOS Hardware Stable] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Hardware Stable] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -d "$ROOT" ] || fail "ArchISO rootfs is missing"
[ -s "$ARCHIVE" ] || fail "final installed-system payload is missing"
[ -s "$BUNDLE" ] || fail "Hotfix 22.6 cumulative bundle is missing"
[ -s "$SUM" ] || fail "Hotfix 22.6 checksum is missing"
[ -s "$MANIFEST" ] || fail "stable manifest is missing"
[ -f "$VERIFY" ] || fail "hardware verification tool source is missing"

python3 - "$MANIFEST" "$EXPECTED_VERSION" "$EXPECTED_SHA" <<'PY'
import json,sys
from pathlib import Path
manifest=Path(sys.argv[1])
expected_version=sys.argv[2]
expected_sha=sys.argv[3]
data=json.loads(manifest.read_text(encoding='utf-8'))
assert data.get('channel') == 'stable', data
assert data.get('version') == expected_version, data
assert data.get('bundle_sha256') == expected_sha, data
assert data.get('requires_reboot') is True, data
PY

actual_sha="$(sha256sum "$BUNDLE" | awk '{print $1}')"
[ "$actual_sha" = "$EXPECTED_SHA" ] || fail "Hotfix 22.6 bundle SHA mismatch: $actual_sha"
(
  cd "$(dirname "$BUNDLE")"
  sha256sum -c "$(basename "$SUM")"
)

# Never unpack an unexpected path from a release bundle into the install root.
while IFS= read -r rel; do
  case "$rel" in
    /*) fail "absolute path in Hotfix 22.6 bundle: $rel" ;;
  esac
  clean="${rel#./}"
  case "/$clean/" in
    */../*) fail "parent traversal in Hotfix 22.6 bundle: $rel" ;;
  esac
done < <(tar --zstd -tf "$BUNDLE")

STAGE="$(mktemp -d /tmp/mechos-hardware-stable.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

tar --warning=no-timestamp --zstd -xpf "$ARCHIVE" -C "$STAGE"
tar --warning=no-timestamp --zstd -xpf "$BUNDLE" -C "$STAGE"

# The cumulative 22.6 service owns activation on this fresh hardware image.
# Disable retired/intermediate hotfix service wants so older patchers do not
# replay independently before the final-state 22.6 reconciler runs.
mkdir -p "$STAGE/etc/systemd/system/multi-user.target.wants"
for n in 14 15 16 17 18 19 20 21; do
  rm -f "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-${n}.service"
done
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-22.service"

install -D -m0755 "$VERIFY" "$STAGE/usr/local/bin/mechos-hardware-verify"
install -D -m0755 "$VERIFY" "$ROOT/usr/local/bin/mechos-hardware-verify"

mkdir -p "$STAGE/etc/mechos" "$ROOT/etc/mechos" \
  "$STAGE/usr/share/mechos/hardware-test" "$ROOT/usr/share/mechos/hardware-test"
cat >"$STAGE/etc/mechos/hardware-test-build" <<EOF
channel=hardware-validation
stable=$EXPECTED_VERSION
bundle_sha256=$EXPECTED_SHA
first_boot_activation=mechos-hotfix-0.3.0-22.service
EOF
cp -f "$STAGE/etc/mechos/hardware-test-build" "$ROOT/etc/mechos/hardware-test-build"
cp -f "$MANIFEST" "$STAGE/usr/share/mechos/hardware-test/stable.json"
cp -f "$MANIFEST" "$ROOT/usr/share/mechos/hardware-test/stable.json"
cp -f "$SUM" "$STAGE/usr/share/mechos/hardware-test/MechOS-0.3.0-hotfix.22.6-update.tar.zst.sha256"
cp -f "$SUM" "$ROOT/usr/share/mechos/hardware-test/MechOS-0.3.0-hotfix.22.6-update.tar.zst.sha256"

# Contracts required before we trust this payload as a hardware candidate.
[ -x "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-22-apply" ] || fail "Hotfix 22.6 apply helper missing from installed payload"
[ -f "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service" ] || fail "Hotfix 22.6 activation service missing"
grep -Fq 'ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-22.6-applied' \
  "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service"
grep -Fq 'Before=sddm.service display-manager.service' \
  "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service"
grep -Fq 'MECHOS_HOTFIX22_APPLY_V8' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-22-apply"
grep -Fq 'MECHOS_HOTFIX22_CREATOR_EXTERNAL_QT_HANDOFF_V26' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-22-apply"
grep -Fq 'MECHOS_CREATOR_EXTERNAL_QT_HANDOFF_V26' "$STAGE/usr/local/bin/mechos-mode-launch"
grep -Fq 'MECHOS_CREATOR_EXTERNAL_QT_HANDOFF_V26' "$STAGE/usr/local/bin/mechos-shell-route"
grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_V26' "$STAGE/usr/local/libexec/mechos-mechscope-runtime-v23"
grep -Fq 'MECHOS_MECHSCOPE_REFERENCE_COMPAT_V25' "$STAGE/usr/local/share/mechos/ui/mechscope_reference_compat_v25.py"

for n in 14 15 16 17 18 19 20 21; do
  [ ! -e "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-${n}.service" ] \
    || fail "retired/intermediate Hotfix $n is still enabled in fresh hardware payload"
done
[ -L "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-22.service" ] \
  || fail "Hotfix 22.6 activation service is not enabled"

# Rebuild the installer payload after the normal final payload synchronization.
TMP="$ARCHIVE.hardware-22.6"
tar --zstd -cpf "$TMP" -C "$STAGE" .
mv -f "$TMP" "$ARCHIVE"

tar --zstd -tf "$ARCHIVE" ./usr/local/bin/mechos-hardware-verify >/dev/null
tar --zstd -tf "$ARCHIVE" ./usr/local/libexec/mechos-hotfix-0.3.0-22-apply >/dev/null
tar --zstd -tf "$ARCHIVE" ./etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-22.service >/dev/null
tar --zstd -tf "$ARCHIVE" ./etc/mechos/hardware-test-build >/dev/null

log "installed payload seeded with verified $EXPECTED_VERSION cumulative runtime"
log "only Hotfix 22.6 cumulative activation is enabled for first installed boot"
log "hardware verifier installed as /usr/local/bin/mechos-hardware-verify in Live and installed systems"
