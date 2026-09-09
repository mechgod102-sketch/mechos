#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX35_UNIFIED_STORE_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n \
  "$ROOT/scripts/mechos-launcher-bootstrap-v35.sh" \
  "$ROOT/scripts/mechos-hotfix-0.3.0-35-apply.sh" \
  "$ROOT/scripts/build-hotfix-0.3.0-35.sh"
python3 -m py_compile \
  "$ROOT/scripts/mechos-unified-store-v35.py" \
  "$ROOT/scripts/mechos-hotfix35-store-route-patch.py"

grep -Fq 'MECHOS_UNIFIED_STORE_V35' "$ROOT/scripts/mechos-unified-store-v35.py"
grep -Fq 'STORES = [' "$ROOT/scripts/mechos-unified-store-v35.py"
grep -Fq 'LAUNCHERS = {' "$ROOT/scripts/mechos-unified-store-v35.py"
grep -Fq 'View in Unified Store' "$ROOT/scripts/mechos-unified-store-v35.py"
grep -Fq 'Install Launcher' "$ROOT/scripts/mechos-unified-store-v35.py"
grep -Fq '/usr/local/libexec/mechos-game-catalog-v15' "$ROOT/scripts/mechos-unified-store-v35.py"
grep -Fq '/usr/local/libexec/mechos-launcher-bootstrap-v35' "$ROOT/scripts/mechos-unified-store-v35.py"
for name in 'Steam' 'Epic Games' 'GOG.com' 'Amazon Games' 'Heroic Games Launcher' 'Lutris'; do
  grep -Fq "$name" "$ROOT/scripts/mechos-unified-store-v35.py" || { echo "Unified Store missing $name" >&2; exit 1; }
done

grep -Fq 'MECHOS_LAUNCHER_BOOTSTRAP_V35' "$ROOT/scripts/mechos-launcher-bootstrap-v35.sh"
grep -Fq 'steam)' "$ROOT/scripts/mechos-launcher-bootstrap-v35.sh"
grep -Fq 'heroic)' "$ROOT/scripts/mechos-launcher-bootstrap-v35.sh"
grep -Fq 'lutris)' "$ROOT/scripts/mechos-launcher-bootstrap-v35.sh"
grep -Fq 'pkexec /usr/bin/pacman -S --needed --noconfirm lutris' "$ROOT/scripts/mechos-launcher-bootstrap-v35.sh"
! grep -Eq 'eval|bash[[:space:]]+-c|sh[[:space:]]+-c' "$ROOT/scripts/mechos-launcher-bootstrap-v35.sh"

grep -Fq 'MECHOS_HOTFIX35_STORE_ROUTE_PATCH' "$ROOT/scripts/mechos-hotfix35-store-route-patch.py"
grep -Fq '/usr/local/bin/mechos-unified-store' "$ROOT/scripts/mechos-hotfix35-store-route-patch.py"
grep -Fq 'dashboard routing still prefers Discovery' "$ROOT/scripts/mechos-hotfix35-store-route-patch.py"
grep -Fq 'MECHOS_HOTFIX35_UNIFIED_STORE_V1' "$ROOT/scripts/mechos-hotfix-0.3.0-35-apply.sh"
grep -Fq 'MechOS-0.3.0-hotfix.34-update.tar.zst' "$ROOT/scripts/build-hotfix-0.3.0-35.sh"
grep -Fq "'version':'0.3.0-hotfix.35'" "$ROOT/scripts/build-hotfix-0.3.0-35.sh"

# Prove the route patch against the checked-in HF33 runtime without modifying it.
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
cp "$ROOT/scripts/mechos-mechscope-source-runtime-v33.py" "$tmp"
python3 "$ROOT/scripts/mechos-hotfix35-store-route-patch.py" "$tmp"
python3 -m py_compile "$tmp"
grep -Fq 'MECHOS_MECHSCOPE_UNIFIED_STORE_ROUTE_V35' "$tmp"
python3 - "$tmp" <<'PY'
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

echo 'Hotfix 35 Unified Store source contracts validated.'
