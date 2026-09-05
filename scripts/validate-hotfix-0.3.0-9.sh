#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.9-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
fail(){ echo "[Hotfix 9 Validation] ERROR: $*" >&2; exit 1; }
[ -s "$BUNDLE" ] || fail 'bundle missing'
[ -s "$SUM" ] || fail 'checksum missing'
[ -s "$MANIFEST" ] || fail 'stable manifest missing'
(cd "$(dirname "$BUNDLE")" && sha256sum -c "$(basename "$SUM")")

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar --zstd -xpf "$BUNDLE" -C "$TMP"
UI="$TMP/usr/local/share/mechos/ui"
THEME="$TMP/usr/share/mechos/theme/reference-v5.qss"
VISUAL="$TMP/usr/local/libexec/mechos-visual-surfaces-v9-patch"
OWNER="$TMP/usr/local/libexec/mechos-final-surface-owner-v8-patch"
APPLY="$TMP/usr/local/libexec/mechos-hotfix-0.3.0-9-apply"
STORE_APPLY="$TMP/usr/local/libexec/mechos-apply-current-store-v8"
STORE_GEN="$TMP/usr/local/libexec/mechos-reference-v5-store-layout.sh"
QLINE="$TMP/usr/local/libexec/mechos-store-qlineedit-patch"

for f in "$THEME" "$VISUAL" "$OWNER" "$APPLY" "$STORE_APPLY" "$STORE_GEN" "$QLINE"; do
  [ -f "$f" ] || fail "missing staged file: $f"
done
for f in fixed_canvas.py update_shell.py recovery_shell.py quick_actions_shell.py creator_shell.py; do
  [ -f "$UI/$f" ] || fail "missing GUI source: $f"
  cmp -s "$ROOT/src/mechos_ui/$f" "$UI/$f" || fail "bundle GUI source differs: $f"
done
cmp -s "$ROOT/src/mechos_ui/reference-v9.qss" "$THEME" || fail 'bundled theme differs from v9 source'

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$VISUAL" "$OWNER" "$QLINE" "$UI/fixed_canvas.py" "$UI/quick_actions_shell.py" "$UI/creator_shell.py"
for f in "$APPLY" "$STORE_APPLY" "$STORE_GEN"; do bash -n "$f"; done

grep -Fq 'MECHOS_VISUAL_SURFACES_V9' "$THEME" || fail 'v9 theme marker missing'
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_FIXED_CANVAS' "$UI/fixed_canvas.py" || fail 'source palette marker missing'
grep -Fq 'MECHOS_QUICK_ACTIONS_VISUAL_V9' "$UI/quick_actions_shell.py" || fail 'Quick Actions visual v9 missing'
for label in 'KEYBOARD RGB' 'Brightness −' 'Audio Settings' 'Recovery Center'; do grep -Fq "$label" "$UI/quick_actions_shell.py" || fail "Quick Actions missing $label"; done
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_QUICK_ACTIONS_WIRING' "$OWNER" || fail 'Quick Actions v9 backend wiring missing'
for key in brightness-down brightness-up rgb-picker rgb-restore rgb-advanced system-settings audio-settings; do grep -Fq "'$key'" "$OWNER" || fail "Quick Actions backend key missing: $key"; done

# Simulate the final visual creator methods.
cat > "$TMP/creator.py" <<'PY'
class Creator(object):
    def app_store(self):
        return None
    def settings(self):
        return None
    def tail(self):
        return None
PY
python3 "$VISUAL" creator "$TMP/creator.py"
for marker in MECHOS_VISUAL_SURFACES_V9_CREATOR_STORE MECHOS_VISUAL_SURFACES_V9_CREATOR_SETTINGS; do grep -Fq "$marker" "$TMP/creator.py" || fail "creator simulation missing $marker"; done
for label in 'Search Creator Store' 'Windows Creator Installer' 'Gaming / MechScope' 'Quick Actions'; do grep -Fq "$label" "$TMP/creator.py" || fail "creator visual control missing: $label"; done
grep -Fq 'textChanged.connect(apply_filter)' "$TMP/creator.py" || fail 'Creator Store search is not wired to filtering'
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/creator.py"

# Generate the base store, then apply the actual v9 storefront.
STORE_ROOT="$TMP/store-root"; mkdir -p "$STORE_ROOT/usr/local/bin"
cat > "$STORE_ROOT/usr/local/bin/mechscope" <<'PY'
class QDialog(object): pass
class QMainWindow(object): pass
class UnifiedStore(QDialog):
    pass
class MechScope(QMainWindow):
    pass
PY
MECHOS_STORE_GENERATOR="$STORE_GEN" bash "$STORE_APPLY" "$STORE_ROOT"
python3 "$VISUAL" unified-store "$STORE_ROOT/usr/local/bin/mechscope"
for marker in MECHOS_REFERENCE_UNIFIED_STORE_V5 MECHOS_VISUAL_SURFACES_V9_UNIFIED_STORE; do grep -Fq "$marker" "$STORE_ROOT/usr/local/bin/mechscope" || fail "store simulation missing $marker"; done
for label in 'Search Selected Store' 'Refresh Local Library' 'Return to MechScope'; do grep -Fq "$label" "$STORE_ROOT/usr/local/bin/mechscope" || fail "Unified Store v9 control missing: $label"; done
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$STORE_ROOT/usr/local/bin/mechscope"

python3 - "$MANIFEST" "$SUM" <<'PY'
import json,pathlib,sys
m=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert m['schema']==1 and m['channel']=='stable'
assert m['version']=='0.3.0-hotfix.9'
assert m['release_name']=='MechOS v0.3.0 Hotfix 9'
assert m['requires_reboot'] is True
sha=pathlib.Path(sys.argv[2]).read_text().strip().split()[0]
assert m['bundle_sha256']==sha
assert m['bundle_url'].endswith('MechOS-0.3.0-hotfix.9-update.tar.zst')
PY

echo '[Hotfix 9 Validation] PASS: actual mode/store/settings/Quick Actions visual authority is bundled, storefront search and controls are configured, and real backend wiring is preserved.'
