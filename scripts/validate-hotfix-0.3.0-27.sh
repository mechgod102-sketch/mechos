#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX27_OOBE_UI_NAMEERROR_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI="$ROOT/src/mechos_ui/oobe_shell.py"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-27-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-27.sh"

python3 -m py_compile "$UI"
bash -n "$APPLY"
bash -n "$BUILD"

python3 - "$UI" <<'PY'
import ast, pathlib, sys
p=pathlib.Path(sys.argv[1]); tree=ast.parse(p.read_text(encoding='utf-8'), filename=str(p))
klass=next((n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='OOBEShell'),None)
assert klass is not None, 'OOBEShell class missing'
build=next((n for n in klass.body if isinstance(n,ast.FunctionDef) and n.name=='build'),None)
assert build is not None, 'OOBEShell.build missing'
forbidden={'zones','locales','keymaps'}
bad=sorted({n.id for n in ast.walk(build) if isinstance(n,ast.Name) and isinstance(n.ctx,ast.Load) and n.id in forbidden})
assert not bad, f'unqualified instance data in OOBEShell.build: {bad}'
PY

grep -Fq 'self.zone.addItems(self.zones)' "$UI"
grep -Fq "'America/New_York' in self.zones" "$UI"
grep -Fq 'self.locale.addItems(self.locales)' "$UI"
grep -Fq 'for label,code in self.keymaps:' "$UI"

grep -Fq 'src/mechos_ui/oobe_shell.py' "$BUILD"
grep -Fq 'usr/local/share/mechos/ui/oobe_shell.py' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.26-update.tar.zst' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.27'" "$BUILD"
grep -Fq 'MECHOS_HOTFIX27_OOBE_UI_NAMEERROR_V1' "$APPLY"
grep -Fq 'MECHOS_BUILD_HOTFIX27_OOBE_UI_NAMEERROR_V1' "$BUILD"

printf 'Hotfix 27 OOBE UI regression validation passed.\n'
