#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_031_FULL_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n   "$ROOT/scripts/mechos-0.3.1-phase1-apply.sh"   "$ROOT/scripts/build-mechos-0.3.1.sh"   "$ROOT/scripts/mechos-update-helper-v37.sh"   "$ROOT/scripts/mechos-update-transaction-v14.sh"
python3 -m py_compile   "$ROOT/scripts/mechos-031-control-suite.py"   "$ROOT/scripts/mechos-bridge-v031.py"   "$ROOT/scripts/mechos-game-run-v031.py"

grep -Fq 'MECHOS_031_CONTROL_SUITE_V1' "$ROOT/scripts/mechos-031-control-suite.py"
grep -Fq 'MECHOS_BRIDGE_V031' "$ROOT/scripts/mechos-bridge-v031.py"
grep -Fq 'MECHOS_GAME_RUN_V031' "$ROOT/scripts/mechos-game-run-v031.py"
grep -Fq 'MECHOS_UPDATE_HELPER_V37_SIGNED_MANIFEST_V1' "$ROOT/scripts/mechos-update-helper-v37.sh"
grep -Fq 'selftest)' "$ROOT/scripts/mechos-update-helper-v37.sh"
grep -Fq 'commit_release_version "$latest"' "$ROOT/scripts/mechos-update-helper-v37.sh"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14_031_REPAIR_V1' "$ROOT/scripts/mechos-update-transaction-v14.sh"
grep -Fq 'source-owned MechScope session/runtime present' "$ROOT/scripts/mechos-update-transaction-v14.sh"
grep -Fq 'Performance Center is absent; update remains valid' "$ROOT/scripts/mechos-update-transaction-v14.sh"
! grep -Fq 'timeout 8 /usr/local/bin/mechos-update-helper status' "$ROOT/scripts/mechos-update-transaction-v14.sh"
grep -Fq "signature_url" "$ROOT/scripts/build-mechos-0.3.1.sh"
grep -Fq "signing_key_id" "$ROOT/scripts/build-mechos-0.3.1.sh"
grep -Fq 'MechOS-0.3.0-hotfix.36-update.tar.zst' "$ROOT/scripts/build-mechos-0.3.1.sh"
grep -Fq "'version':'0.3.1'" "$ROOT/scripts/build-mechos-0.3.1.sh"
grep -Fq "release_name':'MechOS v0.3.1'" "$ROOT/scripts/build-mechos-0.3.1.sh"

for i in $(seq -w 1 16); do
  img="$ROOT/overlay/rootfs/usr/share/backgrounds/mechos/mechos-wallpaper-$i.jpg"
  [ -s "$img" ] || { echo "Missing wallpaper source: $img" >&2; exit 1; }
done

python3 - "$ROOT/data/mechos-0.3.1-feature-registry.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
expected={'boot','downloads','ota','bridge','network','browser','gpu','power','crash','creator','compat','input'}
got={x['id'] for x in d['features']}
missing=expected-got
assert not missing, f'missing roadmap feature registry entries: {sorted(missing)}'
for x in d['features']:
    assert x.get('status') not in {'planned','missing','todo'}, x
print('0.3.1 feature registry covers all roadmap sections')
PY

python3 - "$ROOT/data/mechos-0.3.1-game-compatibility.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
m={x['id']:x for x in d['games']}
assert m['stalker-gamma']['status']=='Needs Setup/Testing'
assert m['star-citizen']['status']=='Needs Setup/Testing'
PY

for token in   mechos-downloads mechos-network mechos-browser mechos-gpu mechos-inputs   mechos-compat mechos-creator mechos-power mechos-crashes mechos-bridge-settings   mechos-game-run mechos-bridge.service; do
  grep -Fq "$token" "$ROOT/scripts/build-mechos-0.3.1.sh" || {
    echo "0.3.1 builder missing component: $token" >&2; exit 1;
  }
done

# Publication remains blocked until a real public signing key is committed.
# Never weaken this by committing a private key or a generated test key.
if [ ! -s "$ROOT/updates/mechos-update-signing-public.pem" ]; then
  echo 'RELEASE GATE: updates/mechos-update-signing-public.pem is not provisioned.' >&2
  echo 'Source validation passed, but full 0.3.1 Stable publication must not be certified as signed yet.' >&2
fi

echo 'MechOS 0.3.1 full roadmap source contracts validated.'


# Regression: nounset-safe signed manifest locals. Do not reference $dir in
# the same local declaration that first assigns it.
! grep -Fq 'local dir="$1" manifest="$dir/stable.json"' "$ROOT/scripts/mechos-update-helper-v37.sh"
grep -Fq 'dir="$1"' "$ROOT/scripts/mechos-update-helper-v37.sh"
grep -Fq 'manifest="$dir/stable.json"' "$ROOT/scripts/mechos-update-helper-v37.sh"
