#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX29_MECHSCOPE_LIFETIME_CREATOR_ICONS_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="$ROOT/scripts/mechscope-session-v20.sh"
OVERLAY_SESSION="$ROOT/overlay/rootfs/usr/local/bin/mechscope-session"
RUNTIME="$ROOT/scripts/mechos-mechscope-runtime-v23.py"
VM="$ROOT/scripts/mechos-vm-mode-runtime-hotfix6.sh"
VM_CORE="$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh"
WATCHDOG="$ROOT/scripts/mechos-vm-mechscope-watchdog-v29.sh"
CANVAS="$ROOT/src/mechos_ui/fixed_canvas.py"
REAL_ICONS="$ROOT/src/mechos_ui/creator_real_icons_v22.py"
ICON_PATCH="$ROOT/scripts/mechos-creator-real-icons-owner-v22-patch.py"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-29-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-29.sh"

bash -n "$SESSION" "$OVERLAY_SESSION" "$VM" "$VM_CORE" "$WATCHDOG" "$APPLY" "$BUILD"
python3 -m py_compile "$RUNTIME" "$CANVAS" "$REAL_ICONS" "$ICON_PATCH"

# Physical hardware Gaming Mode must distinguish an intentional mode switch
# from a child/compositor exit, including rc=0 exits.
for f in "$SESSION" "$OVERLAY_SESSION"; do
  grep -Fq 'MECHOS_MECHSCOPE_SESSION_V20' "$f"
  grep -Fq 'MECHOS_SESSION_SUPERVISED=1' "$f"
  grep -Fq 'gaming_requested' "$f"
  grep -Fq 'while Gaming Mode remains active' "$f"
  grep -Fq 'return 90' "$f"
  grep -Fq 'plasma_mechscope_supervisor' "$f"
  grep -Fq '/usr/bin/gamescope' "$f"
done

# The Qt runtime must hold Gaming Mode alive on both VM and supervised hardware
# but stop restoring the window after a genuine Creator/Desktop transition.
grep -Fq 'MECHOS_MECHSCOPE_LIFETIME_V29' "$RUNTIME"
grep -Fq 'MECHOS_SESSION_SUPERVISED' "$RUNTIME"
grep -Fq 'app.setQuitOnLastWindowClosed(False)' "$RUNTIME"
grep -Fq 'if not gaming_mode_active()' "$RUNTIME"
grep -Fq 'window.showFullScreen()' "$RUNTIME"
grep -Fq 'app.aboutToQuit.connect' "$RUNTIME"

# VMware must outlive the old short HF28 startup probe and recover later exits.
grep -Fq 'MECHOS_VM_MECHSCOPE_SUSTAINED_HEALTH_V6' "$VM"
grep -Fq 'for _ in $(seq 1 16)' "$VM"
grep -Fq 'sleep 0.5' "$VM"
grep -Fq 'MechScope sustained health verified for 8 seconds' "$VM"
grep -Fq '/usr/local/libexec/mechos-vm-mode-runtime-v5' "$VM"
grep -Fq '/usr/local/libexec/mechos-vm-mechscope-watchdog-v29' "$VM"
grep -Fq 'MECHOS_VM_MECHSCOPE_PERSISTENT_RUNTIME_V5' "$VM_CORE"
grep -Fq 'MECHOS_VM_MECHSCOPE_WATCHDOG_V29' "$WATCHDOG"
grep -Fq 'while gaming_active' "$WATCHDOG"
grep -Fq 'recovery attempt=' "$WATCHDOG"

# Creator icons must now be source/update-owned, while application buttons still
# prefer real installed application icons through the existing v22 resolver.
grep -Fq 'MECHOS_CREATOR_BUTTON_ICONS_V1' "$CANVAS"
grep -Fq 'MECHOS_BUTTON_ICONS' "$CANVAS"
grep -Fq "'Blender':" "$CANVAS"
grep -Fq "'Unity Hub':" "$CANVAS"
grep -Fq "'Unreal Engine':" "$CANVAS"
grep -Fq 'q.setIcon(icon)' "$CANVAS"
grep -Fq 'widget.setIconSize(QSize(icon_px, icon_px))' "$CANVAS"
grep -Fq 'MECHOS_CREATOR_REAL_ICONS_V22' "$REAL_ICONS"
grep -Fq 'QIcon.fromTheme' "$REAL_ICONS"
grep -Fq '/var/lib/flatpak/exports/share/applications' "$REAL_ICONS"
grep -Fq 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' "$ICON_PATCH"
grep -Fq 'icons.install(shell)' "$ICON_PATCH"

# The boot repair must heal mixed-version public launchers and re-run the real
# icon owner hook before committing the version/marker.
grep -Fq 'MECHOS_HOTFIX29_MECHSCOPE_LIFETIME_CREATOR_ICONS_V1' "$APPLY"
grep -Fq 'mechos-creator-mode.real' "$APPLY"
grep -Fq 'python3 "$ICON_PATCH" "$CREATOR"' "$APPLY"
grep -Fq 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' "$APPLY"
grep -Fq 'install -m0755 "$RUNTIME" "$PUBLIC"' "$APPLY"
grep -Fq "printf '0.3.0-hotfix.29" "$APPLY"
grep -Fq 'touch "$MARKER"' "$APPLY"

# Canonical session is MechScope only; never revive the historical broken name.
grep -Fq 'Exec=/usr/local/bin/mechscope-session' "$BUILD"
grep -Fq 'usr/share/wayland-sessions/mechscope.desktop' "$BUILD"
if grep -R -nF 'Session=mechos-gaming.desktop' \
  "$SESSION" "$RUNTIME" "$VM" "$WATCHDOG" "$CANVAS" "$APPLY" "$BUILD"; then
  echo 'Hotfix 29 source reintroduced obsolete mechos-gaming.desktop session name' >&2
  exit 1
fi

# Build must remain cumulative from Hotfix 28 and include all new recovery parts.
grep -Fq 'MechOS-0.3.0-hotfix.28-update.tar.zst' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.29-update.tar.zst' "$BUILD"
grep -Fq 'mechos-vm-mode-runtime-hotfix6.sh' "$BUILD"
grep -Fq 'mechos-vm-mode-runtime-v5' "$BUILD"
grep -Fq 'mechos-vm-mechscope-watchdog-v29' "$BUILD"
grep -Fq 'mechscope-session-v20.sh' "$BUILD"
grep -Fq 'src/mechos_ui/fixed_canvas.py' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.29'" "$BUILD"
grep -Fq 'requires_reboot' "$BUILD"

printf 'Hotfix 29 MechScope lifetime + Creator icon regression validation passed.\n'
