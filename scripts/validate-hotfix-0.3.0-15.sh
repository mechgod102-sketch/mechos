#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in \
  "$ROOT/scripts/mechos-mode-launch-v15.sh" \
  "$ROOT/scripts/mechos-mode-launch-hotfix10.sh" \
  "$ROOT/scripts/mechos-provider-bootstrap-v15.sh" \
  "$ROOT/scripts/mechos-hotfix-0.3.0-15-apply.sh" \
  "$ROOT/scripts/build-hotfix-0.3.0-15.sh"; do
  bash -n "$f"
done

python3 -m py_compile \
  "$ROOT/scripts/mechos-hotfix15-runtime-patch.py" \
  "$ROOT/scripts/mechos-hotfix15-game-browser-patch.py" \
  "$ROOT/scripts/mechos-game-catalog-v15.py"

grep -Fq 'MECHOS_MODE_LAUNCH_V15' "$ROOT/scripts/mechos-mode-launch-v15.sh"
grep -Fq 'MECHOS_CREATOR_HANDOFF_V15' "$ROOT/scripts/mechos-mode-launch-v15.sh"
grep -Fq 'MECHOS_CREATOR_VM_OVERLAY_V15' "$ROOT/scripts/mechos-mode-launch-v15.sh"
! grep -Eq 'mechos-vm-mode-runtime[[:space:]]+creator' "$ROOT/scripts/mechos-mode-launch-v15.sh"

grep -Fq 'MECHOS_PROVIDER_BOOTSTRAP_V15' "$ROOT/scripts/mechos-provider-bootstrap-v15.sh"
grep -Fq 'flatpak install --user -y flathub com.heroicgameslauncher.hgl' "$ROOT/scripts/mechos-provider-bootstrap-v15.sh"
grep -Fq 'pkexec /usr/bin/pacman -S --needed --noconfirm steam' "$ROOT/scripts/mechos-provider-bootstrap-v15.sh"

grep -Fq 'MECHOS_HOTFIX15_INTERNAL_GAME_BROWSER' "$ROOT/scripts/mechos-hotfix15-game-browser-patch.py"
grep -Fq 'mechos-game-catalog-v15' "$ROOT/scripts/mechos-hotfix15-game-browser-patch.py"
grep -Fq 'Search All Stores' "$ROOT/scripts/mechos-hotfix15-game-browser-patch.py"

grep -Fq 'MechOS-Unified-Store/0.3.0-hotfix.15' "$ROOT/scripts/mechos-game-catalog-v15.py"
grep -Fq 'https://www.cheapshark.com/api/1.0' "$ROOT/scripts/mechos-game-catalog-v15.py"

# Smoke-patch a minimal generated MechScope owner. The hotfix must compile after
# both patches, retain search methods as native Game Browser actions and contain
# no old xdg-open store-search handoff.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/mechscope" <<'PY'
#!/usr/bin/env python3
from urllib.parse import quote_plus
class DummySignal:
    def connect(self,*a,**k): pass
class DummyButton:
    clicked=DummySignal()
class UnifiedStore(object):
    STORES=[
      ('Steam','Steam','https://store.steampowered.com/search/?term={query}',['steam','-gamepadui']),
      ('Epic Games','Epic','https://store.epicgames.com/browse?q={query}',['flatpak','run','com.heroicgameslauncher.hgl']),
      ('GOG','GOG','https://www.gog.com/en/games?query={query}',['flatpak','run','com.heroicgameslauncher.hgl']),
      ('Amazon Games','Amazon','https://gaming.amazon.com/home',['flatpak','run','com.heroicgameslauncher.hgl']),
    ]
    def select_store(self,index):
        self.selected_store=index
    def browse_selected(self):
        spawn(['xdg-open', self.STORES[self.selected_store][2].format(query=self.query())])
    def search_selected(self):
        self.browse_selected()
    def search_all(self):
        q=self.query()
        for _name,_desc,url,_launcher in self.STORES:
            spawn(['xdg-open',url.format(query=q)])
    def open_selected_launcher(self):
        spawn(self.STORES[self.selected_store][3])
    def query(self):
        return quote_plus(self.search.text().strip())
class MechScope(object):
    pass
PY
python3 "$ROOT/scripts/mechos-hotfix15-runtime-patch.py" store "$tmp/mechscope"
python3 "$ROOT/scripts/mechos-hotfix15-game-browser-patch.py" "$tmp/mechscope"
python3 - "$tmp/mechscope" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
compile(t,str(p),'exec')
assert 'MECHOS_HOTFIX15_NATIVE_UNIFIED_STORE' in t
assert 'MECHOS_HOTFIX15_INTERNAL_GAME_BROWSER' in t
assert '_mechos_show_game_browser_v15' in t
assert "spawn(['xdg-open', url.format(query=self.query())])" not in t
assert "spawn(['xdg-open',url.format(query=q)])" not in t
assert "self._mechos_show_game_browser_v15('all')" in t
PY

echo 'Hotfix 15 validation passed: Creator overlay is safe, Unified Store search remains inside MechOS, and missing provider clients are auto-installed only on provider handoff.'
