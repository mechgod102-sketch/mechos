#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX35_UNIFIED_STORE_V1

log(){ printf '[%s] [MechOS Hotfix 35] %s\n' "$(date -Is 2>/dev/null || date)" "$*" | tee -a /var/log/mechos-hotfix-0.3.0-35.log; }
fail(){ log "ERROR: $*"; exit 1; }
[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f /var/lib/mechos/installed ] || fail 'not an installed MechOS system'
[ ! -e /run/archiso/bootmnt ] || fail 'refusing live ISO'

STORE=/usr/local/bin/mechos-unified-store
BOOTSTRAP=/usr/local/libexec/mechos-launcher-bootstrap-v35
CATALOG=/usr/local/libexec/mechos-game-catalog-v15
PROVIDER=/usr/local/libexec/mechos-provider-bootstrap-v15
RUNTIME=/usr/local/libexec/mechos-mechscope-source-runtime-v33
PATCHER=/usr/local/libexec/mechos-hotfix35-store-route-patch
MARKER=/var/lib/mechos/hotfix-0.3.0-35-applied

for f in "$STORE" "$BOOTSTRAP" "$CATALOG" "$PROVIDER" "$RUNTIME" "$PATCHER"; do
  [ -f "$f" ] || fail "required Unified Store component missing: $f"
done

/usr/bin/python3 "$PATCHER" "$RUNTIME" || fail 'could not make Unified Store the primary MechScope store route'
/usr/bin/python3 -m py_compile "$STORE" "$RUNTIME" "$CATALOG" "$PATCHER" || fail 'Unified Store Python validation failed'
bash -n "$BOOTSTRAP" "$PROVIDER" || fail 'launcher installer validation failed'

grep -Fq 'MECHOS_UNIFIED_STORE_V35' "$STORE" || fail 'Unified Store V35 marker missing'
grep -Fq 'MECHOS_LAUNCHER_BOOTSTRAP_V35' "$BOOTSTRAP" || fail 'launcher bootstrap V35 marker missing'
grep -Fq 'MECHOS_MECHSCOPE_UNIFIED_STORE_ROUTE_V35' "$RUNTIME" || fail 'MechScope Unified Store route marker missing'
grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33' "$RUNTIME" || fail 'HF33 source-owned runtime regressed'
grep -Fq 'MECHOS_PROVIDER_BOOTSTRAP_V15' "$PROVIDER" || fail 'provider bootstrap V15 missing'
grep -Fq 'MechOS-Unified-Store/0.3.0-hotfix.15' "$CATALOG" || fail 'in-app game catalog V15 missing'

# The frontend may request only fixed launcher IDs. The helper itself owns all
# package/app IDs so the UI cannot pass arbitrary packages, commands or URLs.
grep -Fq 'steam)' "$BOOTSTRAP" || fail 'Steam fixed installer missing'
grep -Fq 'heroic)' "$BOOTSTRAP" || fail 'Heroic fixed installer missing'
grep -Fq 'lutris)' "$BOOTSTRAP" || fail 'Lutris fixed installer missing'
! grep -Eq 'eval|bash[[:space:]]+-c|sh[[:space:]]+-c' "$BOOTSTRAP" || fail 'unsafe shell execution found in launcher bootstrap'

# Regression guard: both dashboard Store and `mechscope --store` must try the
# source-owned Unified Store before any Discovery/Discover fallback.
/usr/bin/python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
for start_token,end_token in [
    ('    def open_store(self) -> None:', '\n    def launch_vr'),
    ('    def _handoff(self):', '\n\ndef main'),
]:
    start=text.index(start_token); end=text.index(end_token,start); block=text[start:end]
    assert block.index('/usr/local/bin/mechos-unified-store') < block.index('/usr/local/bin/mechos-discovery-store')
PY

rm -rf /usr/local/bin/__pycache__ /usr/local/libexec/__pycache__ 2>/dev/null || true
mkdir -p /var/lib/mechos
touch "$MARKER"
log 'Hotfix 35 applied: source-owned Unified Store installed with in-page stores, launcher install/launch controls, and primary MechScope routing.'
