#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HARDWARE_FOLLOW_STABLE_V1

PHASE="${1:-final}"
[ "$PHASE" = final ] || exit 0

ROOT=/workspace/archlive/airootfs
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
MANIFEST=/workspace/updates/stable.json
BUNDLES=/workspace/updates/bundles
BASELINE_VERSION=0.3.0-hotfix.22.6

log(){ printf '[MechOS Hardware Stable Follow] %s\n' "$*"; }
fail(){ printf '[MechOS Hardware Stable Follow] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Hardware Stable Follow] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -s "$ARCHIVE" ] || fail "final installed-system payload is missing"
[ -s "$MANIFEST" ] || fail "updates/stable.json is missing"

mapfile -t META < <(python3 - "$MANIFEST" "$BASELINE_VERSION" <<'PY'
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

manifest = Path(sys.argv[1])
baseline = sys.argv[2]
data = json.loads(manifest.read_text(encoding="utf-8"))

if data.get("channel") != "stable":
    raise SystemExit("stable manifest channel is not 'stable'")

version = str(data.get("version", "")).strip()
sha = str(data.get("bundle_sha256", "")).strip().lower()
url = str(data.get("bundle_url", "")).strip()

pattern = re.compile(r"^0\.3\.0-hotfix\.(\d+(?:\.\d+)*)$")
def key(value: str):
    match = pattern.fullmatch(value)
    if not match:
        raise SystemExit(f"unsupported MechOS hotfix version: {value!r}")
    return tuple(int(part) for part in match.group(1).split("."))

if key(version) < key(baseline):
    raise SystemExit(f"stable target {version} is older than hardware baseline {baseline}")
if not re.fullmatch(r"[0-9a-f]{64}", sha):
    raise SystemExit("stable manifest bundle_sha256 is invalid")

name = Path(urlparse(url).path).name
expected_name = f"MechOS-{version}-update.tar.zst"
if name != expected_name:
    raise SystemExit(f"stable bundle URL basename {name!r} != {expected_name!r}")

suffix = version.split("hotfix.", 1)[1]
service_tag = suffix.split(".", 1)[0]
print(version)
print(sha)
print(name)
print(service_tag)
print(suffix)
PY
)

[ "${#META[@]}" -eq 5 ] || fail "could not resolve stable manifest metadata"
STABLE_VERSION="${META[0]}"
STABLE_SHA="${META[1]}"
BUNDLE_NAME="${META[2]}"
SERVICE_TAG="${META[3]}"
MARKER_SUFFIX="${META[4]}"
BUNDLE="$BUNDLES/$BUNDLE_NAME"
SUM="$BUNDLE.sha256"

[ -s "$BUNDLE" ] || fail "stable bundle is not present in checkout: $BUNDLE_NAME"
actual_sha="$(sha256sum "$BUNDLE" | awk '{print $1}')"
[ "$actual_sha" = "$STABLE_SHA" ] || fail "stable bundle SHA mismatch: manifest=$STABLE_SHA local=$actual_sha"
if [ -s "$SUM" ]; then
  (
    cd "$BUNDLES"
    sha256sum -c "$(basename "$SUM")"
  )
fi

# Refuse path traversal before overlaying the current stable bundle.
while IFS= read -r rel; do
  case "$rel" in
    /*) fail "absolute path in stable bundle: $rel" ;;
  esac
  clean="${rel#./}"
  case "/$clean/" in
    */../*) fail "parent traversal in stable bundle: $rel" ;;
  esac
done < <(tar --zstd -tf "$BUNDLE")

STAGE="$(mktemp -d /tmp/mechos-hardware-follow-stable.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

tar --warning=no-timestamp --zstd -xpf "$ARCHIVE" -C "$STAGE"

# The prior hardware seed guarantees 22.6 is the minimum installed filesystem
# state. Stamp that baseline before adding a newer published cumulative bundle,
# so a failed later first-boot service can never leave this image identifying
# itself as the old Hotfix 21 base.
mkdir -p "$STAGE/etc/mechos"
printf '%s\n' "$BASELINE_VERSION" >"$STAGE/etc/mechos/release"
if [ -f "$STAGE/etc/mechos/mechos.conf" ]; then
  if grep -q '^MECHOS_VERSION=' "$STAGE/etc/mechos/mechos.conf"; then
    sed -i "s/^MECHOS_VERSION=.*/MECHOS_VERSION=$BASELINE_VERSION/" "$STAGE/etc/mechos/mechos.conf"
  else
    printf 'MECHOS_VERSION=%s\n' "$BASELINE_VERSION" >>"$STAGE/etc/mechos/mechos.conf"
  fi
fi
printf 'MechOS v%s\n' "$BASELINE_VERSION" >"$STAGE/etc/system-release"

# Every stable bundle is cumulative. Overlay the manifest-selected stable target
# after the 22.6 hardware baseline and after the account repair so newer fixes
# are authoritative in fresh hardware installs.
tar --warning=no-timestamp --zstd -xpf "$BUNDLE" -C "$STAGE"

LATEST_SERVICE="/usr/lib/systemd/system/mechos-hotfix-0.3.0-${SERVICE_TAG}.service"
LATEST_MARKER="/var/lib/mechos/hotfix-0.3.0-${MARKER_SUFFIX}-applied"
[ -f "$STAGE$LATEST_SERVICE" ] || fail "stable activation service missing: $LATEST_SERVICE"
mkdir -p "$STAGE/etc/systemd/system/multi-user.target.wants"
ln -sfn "$LATEST_SERVICE" \
  "$STAGE/etc/systemd/system/multi-user.target.wants/$(basename "$LATEST_SERVICE")"

# A fresh ISO is not processed through the normal update transaction. Commit
# its release identity only after the newest stable activation service succeeds.
# This preserves Hotfix 25's rule that /etc/mechos/release must not advance
# before postflight/activation has actually completed.
COMMIT_HELPER="$STAGE/usr/local/libexec/mechos-hardware-stable-release-commit"
COMMIT_SERVICE="$STAGE/usr/lib/systemd/system/mechos-hardware-stable-release-commit.service"
install -d -m0755 "$(dirname "$COMMIT_HELPER")" "$(dirname "$COMMIT_SERVICE")"

cat >"$COMMIT_HELPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HARDWARE_STABLE_RELEASE_COMMIT_V1
EXPECTED_VERSION='$STABLE_VERSION'
EXPECTED_MARKER='$LATEST_MARKER'
STATE=/var/lib/mechos
RELEASE=/etc/mechos/release
CONF=/etc/mechos/mechos.conf
SYSTEM_RELEASE=/etc/system-release

[ -f "\$STATE/installed" ] || exit 0
[ -e "\$EXPECTED_MARKER" ] || {
  printf '[MechOS Hardware Stable] newest stable marker missing: %s\n' "\$EXPECTED_MARKER" >&2
  exit 1
}

mkdir -p /etc/mechos
tmp="\$(mktemp /etc/mechos/.release.XXXXXX)"
printf '%s\n' "\$EXPECTED_VERSION" >"\$tmp"
chmod 0644 "\$tmp"
mv -f "\$tmp" "\$RELEASE"

if [ -f "\$CONF" ]; then
  if grep -q '^MECHOS_VERSION=' "\$CONF"; then
    sed -i "s/^MECHOS_VERSION=.*/MECHOS_VERSION=\$EXPECTED_VERSION/" "\$CONF"
  else
    printf 'MECHOS_VERSION=%s\n' "\$EXPECTED_VERSION" >>"\$CONF"
  fi
fi
printf 'MechOS v%s\n' "\$EXPECTED_VERSION" >"\$SYSTEM_RELEASE"
printf '%s\n' "\$EXPECTED_VERSION" >"\$STATE/hardware-stable-release-committed"
EOF
chmod 0755 "$COMMIT_HELPER"
bash -n "$COMMIT_HELPER"

cat >"$COMMIT_SERVICE" <<EOF
[Unit]
Description=Commit the MechOS hardware image to the newest published stable release
After=$(basename "$LATEST_SERVICE")
Requires=$(basename "$LATEST_SERVICE")
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hardware-stable-release-commit

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hardware-stable-release-commit.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hardware-stable-release-commit.service"

# Persist the exact stable target used by this build. The verifier reads this so
# it accepts future stable targets instead of being permanently pinned to 22.6.
mkdir -p "$STAGE/etc/mechos" "$ROOT/etc/mechos" \
  "$STAGE/usr/share/mechos/hardware-test" "$ROOT/usr/share/mechos/hardware-test"
for tree in "$STAGE" "$ROOT"; do
  cat >"$tree/etc/mechos/hardware-test-build" <<EOF
channel=hardware-validation
baseline=$BASELINE_VERSION
stable_target=$STABLE_VERSION
stable_bundle=$BUNDLE_NAME
stable_bundle_sha256=$STABLE_SHA
first_boot_activation=$(basename "$LATEST_SERVICE")
release_commit=mechos-hardware-stable-release-commit.service
EOF
  cp -f "$MANIFEST" "$tree/usr/share/mechos/hardware-test/stable.json"
done

TMP="$ARCHIVE.hardware-stable-current"
tar --zstd -cpf "$TMP" -C "$STAGE" .
mv -f "$TMP" "$ARCHIVE"

tar --zstd -tf "$ARCHIVE" "./usr/lib/systemd/system/$(basename "$LATEST_SERVICE")" >/dev/null
tar --zstd -tf "$ARCHIVE" ./usr/local/libexec/mechos-hardware-stable-release-commit >/dev/null
tar --zstd -tf "$ARCHIVE" ./usr/lib/systemd/system/mechos-hardware-stable-release-commit.service >/dev/null
tar --zstd -tf "$ARCHIVE" ./etc/mechos/hardware-test-build >/dev/null

log "hardware baseline: $BASELINE_VERSION"
log "manifest-selected stable target: $STABLE_VERSION"
log "stable bundle verified: $BUNDLE_NAME ($STABLE_SHA)"
log "release identity will advance to $STABLE_VERSION only after $(basename "$LATEST_SERVICE") succeeds"
