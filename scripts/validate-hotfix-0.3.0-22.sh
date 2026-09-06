#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/src/mechos_ui/creator_real_icons_v22.py"
PATCH="$ROOT/scripts/mechos-creator-real-icons-owner-v22-patch.py"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-22-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-22.sh"
MODE19="$ROOT/scripts/mechos-mode-launch-v19.sh"
ROUTE19="$ROOT/scripts/mechos-shell-route-v19.sh"
HELPER19="$ROOT/scripts/mechos-update-helper-v19.sh"

python3 -m py_compile "$MODULE" "$PATCH"
bash -n "$APPLY" "$BUILD" "$MODE19" "$ROUTE19" "$HELPER19"

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

# Final v19 public surfaces must remain compatible with the older cumulative
# activation checks that Hotfix 22.1 can invoke on a direct update jump.
for token in \
  MECHOS_MODE_LAUNCH_V15 \
  MECHOS_CREATOR_HANDOFF_V15 \
  MECHOS_CREATOR_VM_OVERLAY_V15 \
  MECHOS_MODE_LAUNCH_V16 \
  MECHOS_MODE_LAUNCH_V19; do
  grep -Fq "$token" "$MODE19"
done
grep -Fq 'MECHOS_SHELL_ROUTE_V16' "$ROUTE19"
grep -Fq 'MECHOS_SHELL_ROUTE_V19' "$ROUTE19"
grep -Fq 'MECHOS_HOTFIX17_HELPER_WARNING_FIX' "$HELPER19"
grep -Fq 'tar --warning=no-timestamp --zstd -xpf' "$HELPER19"

# Hotfix 22.1 must actively orchestrate every missing layer from 15 through 21.
grep -Fq 'MECHOS_HOTFIX22_APPLY_V3' "$APPLY"
grep -Fq 'for n in 15 16 17 18 19 20 21' "$APPLY"
grep -Fq 'mechos-hotfix-0.3.0-${n}-apply' "$APPLY"
grep -Fq 'Hotfixes 15-21 confirmed active' "$APPLY"
grep -Fq 'hotfix-0.3.0-22.1-applied' "$APPLY"
grep -Fq "printf '0.3.0-hotfix.22.1" "$APPLY"

# The bundle remains based on Hotfix 21, but Hotfix 22.1 refreshes all
# cumulative apply helpers. A distinct 22.1 version is required so machines
# that already recorded original Hotfix 22 will see the corrected payload.
grep -Fq 'MechOS-0.3.0-hotfix.21-update.tar.zst' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.22.1-update.tar.zst' "$BUILD"
grep -Fq 'for n in 15 16 17 18 19 20 21' "$BUILD"
grep -Fq 'mechos-mode-launch-v19.sh' "$BUILD"
grep -Fq 'mechos-shell-route-v19.sh' "$BUILD"
grep -Fq 'mechos-update-helper-v19.sh' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.22.1'" "$BUILD"
grep -Fq 'ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-22.1-applied' "$BUILD"
! grep -Fq 'Requires=mechos-hotfix-0.3.0-21.service' "$BUILD"
! grep -Fq 'ConditionPathExists=/var/lib/mechos/installed' "$BUILD"

echo 'Hotfix 22.1 cumulative 15-21 + Creator real-icon validation passed.'
