#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX33_SOURCE_OWNED_MECHSCOPE_RUNTIME_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="$ROOT/scripts/mechos-mechscope-source-runtime-v33.py"
SHELL="$ROOT/src/mechscope/mechscope_shell.py"
SESSION="$ROOT/scripts/mechscope-session-v20.sh"
OVERLAY="$ROOT/overlay/rootfs/usr/local/bin/mechscope-session"
SAFE="$ROOT/scripts/mechos-mechscope-safe-launch-v31.sh"
CLEANUP="$ROOT/scripts/mechos-mechscope-user-cleanup-v33.sh"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-33-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-33.sh"

python3 -m py_compile "$RUNTIME" "$SHELL"
bash -n "$SESSION" "$OVERLAY" "$SAFE" "$CLEANUP" "$APPLY" "$BUILD"

grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33' "$RUNTIME"
grep -Fq '/usr/local/share/mechos/mechscope/mechscope_shell.py' "$RUNTIME"
grep -Fq 'class MechScope(QMainWindow)' "$RUNTIME"
grep -Fq 'app.setQuitOnLastWindowClosed(False)' "$RUNTIME"
grep -Fq 'window.showFullScreen()' "$RUNTIME"
python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import ast,sys
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8'); tree=ast.parse(text)
# Comments/docstrings may explain the removed legacy paths. Reject executable
# constants/loader code that would actually depend on them.
strings=[]
for node in ast.walk(tree):
    if isinstance(node, ast.Constant) and isinstance(node.value,str): strings.append(node.value)
for value in strings:
    if value in ('/usr/local/bin/mechscope.real','/usr/local/libexec/mechscope-owner-v23.py'):
        raise SystemExit(f'V33 executable runtime still depends on legacy path: {value}')
assert 'load_owner(' not in text
PY

grep -Fq 'class MechScopeShell' "$SHELL"
for f in "$SESSION" "$OVERLAY"; do
  grep -Fq 'MECHOS_MECHSCOPE_SESSION_V23_SOURCE_RUNTIME' "$f"
  grep -Fq 'SOURCE_RUNTIME=/usr/local/libexec/mechos-mechscope-source-runtime-v33' "$f"
  grep -Fq '/usr/bin/flock -n "$LOCK_FILE"' "$f"
  grep -Fq 'crashes >= 3' "$f"
  grep -Fq 'elapsed >= 30' "$f"
  if grep -Fq 'RAW_MECHSCOPE=/usr/local/bin/mechscope.real' "$f"; then
    echo "hardware session still owns automatic raw .real fallback: $f" >&2; exit 1
  fi
done

grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_ROUTE_V33' "$SAFE"
grep -Fq 'SOURCE_RUNTIME=/usr/local/libexec/mechos-mechscope-source-runtime-v33' "$SAFE"
grep -Fq 'refusing legacy automatic fallback' "$SAFE"
grep -Fq 'exec /usr/bin/python3 "$target" "$@"' "$SAFE"

grep -Fq 'MECHOS_MECHSCOPE_USER_CLEANUP_V33' "$CLEANUP"
grep -Fq 'Hidden=true' "$CLEANUP"
grep -Fq 'systemctl --user disable --now' "$CLEANUP"

grep -Fq 'MECHOS_HOTFIX33_SOURCE_OWNED_MECHSCOPE_RUNTIME_V1' "$APPLY"
grep -Fq 'Session=mechscope.desktop' "$APPLY"
grep -Fq 'MECHOS_TUTORIAL_SOURCE_RUNTIME_V33' "$APPLY"

grep -Fq 'MechOS-0.3.0-hotfix.32-update.tar.zst' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.33-update.tar.zst' "$BUILD"
grep -Fq 'mechos-mechscope-source-runtime-v33.py' "$BUILD"
grep -Fq 'src/mechscope/mechscope_shell.py' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.33'" "$BUILD"

python3 - "$SAFE" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
source=text.index('if [ -f "$SOURCE_RUNTIME" ]')
installed=text.index('if [ -f /var/lib/mechos/installed ]',source)
legacy=text.index('if [ -f "$LEGACY_RUNTIME" ]',installed)
assert source < installed < legacy
block=text[installed:legacy]
assert 'return 1' in block
assert 'LEGACY_REAL' not in block
PY

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.config/autostart"
cat >"$tmp/.config/autostart/old-mechscope.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Exec=/usr/local/libexec/mechos-mechscope-safe-launch-v31
EOF
HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" XDG_STATE_HOME="$tmp/.local/state" bash "$CLEANUP"
grep -Fq 'Hidden=true' "$tmp/.config/autostart/old-mechscope.desktop"

printf 'Hotfix 33 source-owned MechScope runtime regression validation passed.\n'
