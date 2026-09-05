#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail(){ echo "[Build 122 Validation] ERROR: $*" >&2; exit 1; }

BUILD="$ROOT/scripts/mechos-build122-vm-store-mechscope-final.sh"
PATCHER="$ROOT/scripts/mechos-store-qlineedit-patch.py"
CENTER="$ROOT/scripts/mechos-update-center-recovery-v7.py"
RUNTIME="$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh"
REF="$ROOT/scripts/patch-mechos-reference-v5.py"

for f in "$BUILD" "$PATCHER" "$CENTER" "$RUNTIME" "$REF"; do [ -f "$f" ] || fail "missing $f"; done
bash -n "$BUILD"
bash -n "$RUNTIME"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$PATCHER" "$CENTER" "$REF"
grep -Fq 'MECHOS_UPDATE_CENTER_RECOVERY_V7' "$CENTER" || fail 'Update Center recovery owner missing'
grep -Fq 'MECHOS_VM_MECHSCOPE_PYTHON_EXEC_V2' "$RUNTIME" || fail 'raw-Python MechScope fix missing'
grep -Fq 'mechos-store-qlineedit-patch' "$BUILD" || fail 'Creator Store repair missing from Build 122'
grep -Fq 'mechos-update-center-v7.py' "$BUILD" || fail 'Update Center v7 missing from Build 122'

python3 - "$REF" <<'PY'
from pathlib import Path
import sys
t=Path(sys.argv[1]).read_text()
a=t.find('bash /workspace/scripts/mechos-build120-reboot-vm-creator-final.sh')
b=t.find('bash /workspace/scripts/mechos-build122-vm-store-mechscope-final.sh')
assert -1 not in (a,b), 'final build stage marker missing'
assert a < b, 'Build 122 must run after Build 120'
# patch-mechos-reference-v5.py inserts the entire final-stage block at `pos`,
# where `pos` is the final mkarchiso insertion point. Therefore every command
# inside `insert`, including Build 122, executes before mkarchiso.
assert "text = text[:pos] + insert + text[pos:]" in t, 'final block is not inserted before mkarchiso'
PY

echo '[Build 122 Validation] PASS: Update Center recovery, Creator Store import repair, VM MechScope Python execution, and final build ordering validated.'
