#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.11-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
fail(){ echo "[Hotfix 11 Validation] ERROR: $*" >&2; exit 1; }

[ -s "$BUNDLE" ] || fail 'bundle missing'
[ -s "$SUM" ] || fail 'checksum missing'
[ -s "$MANIFEST" ] || fail 'stable manifest missing'
(cd "$(dirname "$BUNDLE")" && sha256sum -c "$(basename "$SUM")")

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar --zstd -xpf "$BUNDLE" -C "$TMP"
UI="$TMP/usr/local/share/mechos/ui"
VM="$TMP/usr/local/bin/mechos-vm-mode-runtime"
LAUNCH="$TMP/usr/local/bin/mechos-mode-launch"
UPDATE="$TMP/usr/local/bin/mechos-update-center"
IMPORTS="$TMP/usr/local/libexec/mechos-mechscope-runtime-imports-v11"
APPLY="$TMP/usr/local/libexec/mechos-hotfix-0.3.0-11-apply"

for f in "$VM" "$LAUNCH" "$UPDATE" "$IMPORTS" "$APPLY"; do [ -f "$f" ] || fail "missing staged file: $f"; done
for f in fixed_canvas.py update_shell.py recovery_shell.py quick_actions_shell.py creator_shell.py creator_visual_shell_v10.py; do
  [ -f "$UI/$f" ] || fail "missing carried GUI source: $f"
done

cmp -s "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh" "$VM" || fail 'bundled VM runtime differs from source'
cmp -s "$ROOT/scripts/mechos-mode-launch-hotfix10.sh" "$LAUNCH" || fail 'bundled mode launcher differs from source'
cmp -s "$ROOT/scripts/mechos-mechscope-runtime-imports-v11.py" "$IMPORTS" || fail 'bundled runtime import guard differs from source'

for f in "$VM" "$LAUNCH" "$UPDATE" "$APPLY"; do bash -n "$f"; done
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$IMPORTS" "$UI/creator_visual_shell_v10.py"

# Exact VirtualBox rc=1 repair contract.
grep -Fq 'MECHOS_VM_MECHSCOPE_QPA_FALLBACK_V3' "$VM" || fail 'VM QPA fallback marker missing'
for token in \
  'run_mechscope_attempt session auto' \
  'run_mechscope_attempt xwayland xcb' \
  'run_mechscope_attempt wayland wayland' \
  'Require three seconds' \
  'vm-mechscope-launch.log' \
  'mechscope-launch.log' \
  'all visible MechScope VM launch attempts failed'; do
  grep -Fq "$token" "$VM" || fail "VM runtime behavior missing: $token"
done

grep -Fq 'MECHOS_HOTFIX11_VM_FAILURE_LOGS_V1' "$LAUNCH" || fail 'VM failure log marker missing'
for token in 'vm-mode-runtime.log' 'vm-mechscope-launch.log' 'notify_vm_error'; do
  grep -Fq "$token" "$LAUNCH" || fail "launcher does not expose correct VM log: $token"
done

# Guard generated MechScope runtime names that py_compile alone cannot catch.
cat > "$TMP/mechscope.py" <<'PY'
#!/usr/bin/env python3
from PyQt6.QtWidgets import QApplication
class UnifiedStore(object):
    pass
class MechScope(object):
    pass
PY
python3 "$IMPORTS" "$TMP/mechscope.py"
grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_IMPORTS_V11' "$TMP/mechscope.py" || fail 'runtime import marker not installed'
for token in 'QPixmap' 'QLineEdit' 'QVBoxLayout' 'QHBoxLayout' 'QMessageBox' 'from pathlib import Path'; do
  grep -Fq "$token" "$TMP/mechscope.py" || fail "runtime import guard missing $token"
done
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/mechscope.py"

# Update Center can be installed via CLI and then produce a launch log if GUI
# startup is still unhealthy.
grep -Fq 'update-center-launch.log' "$UPDATE" || fail 'Update Center launch diagnostics missing'
grep -Fq 'mechos-update-center-v8.py' "$UPDATE" || fail 'Update Center verified v8 backend missing'

# Carry the prior visual authority forward rather than regressing the UI while
# fixing VM mode switching.
grep -Fq 'MECHOS_CREATOR_VISUALS_V10' "$UI/creator_visual_shell_v10.py" || fail 'Creator visual v10 not carried forward'
grep -Fq 'MECHOS_QUICK_ACTIONS_VISUAL_V9' "$UI/quick_actions_shell.py" || fail 'Quick Actions v9 not carried forward'

python3 - "$MANIFEST" "$SUM" <<'PY'
import json, pathlib, sys
m=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert m['schema']==1 and m['channel']=='stable'
assert m['version']=='0.3.0-hotfix.11'
assert m['release_name']=='MechOS v0.3.0 Hotfix 11'
assert m['requires_reboot'] is True
sha=pathlib.Path(sys.argv[2]).read_text().strip().split()[0]
assert m['bundle_sha256']==sha
assert m['bundle_url'].endswith('MechOS-0.3.0-hotfix.11-update.tar.zst')
PY

echo '[Hotfix 11 Validation] PASS: VirtualBox MechScope rc=1 path has visible Qt backend retries, correct VM logs, runtime imports and carried visual/update authority.'
