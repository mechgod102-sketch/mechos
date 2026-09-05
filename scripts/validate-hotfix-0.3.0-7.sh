#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.7-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

fail(){ echo "[Hotfix 7 Validation] ERROR: $*" >&2; exit 1; }

[ -s "$BUNDLE" ] || fail "bundle missing"
[ -s "$SUM" ] || fail "checksum missing"
[ -s "$MANIFEST" ] || fail "stable manifest missing"
(
  cd "$(dirname "$BUNDLE")"
  sha256sum -c "$(basename "$SUM")"
)

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar --zstd -xpf "$BUNDLE" -C "$TMP"

CENTER="$TMP/usr/local/libexec/mechos-update-center-v7.py"
PATCHER="$TMP/usr/local/libexec/mechos-store-qlineedit-patch"
RUNTIME="$TMP/usr/local/bin/mechos-vm-mode-runtime"
LAUNCH="$TMP/usr/local/bin/mechos-mode-launch"
WRAPPER="$TMP/usr/local/bin/mechos-update-center"
APPLY="$TMP/usr/local/libexec/mechos-hotfix-0.3.0-7-apply"
REBOOT="$TMP/usr/local/bin/mechos-reboot"

for f in "$CENTER" "$PATCHER" "$RUNTIME" "$LAUNCH" "$WRAPPER" "$APPLY" "$REBOOT"; do
  [ -f "$f" ] || fail "missing staged file: $f"
done

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$CENTER" "$PATCHER"
bash -n "$RUNTIME"
bash -n "$LAUNCH"
bash -n "$WRAPPER"
bash -n "$APPLY"
bash -n "$REBOOT"

grep -Fq 'MECHOS_UPDATE_CENTER_RECOVERY_V7' "$CENTER" || fail "recovery Update Center marker missing"
grep -Fq 'exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v7.py' "$WRAPPER" || fail "Update Center wrapper does not use stable v7 owner"
grep -Fq 'MECHOS_VM_MECHSCOPE_PYTHON_EXEC_V2' "$RUNTIME" || fail "raw-Python MechScope execution fix missing"
grep -Fq '/usr/bin/python3 "$target"' "$RUNTIME" || fail "VM runtime does not invoke raw Python backend through python3"
grep -Fq 'MECHOS_HOTFIX5_VM_DIRECT_ROUTER_V1' "$LAUNCH" || fail "VM direct router missing"
grep -Fq 'mechos-store-qlineedit-patch' "$APPLY" || fail "Creator Store repair is not applied"
grep -Fq 'mechos-update-center.pre-hotfix7' "$APPLY" || fail "old Update Center diagnostic backup missing"
grep -Fq 'Exec=/usr/local/bin/mechos-update-center' "$TMP/usr/share/applications/mechos-update-center.desktop" || fail "Update Center desktop launcher broken"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$TMP/usr/share/applications/mechos-return-gaming.desktop" || fail "VM MechScope desktop launcher broken"

cat > "$TMP/qlineedit-sample.py" <<'PY'
#!/usr/bin/env python3
from PyQt6.QtWidgets import QWidget

def build():
    return QLineEdit()
PY
python3 "$PATCHER" "$TMP/qlineedit-sample.py"
grep -Fq 'QLineEdit' "$TMP/qlineedit-sample.py" || fail "QLineEdit repair failed"
grep -Fq 'MECHOS_CREATOR_STORE_QLINEEDIT_IMPORT_V1' "$TMP/qlineedit-sample.py" || fail "QLineEdit import marker missing"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/qlineedit-sample.py"

python3 - "$CENTER" <<'PY'
import ast,sys
p=sys.argv[1]
tree=ast.parse(open(p,encoding='utf-8').read(),filename=p)
classes={n.name:n for n in tree.body if isinstance(n,ast.ClassDef)}
assert 'UpdateCenter' in classes, 'UpdateCenter class missing'
methods={n.name for n in classes['UpdateCenter'].body if isinstance(n,ast.FunctionDef)}
required={'check_updates','install_updates','reboot','load_status','start_process','finished'}
missing=required-methods
assert not missing, f'missing Update Center methods: {sorted(missing)}'
PY

python3 - "$MANIFEST" "$SUM" <<'PY'
import json,pathlib,sys
manifest=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert manifest['schema']==1
assert manifest['channel']=='stable'
assert manifest['version']=='0.3.0-hotfix.7'
assert manifest['release_name']=='MechOS v0.3.0 Hotfix 7'
assert manifest['requires_reboot'] is True
sumline=pathlib.Path(sys.argv[2]).read_text().strip().split()[0]
assert manifest['bundle_sha256']==sumline
assert manifest['bundle_url'].endswith('MechOS-0.3.0-hotfix.7-update.tar.zst')
PY

echo '[Hotfix 7 Validation] PASS: Update Center recovery owner, Creator Store import repair, VM MechScope Python execution, reboot helper, bundle checksum, and stable manifest validated.'
