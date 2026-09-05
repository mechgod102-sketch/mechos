#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.8-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

fail(){ echo "[Hotfix 8 Validation] ERROR: $*" >&2; exit 1; }
[ -s "$BUNDLE" ] || fail 'bundle missing'
[ -s "$SUM" ] || fail 'checksum missing'
[ -s "$MANIFEST" ] || fail 'stable manifest missing'
(cd "$(dirname "$BUNDLE")" && sha256sum -c "$(basename "$SUM")")

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar --zstd -xpf "$BUNDLE" -C "$TMP"
UI="$TMP/usr/local/share/mechos/ui"
UPDATE="$TMP/usr/local/libexec/mechos-update-center-v8.py"
OWNER="$TMP/usr/local/libexec/mechos-final-surface-owner-v8-patch"
SETTINGS="$TMP/usr/local/libexec/mechos-creator-settings-v8-patch"
STORE_APPLY="$TMP/usr/local/libexec/mechos-apply-current-store-v8"
STORE_GEN="$TMP/usr/local/libexec/mechos-reference-v5-store-layout.sh"
QLINE="$TMP/usr/local/libexec/mechos-store-qlineedit-patch"
APPLY="$TMP/usr/local/libexec/mechos-hotfix-0.3.0-8-apply"
WRAPPER="$TMP/usr/local/bin/mechos-update-center"
REBOOT="$TMP/usr/local/bin/mechos-reboot"
VM_RUNTIME="$TMP/usr/local/bin/mechos-vm-mode-runtime"
MODE_LAUNCH="$TMP/usr/local/bin/mechos-mode-launch"

for f in "$UPDATE" "$OWNER" "$SETTINGS" "$STORE_APPLY" "$STORE_GEN" "$QLINE" "$APPLY" "$WRAPPER" "$REBOOT" "$VM_RUNTIME" "$MODE_LAUNCH"; do
  [ -f "$f" ] || fail "missing staged file: $f"
done
for f in fixed_canvas.py update_shell.py recovery_shell.py quick_actions_shell.py creator_shell.py; do
  [ -f "$UI/$f" ] || fail "missing exact GUI source: $f"
  cmp -s "$ROOT/src/mechos_ui/$f" "$UI/$f" || fail "bundle GUI source differs from repository source: $f"
done

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$UPDATE" "$OWNER" "$SETTINGS" "$QLINE" \
  "$UI/fixed_canvas.py" "$UI/update_shell.py" "$UI/recovery_shell.py" "$UI/quick_actions_shell.py" "$UI/creator_shell.py"
for f in "$STORE_APPLY" "$STORE_GEN" "$APPLY" "$WRAPPER" "$REBOOT" "$VM_RUNTIME" "$MODE_LAUNCH"; do bash -n "$f"; done

grep -Fq 'MECHOS_UPDATE_CENTER_REFERENCE_V8' "$UPDATE" || fail 'Update Center v8 marker missing'
grep -Fq 'SYSTEM UPDATE CONTROL' "$UI/update_shell.py" || fail 'canonical Update Center title missing'
grep -Fq 'RECOVERY CENTER' "$UI/recovery_shell.py" || fail 'canonical Recovery Center title missing'
grep -Fq 'QUICK ACTIONS' "$UI/quick_actions_shell.py" || fail 'canonical Quick Actions title missing'
grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V3' "$UI/fixed_canvas.py" || fail 'responsive GUI V3 missing'
grep -Fq 'exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py' "$WRAPPER" || fail 'Update Center wrapper is not v8'
grep -Fq 'MECHOS_VM_MECHSCOPE_PYTHON_EXEC_V2' "$VM_RUNTIME" || fail 'VM MechScope runtime regression'
grep -Fq 'MECHOS_HOTFIX5_VM_DIRECT_ROUTER_V1' "$MODE_LAUNCH" || fail 'VM mode router regression'

