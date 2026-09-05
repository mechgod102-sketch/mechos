#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/scripts/build-hotfix-0.3.0-13.sh"
bash -n "$ROOT/scripts/mechos-hotfix-0.3.0-13-apply.sh"
bash -n "$ROOT/scripts/mechos-hotfix13-stability-integration.sh"
bash -n "$ROOT/scripts/mechos-update-transaction-v13.sh"
python3 -m py_compile \
  "$ROOT/scripts/mechos-game-install-controller-v13.py" \
  "$ROOT/scripts/mechos-hotfix13-mechscope-patch.py" \
  "$ROOT/scripts/mechos-performance-center-v13.py" \
  "$ROOT/scripts/mechos-update-helper-v13-patch.py"

python3 - "$ROOT/scripts/mechos-game-install-controller-v13.py" <<'PY'
import importlib.util,sys
p=sys.argv[1]
spec=importlib.util.spec_from_file_location('storectl',p)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.extract_steam_id('https://store.steampowered.com/app/123456/Test/') == '123456'
assert m.extract_steam_id('steam://install/730') == '730'
assert m.extract_lutris_slug('lutris:quake-darkplaces') == 'quake-darkplaces'
assert m.extract_lutris_slug('https://lutris.net/games/quake-darkplaces/') == 'quake-darkplaces'
PY

grep -Fq 'MECHOS_HOTFIX13_PROVIDER_INSTALL_V1' "$ROOT/scripts/mechos-hotfix13-mechscope-patch.py"
grep -Fq 'steam://install/' "$ROOT/scripts/mechos-game-install-controller-v13.py"
grep -Fq 'lutris-installer-uri' "$ROOT/scripts/mechos-game-install-controller-v13.py"
grep -Fq 'legendary' "$ROOT/scripts/mechos-game-install-controller-v13.py"
grep -Fq 'nile' "$ROOT/scripts/mechos-game-install-controller-v13.py"
grep -Fq 'Heroic Games Launcher' "$ROOT/scripts/mechos-game-install-controller-v13.py"
grep -Fq 'mechos-game-install-controller-v13.py' "$ROOT/scripts/build-hotfix-0.3.0-13.sh"
grep -Fq 'MECHOS_HOTFIX13_PROVIDER_INSTALL_V1' "$ROOT/scripts/mechos-hotfix-0.3.0-13-apply.sh"
grep -Fq 'mechos-game-install-controller-v13.py' "$ROOT/scripts/mechos-hotfix13-stability-integration.sh"
grep -Fq 'mechos-hotfix13-stability-integration.sh' "$ROOT/scripts/patch-mechos-reference-v5.py"

for f in "$ROOT/scripts/mechos-hotfix-0.3.0-13-apply.sh" "$ROOT/scripts/mechos-update-transaction-v13.sh"; do
  ! grep -Fq 'systemctl reboot' "$f"
  ! grep -Fq 'shutdown -r' "$f"
  ! grep -Fq 'reboot -f' "$f"
done

echo 'Hotfix 13 validation passed: updater protection, fullscreen/store authority, Performance Center and provider install adapters are present.'
