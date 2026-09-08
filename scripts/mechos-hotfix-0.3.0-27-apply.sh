#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX27_OOBE_UI_NAMEERROR_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-27-applied"
UI=/usr/local/share/mechos/ui/oobe_shell.py
REARM=/usr/local/libexec/mechos-oobe-rearm-v25

log(){ printf '[MechOS Hotfix 27] %s\n' "$*"; }
fail(){ printf '[MechOS Hotfix 27] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to repair'; exit 0; }
[ -f "$UI" ] || fail "missing corrected OOBE shell: $UI"

python3 - "$UI" <<'PY'
import ast, pathlib, sys
p=pathlib.Path(sys.argv[1])
tree=ast.parse(p.read_text(encoding='utf-8'), filename=str(p))
build=None
for node in tree.body:
    if isinstance(node, ast.ClassDef) and node.name == 'OOBEShell':
        build=next((n for n in node.body if isinstance(n, ast.FunctionDef) and n.name == 'build'), None)
        break
if build is None:
    raise SystemExit('OOBEShell.build is missing')
forbidden={'zones','locales','keymaps'}
bad=sorted({n.id for n in ast.walk(build) if isinstance(n,ast.Name) and isinstance(n.ctx,ast.Load) and n.id in forbidden})
if bad:
    raise SystemExit('unqualified OOBE instance data remains: '+', '.join(bad))
PY

grep -Fq 'self.zone.addItems(self.zones)' "$UI" || fail 'self.zones repair missing'
grep -Fq 'self.locale.addItems(self.locales)' "$UI" || fail 'self.locales repair missing'
grep -Fq 'for label,code in self.keymaps:' "$UI" || fail 'self.keymaps repair missing'

# Reassert the persistent setup route. On reboot the HF26 launcher will now open
# this corrected UI instead of repeatedly crashing in OOBEShell.build().
if [ ! -f "$STATE/oobe-complete" ] && [ -x "$REARM" ]; then
    "$REARM"
fi

touch "$MARKER"
log 'Hotfix 27 applied: OOBE shell instance-data NameErrors are repaired.'
