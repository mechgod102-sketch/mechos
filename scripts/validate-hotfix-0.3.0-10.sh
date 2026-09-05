#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.10-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
fail(){ echo "[Hotfix 10 Validation] ERROR: $*" >&2; exit 1; }

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
CREATOR_V10_OWNER="$TMP/usr/local/libexec/mechos-creator-visual-owner-v10-patch"
APPLY="$TMP/usr/local/libexec/mechos-hotfix-0.3.0-10-apply"
STORE_APPLY="$TMP/usr/local/libexec/mechos-apply-current-store-v8"
STORE_GEN="$TMP/usr/local/libexec/mechos-reference-v5-store-layout.sh"
QLINE="$TMP/usr/local/libexec/mechos-store-qlineedit-patch"
MODE_LAUNCH="$TMP/usr/local/bin/mechos-mode-launch"
VM_RUNTIME="$TMP/usr/local/bin/mechos-vm-mode-runtime"

for f in "$THEME" "$VISUAL" "$OWNER" "$CREATOR_V10_OWNER" "$APPLY" "$STORE_APPLY" "$STORE_GEN" "$QLINE" "$MODE_LAUNCH" "$VM_RUNTIME"; do
  [ -f "$f" ] || fail "missing staged file: $f"
done
for f in fixed_canvas.py update_shell.py recovery_shell.py quick_actions_shell.py creator_shell.py creator_visual_shell_v10.py; do
  [ -f "$UI/$f" ] || fail "missing GUI source: $f"
  cmp -s "$ROOT/src/mechos_ui/$f" "$UI/$f" || fail "bundle GUI source differs: $f"
done
cmp -s "$ROOT/src/mechos_ui/reference-v9.qss" "$THEME" || fail 'bundled theme differs from v9 source'
cmp -s "$ROOT/scripts/mechos-mode-launch-hotfix10.sh" "$MODE_LAUNCH" || fail 'bundled MechScope launcher differs from Hotfix 10 source'

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$VISUAL" "$OWNER" "$CREATOR_V10_OWNER" "$QLINE" \
  "$UI/fixed_canvas.py" "$UI/quick_actions_shell.py" "$UI/creator_shell.py" "$UI/creator_visual_shell_v10.py"
for f in "$APPLY" "$STORE_APPLY" "$STORE_GEN" "$MODE_LAUNCH" "$VM_RUNTIME"; do bash -n "$f"; done

# Graphical Creator Mode must be more than a palette/geometry change.
grep -Fq 'MECHOS_CREATOR_VISUALS_V10' "$UI/creator_visual_shell_v10.py" || fail 'Creator v10 visual marker missing'
for token in 'badge_pixmap' 'hero_pixmap' 'setIcon' 'VisualCreatorHome' 'CreatorVisualShellV10' 'refresh_projects'; do
  grep -Fq "$token" "$UI/creator_visual_shell_v10.py" || fail "Creator graphical implementation missing: $token"
done
for app in blender unityhub unreal vscode gitkraken krita obs godot kdenlive audacity vrchat; do
  grep -Fq "\"$app\"" "$UI/creator_visual_shell_v10.py" || fail "Creator visual badge missing app key: $app"
done

# Prove the late owner patch wins after the existing Creator class.
cat > "$TMP/creator-owner.py" <<'PY'
class Creator(object):
    def build(self):
        return None

def main():
    pass
PY
python3 "$CREATOR_V10_OWNER" "$TMP/creator-owner.py"
grep -Fq 'MECHOS_HOTFIX10_CREATOR_VISUAL_OWNER_V1' "$TMP/creator-owner.py" || fail 'Creator v10 owner marker missing after simulation'
grep -Fq "creator_visual_shell_v10.py" "$TMP/creator-owner.py" || fail 'Creator owner does not load visual shell'
grep -Fq 'Creator.build = _mechos_surface_v10_creator_build' "$TMP/creator-owner.py" || fail 'Creator v10 build assignment missing'
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/creator-owner.py"

# MechScope: preserve normal hardware path, but do not trust a successful
# controller return unless a real MechScope process appears.
grep -Fq 'MECHOS_HOTFIX10_PHYSICAL_MECHSCOPE_FALLBACK_V1' "$MODE_LAUNCH" || fail 'Hotfix 10 MechScope marker missing'
for token in \
  'requesting accelerated controller start' \
  'wait_for_mechscope' \
  'controller produced no MechScope process within 5 seconds' \
  'launch_mechscope_direct' \
  'direct fallback: MechScope launch healthy' \
  'mechos-vm-mode-runtime'; do
  grep -Fq "$token" "$MODE_LAUNCH" || fail "MechScope fallback token missing: $token"
done
if grep -Fq 'export QT_OPENGL=software' "$MODE_LAUNCH"; then
  fail 'physical launcher must not force software rendering'
fi

# Keep Hotfix 9 storefront/backend authority in the self-contained update.
grep -Fq 'MECHOS_VISUAL_SURFACES_V9' "$THEME" || fail 'v9 visual baseline missing'
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_FIXED_CANVAS' "$UI/fixed_canvas.py" || fail 'v9 fixed-canvas source missing'
grep -Fq 'MECHOS_QUICK_ACTIONS_VISUAL_V9' "$UI/quick_actions_shell.py" || fail 'Quick Actions visual baseline missing'

python3 - "$MANIFEST" "$SUM" <<'PY'
import json, pathlib, sys
m=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert m['schema']==1 and m['channel']=='stable'
assert m['version']=='0.3.0-hotfix.10'
assert m['release_name']=='MechOS v0.3.0 Hotfix 10'
assert m['requires_reboot'] is True
sha=pathlib.Path(sys.argv[2]).read_text().strip().split()[0]
assert m['bundle_sha256']==sha
assert m['bundle_url'].endswith('MechOS-0.3.0-hotfix.10-update.tar.zst')
PY

echo '[Hotfix 10 Validation] PASS: graphical Creator visuals are bundled and authoritative; physical MechScope keeps the accelerated controller path with verified direct fallback and detailed diagnostics.'
