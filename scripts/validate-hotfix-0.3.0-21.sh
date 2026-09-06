#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="$ROOT/scripts/mechos-hotfix21-unified-store-patch.py"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-21-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-21.sh"

python3 -m py_compile "$PATCH" "$ROOT/scripts/mechos-game-catalog-v15.py"
bash -n "$APPLY" "$BUILD" "$ROOT/scripts/mechos-provider-bootstrap-v15.sh"

grep -Fq 'MECHOS_HOTFIX21_UNIFIED_STORE_PATCH' "$PATCH"
grep -Fq 'MECHOS_HOTFIX21_UNIFIED_STORE_NATIVE_PAGE' "$PATCH"
grep -Fq 'ONE STORE. NO BROWSER HANDOFF.' "$PATCH"
grep -Fq 'mechos-game-catalog-v15' "$PATCH"
grep -Fq 'mechos-provider-bootstrap-v15' "$PATCH"
grep -Fq "return self._open_steam('steam://rungameid/' + appid)" "$PATCH"
grep -Fq 'self._render_catalog_results(rows, error, provider)' "$PATCH"

# Guard the root cause reported from real Hotfix 20 systems: the legacy V5
# owner constructs build_reference_v5(), while Hotfix 15 visual code only
# targeted build_reference_store(). Hotfix 21 must replace the class itself.
grep -Fq 'self.build_reference_v5()' "$ROOT/scripts/mechos-reference-v5-store-layout.sh"
grep -Fq "method_bounds(text, 'UnifiedStore', 'build_reference_store')" "$ROOT/scripts/mechos-hotfix15-runtime-patch.py"
grep -Fq "bounds = class_bounds(text, 'UnifiedStore')" "$PATCH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/mechscope" <<'PY'
#!/usr/bin/env python3
class UnifiedStore(QDialog):
    def __init__(self,parent=None):
        super().__init__(parent)
        self.build_reference_v5()
    def build_reference_v5(self):
        pass
    def search_selected(self):
        spawn(['xdg-open','https://example.invalid/search'])
    def search_all(self):
        spawn(['xdg-open','https://example.invalid/all'])
    def launch_game(self,game):
        spawn(['xdg-open','steam://rungameid/1'])

class MechScope(QMainWindow):
    pass
PY
python3 "$PATCH" "$TMP/mechscope"
python3 - "$TMP/mechscope" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
compile(text,sys.argv[1],'exec')
start=text.find('class UnifiedStore(')
end=text.find('\nclass ',start+1)
section=text[start:end]
assert 'MECHOS_HOTFIX21_UNIFIED_STORE_NATIVE_PAGE' in section
assert 'def build_reference_v5' not in section
assert 'def build_hotfix21_store' in section
assert 'mechos-game-catalog-v15' in section
assert 'mechos-provider-bootstrap-v15' in section
assert "spawn(['xdg-open'" not in section
assert 'webbrowser.' not in section
assert 'dialog.exec()' not in section
assert "steam://rungameid/" in section
PY

# Apply/build scripts must advance the installed release and preserve v20 as
# the cumulative root-safe dependency.
grep -Fq "printf '0.3.0-hotfix.21" "$APPLY"
grep -Fq 'mechos-hotfix-0.3.0-20.service' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.20-update.tar.zst' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.21'" "$BUILD"

echo 'Hotfix 21 Unified Store validation passed.'