# Simulate exact Creator Settings replacement.
cat > "$TMP/creator.py" <<'PY'
#!/usr/bin/env python3
APP='/usr/local/bin/mechos-creator-app'
def spawn(x): pass
class QPushButton(object):
    pass
class Creator(object):
    def scroll(self): pass
    def section(self,*a): pass
    def settings(self):
        return None
    def select(self,i): pass
PY
python3 "$SETTINGS" "$TMP/creator.py"
grep -Fq 'MECHOS_CREATOR_SETTINGS_V8_EXACT' "$TMP/creator.py" || fail 'Creator Settings patch marker missing'
for label in 'System Settings' 'Performance Center' 'Update Center' 'Creator Folder Setup' 'Windows Creator Installer'; do
  grep -Fq "$label" "$TMP/creator.py" || fail "Creator Settings missing $label"
done
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/creator.py"

# Simulate source-owned owner attachment without running any system action. Use
# explicit base classes because the real generated owners are Qt subclasses and
# the owner patcher intentionally matches `class Name(` syntax.
cat > "$TMP/recovery.py" <<'PY'
#!/usr/bin/env python3
class Recovery(object):
    pass
def main(): pass
PY
cat > "$TMP/quick.py" <<'PY'
#!/usr/bin/env python3
class QuickActions(object):
    pass
def main(): pass
PY
cat > "$TMP/creator-owner.py" <<'PY'
#!/usr/bin/env python3
class Creator(object):
    pass
def main(): pass
PY
python3 "$OWNER" "$TMP/recovery.py" recovery
python3 "$OWNER" "$TMP/quick.py" quick
python3 "$OWNER" "$TMP/creator-owner.py" creator
for spec in 'recovery.py:RECOVERY' 'quick.py:QUICK' 'creator-owner.py:CREATOR'; do
  file="${spec%%:*}"; marker="${spec##*:}"
  grep -Fq "MECHOS_HOTFIX8_SURFACE_OWNER_${marker}" "$TMP/$file" || fail "owner patch simulation failed: $file"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/$file"
done

# Run the exact current Unified Store v5 generator against a disposable owner.
STORE_ROOT="$TMP/store-root"; mkdir -p "$STORE_ROOT/usr/local/bin"
cat > "$STORE_ROOT/usr/local/bin/mechscope" <<'PY'
#!/usr/bin/env python3
class QDialog(object): pass
class QMainWindow(object): pass
class UnifiedStore(QDialog):
    pass
class MechScope(QMainWindow):
    pass
PY
MECHOS_STORE_GENERATOR="$STORE_GEN" bash "$STORE_APPLY" "$STORE_ROOT"
grep -Fq 'MECHOS_REFERENCE_UNIFIED_STORE_V5' "$STORE_ROOT/usr/local/bin/mechscope" || fail 'Unified Store exact v5 generation failed'
for label in 'Explore All Games' 'Manage Library' 'Return to MechScope'; do
  grep -Fq "$label" "$STORE_ROOT/usr/local/bin/mechscope" || fail "Unified Store generated control missing: $label"
done

python3 - "$MANIFEST" "$SUM" <<'PY'
import json,pathlib,sys
manifest=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert manifest['schema']==1
assert manifest['channel']=='stable'
assert manifest['version']=='0.3.0-hotfix.8'
assert manifest['release_name']=='MechOS v0.3.0 Hotfix 8'
assert manifest['requires_reboot'] is True
sumline=pathlib.Path(sys.argv[2]).read_text().strip().split()[0]
assert manifest['bundle_sha256']==sumline
assert manifest['bundle_url'].endswith('MechOS-0.3.0-hotfix.8-update.tar.zst')
PY

echo '[Hotfix 8 Validation] PASS: exact current Update Center, Recovery Center, Unified Store v5, Creator Settings and Quick Actions sources/generators are bundled; responsive GUI V3, VM MechScope and reboot protections are preserved.'
