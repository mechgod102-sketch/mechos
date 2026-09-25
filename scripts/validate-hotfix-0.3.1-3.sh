#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX_0313_AB_UPDATE_ENGINE_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in   scripts/mechos-update-helper-launcher-v38.sh   scripts/mechos-update-center-launcher-v38.sh   scripts/mechos-update-helper-core-v38.sh   scripts/mechos-update-engine-switch-v38.sh   scripts/mechos-update-self-repair-v0313.sh   scripts/mechos-update-transaction-v15.sh   scripts/mechos-hotfix-0.3.1-3-apply.sh   scripts/build-hotfix-0.3.1-3.sh; do
  bash -n "$ROOT/$f"
done
python3 -m py_compile "$ROOT/scripts/mechos-update-center-reference-v8.py"

grep -Fq 'MECHOS_UPDATE_HELPER_AB_LAUNCHER_V38' "$ROOT/scripts/mechos-update-helper-launcher-v38.sh"
grep -Fq 'MECHOS_UPDATE_CENTER_AB_LAUNCHER_V38' "$ROOT/scripts/mechos-update-center-launcher-v38.sh"
grep -Fq 'MECHOS_UPDATE_HELPER_CORE_V38_AB_ENGINE' "$ROOT/scripts/mechos-update-helper-core-v38.sh"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V15_AB_ENGINE_ISOLATION_V1' "$ROOT/scripts/mechos-update-transaction-v15.sh"
grep -Fq 'healthy v38' "$ROOT/scripts/mechos-update-transaction-v15.sh"
grep -Fq 'restored previous A/B Update Engine slot' "$ROOT/scripts/mechos-update-transaction-v15.sh"

# Exercise atomic slot activation and previous-slot recovery without root.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
engine="$tmp/engine"
mkdir -p "$engine/slots/old" "$engine/slots/new"

make_slot(){
  local dst="$1"
  cp "$ROOT/scripts/mechos-update-helper-core-v38.sh" "$dst/mechos-update-helper-core"
  cp "$ROOT/scripts/mechos-update-center-reference-v8.py" "$dst/mechos-update-center-backend.py"
  cp "$ROOT/scripts/mechos-update-transaction-v15.sh" "$dst/mechos-update-transaction"
  chmod 0755 "$dst/mechos-update-helper-core" "$dst/mechos-update-center-backend.py" "$dst/mechos-update-transaction"
}
make_slot "$engine/slots/old"
make_slot "$engine/slots/new"

MECHOS_UPDATE_ENGINE_TEST_MODE=1 MECHOS_UPDATE_ENGINE_ROOT="$engine"   bash "$ROOT/scripts/mechos-update-engine-switch-v38.sh" --activate old >/dev/null
test "$(basename "$(readlink -f "$engine/current")")" = old

MECHOS_UPDATE_ENGINE_TEST_MODE=1 MECHOS_UPDATE_ENGINE_ROOT="$engine"   bash "$ROOT/scripts/mechos-update-engine-switch-v38.sh" --activate new >/dev/null
test "$(basename "$(readlink -f "$engine/current")")" = new
test "$(basename "$(readlink -f "$engine/previous")")" = old

rm -f "$engine/slots/new/mechos-update-helper-core"
if MECHOS_UPDATE_ENGINE_TEST_MODE=1 MECHOS_UPDATE_ENGINE_ROOT="$engine"   bash "$ROOT/scripts/mechos-update-engine-switch-v38.sh" --check >/dev/null 2>&1; then
  echo 'invalid current slot unexpectedly passed validation' >&2
  exit 1
fi
MECHOS_UPDATE_ENGINE_TEST_MODE=1 MECHOS_UPDATE_ENGINE_ROOT="$engine"   bash "$ROOT/scripts/mechos-update-engine-switch-v38.sh" --recover >/dev/null
test "$(basename "$(readlink -f "$engine/current")")" = old

# Ensure transaction source protects healthy public launchers from later
# cumulative hotfixes rather than unconditionally installing staged copies.
python3 - "$ROOT/scripts/mechos-update-transaction-v15.sh" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert "if ! grep -Fq 'MECHOS_UPDATE_HELPER_AB_LAUNCHER_V38'" in s
assert "if ! grep -Fq 'MECHOS_UPDATE_CENTER_AB_LAUNCHER_V38'" in s
assert "--exclude='./usr/local/bin/mechos-update-helper'" in s
assert "--exclude='./usr/local/bin/mechos-update-center'" in s
PY

echo 'MechOS 0.3.1 Hotfix 3 A/B Update Engine contracts validated.'
