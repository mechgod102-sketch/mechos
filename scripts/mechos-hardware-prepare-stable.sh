#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HARDWARE_PREPARE_STABLE_V1

PHASE="${1:-final}"
[ "$PHASE" = final ] || exit 0

ROOT=/workspace
MANIFEST="$ROOT/updates/stable.json"
BUNDLES="$ROOT/updates/bundles"
BASELINE_VERSION=0.3.0-hotfix.22.6
REQUESTED_VERSION="${MECHOS_HARDWARE_TARGET_VERSION:-}"

log(){ printf '[MechOS Hardware Prepare Stable] %s\n' "$*"; }
fail(){ printf '[MechOS Hardware Prepare Stable] ERROR: %s\n' "$*" >&2; exit 1; }

[ -s "$MANIFEST" ] || fail "updates/stable.json is missing"

version_ge(){
  python3 - "$1" "$2" <<'PY'
import re,sys
pat=re.compile(r'^0\.3\.0-hotfix\.(\d+(?:\.\d+)*)$')
def key(v):
    m=pat.fullmatch(v)
    if not m:
        raise SystemExit(2)
    return tuple(int(x) for x in m.group(1).split('.'))
raise SystemExit(0 if key(sys.argv[1]) >= key(sys.argv[2]) else 1)
PY
}

manifest_version(){
  python3 - "$MANIFEST" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
data=json.loads(p.read_text(encoding='utf-8'))
if data.get('channel') != 'stable':
    raise SystemExit("stable manifest channel is not 'stable'")
print(str(data.get('version','')).strip())
PY
}

TARGET="$(manifest_version)"
[ -n "$TARGET" ] || fail "stable manifest has no version"
version_ge "$TARGET" "$BASELINE_VERSION" || fail "stable target $TARGET is older than hardware baseline $BASELINE_VERSION"

# Optional explicit hardware target is intended for validating the next hotfix
# before/while it is being promoted. It is never silently substituted: a real
# build script for that exact hotfix must exist.
if [ -n "$REQUESTED_VERSION" ] && [ "$REQUESTED_VERSION" != "$TARGET" ]; then
  version_ge "$REQUESTED_VERSION" "$BASELINE_VERSION" || fail "requested target $REQUESTED_VERSION is older than $BASELINE_VERSION"
  BUILDER="$ROOT/scripts/build-hotfix-${REQUESTED_VERSION}.sh"
  [ -x "$BUILDER" ] || [ -f "$BUILDER" ] || fail "requested target $REQUESTED_VERSION has no build script: $BUILDER"
  log "building explicitly requested hardware target $REQUESTED_VERSION"
  bash "$BUILDER"
  TARGET="$(manifest_version)"
  [ "$TARGET" = "$REQUESTED_VERSION" ] || fail "builder promoted $TARGET instead of requested $REQUESTED_VERSION"
fi

resolve_bundle(){
  python3 - "$MANIFEST" <<'PY'
import json,re,sys
from pathlib import Path
from urllib.parse import urlparse
p=Path(sys.argv[1])
data=json.loads(p.read_text(encoding='utf-8'))
version=str(data.get('version','')).strip()
sha=str(data.get('bundle_sha256','')).strip().lower()
url=str(data.get('bundle_url','')).strip()
if not re.fullmatch(r'0\.3\.0-hotfix\.\d+(?:\.\d+)*', version):
    raise SystemExit(f'invalid stable version: {version!r}')
if not re.fullmatch(r'[0-9a-f]{64}', sha):
    raise SystemExit('invalid stable bundle sha256')
name=Path(urlparse(url).path).name
expected=f'MechOS-{version}-update.tar.zst'
if name != expected:
    raise SystemExit(f'bundle URL basename {name!r} != {expected!r}')
print(version)
print(sha)
print(name)
PY
}

mapfile -t META < <(resolve_bundle)
[ "${#META[@]}" -eq 3 ] || fail "could not resolve stable bundle metadata"
TARGET="${META[0]}"
SHA="${META[1]}"
NAME="${META[2]}"
BUNDLE="$BUNDLES/$NAME"

# If the target was published in the manifest before its generated bundle was
# checked in, build that exact target from source. This makes the hardware ISO
# path tolerant of source-first HF27 promotion without ever fabricating a
# hotfix that has no corresponding builder.
if [ ! -s "$BUNDLE" ]; then
  BUILDER="$ROOT/scripts/build-hotfix-${TARGET}.sh"
  [ -f "$BUILDER" ] || fail "stable bundle $NAME is missing and no builder exists for $TARGET"
  log "stable bundle missing; generating $TARGET with $(basename "$BUILDER")"
  bash "$BUILDER"
  mapfile -t META < <(resolve_bundle)
  TARGET="${META[0]}"
  SHA="${META[1]}"
  NAME="${META[2]}"
  BUNDLE="$BUNDLES/$NAME"
fi

[ -s "$BUNDLE" ] || fail "stable bundle is still missing after preparation: $NAME"
ACTUAL="$(sha256sum "$BUNDLE" | awk '{print $1}')"
[ "$ACTUAL" = "$SHA" ] || fail "stable bundle SHA mismatch: manifest=$SHA actual=$ACTUAL"

SERVICE_TAG="${TARGET#0.3.0-hotfix.}"
SERVICE_TAG="${SERVICE_TAG%%.*}"
log "prepared stable target $TARGET"
log "bundle $NAME sha256=$SHA"
log "expected first-boot service mechos-hotfix-0.3.0-${SERVICE_TAG}.service"
