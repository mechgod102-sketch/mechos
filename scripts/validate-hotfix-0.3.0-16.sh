#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in \
  "$ROOT/scripts/mechos-shell-route-v16.sh" \
  "$ROOT/scripts/mechos-mode-launch-v16.sh" \
  "$ROOT/scripts/mechos-hotfix-0.3.0-16-apply.sh" \
  "$ROOT/scripts/build-hotfix-0.3.0-16.sh"; do
  bash -n "$f"
done
python3 -m py_compile "$ROOT/scripts/mechos-hotfix16-single-shell-patch.py"

grep -Fq 'MECHOS_HOTFIX16_SINGLE_SHELL_PATCH' "$ROOT/scripts/mechos-hotfix16-single-shell-patch.py"
grep -Fq 'QStackedWidget' "$ROOT/scripts/mechos-hotfix16-single-shell-patch.py"
grep -Fq '_mechos_shell_route_v16' "$ROOT/scripts/mechos-hotfix16-single-shell-patch.py"
grep -Fq '_mechos_shell_load_external_v16' "$ROOT/scripts/mechos-hotfix16-single-shell-patch.py"
grep -Fq 'MECHOS_SHELL_ROUTE_V16' "$ROOT/scripts/mechos-shell-route-v16.sh"
grep -Fq 'MECHOS_MODE_LAUNCH_V16' "$ROOT/scripts/mechos-mode-launch-v16.sh"
grep -Fq 'exec "$ROUTER" "$MODE"' "$ROOT/scripts/mechos-mode-launch-v16.sh"
! grep -Eq 'mechos-creator-mode([[:space:]]|$)|mechos-vm-mode-runtime[[:space:]]+creator' "$ROOT/scripts/mechos-mode-launch-v16.sh"

grep -Fq 'build-hotfix-0.3.0-15.sh' "$ROOT/scripts/build-hotfix-0.3.0-16.sh"
grep -Fq 'Hotfix 16 is cumulative' "$ROOT/scripts/build-hotfix-0.3.0-16.sh"
grep -Fq 'hotfix-0.3.0-15-applied' "$ROOT/scripts/mechos-hotfix-0.3.0-16-apply.sh"

# Smoke-patch a representative generated MechScope owner. This checks that the
# hotfix converts internal navigation without requiring the real display server.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/mechscope" <<'PY'
#!/usr/bin/env python3
class UnifiedStore(QDialog):
    def __init__(self,parent=None):
        super().__init__(parent)
    def accept(self): pass
class MechScope(QMainWindow):
    def build_ui(self):
        root=QWidget(); self.setCentralWidget(root)
        a=lambda:spawn(['/usr/local/bin/mechos-performance-center'])
        b=lambda:spawn(['/usr/local/bin/mechos-update-center'])
        c=lambda:spawn(['/usr/local/bin/mechos-recovery-center'])
        cmd=['/usr/local/bin/mechos-update-center']
        button.clicked.connect(lambda _=False,c=cmd:spawn(c))
    def open_store(self):
        d=UnifiedStore(self); d.exec()
    def switch_mode(self,mode):
        spawn(['/usr/local/bin/mechos-mode-launch',mode])
class After(object):
    pass
PY
python3 "$ROOT/scripts/mechos-hotfix16-single-shell-patch.py" "$tmp/mechscope"
python3 - "$tmp/mechscope" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
compile(t,str(p),'exec')
assert 'MECHOS_HOTFIX16_SINGLE_WINDOW_SHELL' in t
assert 'QStackedWidget' in t
assert "return self._mechos_shell_route_v16('store')" in t
assert "return self._mechos_shell_route_v16('creator')" in t
assert "lambda:self._mechos_shell_route_v16('performance')" in t
assert "lambda:self._mechos_shell_route_v16('updates')" in t
assert "lambda:self._mechos_shell_route_v16('recovery')" in t
assert 'self._mechos_shell_dispatch_v16(c)' in t
assert 'self._mechos_shell_install_v16()' in t
PY

echo 'Hotfix 16 validation passed: MechOS internal surfaces route through one stacked-window shell, mode requests target the running shell, and the bundle remains cumulative with Hotfix 15.'
