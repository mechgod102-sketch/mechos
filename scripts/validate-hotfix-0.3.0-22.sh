#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/src/mechos_ui/creator_real_icons_v22.py"
PATCH="$ROOT/scripts/mechos-creator-real-icons-owner-v22-patch.py"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-22-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-22.sh"

python3 -m py_compile "$MODULE" "$PATCH"
bash -n "$APPLY" "$BUILD"

for token in \
  MECHOS_CREATOR_REAL_ICONS_V22 \
  QIcon.fromTheme \
  /usr/share/applications \
  /var/lib/flatpak/exports/share/applications \
  /var/lib/flatpak/appstream \
  org.blender.Blender \
  com.unity.UnityHub \
  com.obsproject.Studio \
  org.kde.krita \
  davinci \
  vrchat; do
  grep -Fq "$token" "$MODULE"
done

grep -Fq 'visual_module.decorate_button = decorate_button' "$MODULE"
grep -Fq 'original(button, key, size, installed)' "$MODULE"
grep -Fq 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' "$PATCH"
grep -Fq "creator_real_icons_v22.py" "$PATCH"
grep -Fq 'icons.install(shell)' "$PATCH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/creator-owner.py" <<'PY'
#!/usr/bin/env python3
# MECHOS_HOTFIX10_CREATOR_VISUAL_OWNER_V1
def _mechos_surface_v10_module(filename, module_name):
    return object()

def _mechos_surface_v10_creator_build(self):
    shell = _mechos_surface_v10_module('creator_visual_shell_v10.py', 'mechos_creator_visual_shell_v10')
    ui = shell.CreatorVisualShellV10(self, self)
PY
python3 "$PATCH" "$TMP/creator-owner.py"
grep -Fq 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' "$TMP/creator-owner.py"
grep -Fq "icons = _mechos_surface_v10_module('creator_real_icons_v22.py'" "$TMP/creator-owner.py"
grep -Fq 'icons.install(shell)' "$TMP/creator-owner.py"
python3 -m py_compile "$TMP/creator-owner.py"

grep -Fq "printf '0.3.0-hotfix.22" "$APPLY"
grep -Fq 'MechOS-0.3.0-hotfix.21-update.tar.zst' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.22'" "$BUILD"

echo 'Hotfix 22 Creator real-icon validation passed.'
