#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HARDWARE_CREATOR_FINAL_V1

PHASE="${1:-final}"
[ "$PHASE" = final ] || exit 0

ROOT=/workspace/archlive/airootfs
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
SRC=/workspace/src/mechos_ui
OWNER_PATCH=/workspace/scripts/mechos-final-surface-owner-v8-patch.py

log(){ printf '[MechOS Hardware Creator Final] %s\n' "$*"; }
fail(){ printf '[MechOS Hardware Creator Final] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Hardware Creator Final] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -s "$ARCHIVE" ] || fail 'installed-system payload missing'
[ -f "$SRC/fixed_canvas.py" ] || fail 'current fixed_canvas.py missing'
[ -f "$SRC/creator_shell.py" ] || fail 'current creator_shell.py missing'
[ -f "$OWNER_PATCH" ] || fail 'Creator owner patch missing'

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$SRC/fixed_canvas.py" "$SRC/creator_shell.py" "$OWNER_PATCH"
grep -Fq 'MECHOS_VISUAL_SURFACES_V14_FIXED_CANVAS' "$SRC/fixed_canvas.py" \
  || fail 'current responsive FixedCanvas marker missing'
grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V3' "$SRC/fixed_canvas.py" \
  || fail 'current responsive geometry marker missing'
grep -Fq 'class LiveCreatorHome' "$SRC/creator_shell.py" \
  || fail 'current live Creator dashboard source missing'
grep -Fq 'MECHOS_CREATOR_RESPONSIVE_FULLSCREEN_V15' "$OWNER_PATCH" \
  || fail 'Creator responsive fullscreen owner patch missing'

STAGE="$(mktemp -d /tmp/mechos-hardware-creator-final.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
tar --warning=no-timestamp --zstd -xpf "$ARCHIVE" -C "$STAGE"

install -d -m0755 \
  "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/lib/systemd/user" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/mechos/hardware-test"

# The cumulative stable bundle is deliberately overlaid late in hardware builds.
# Reinstall the current source-owned Creator surface after that overlay so an
# older cumulative Creator copy cannot win over the responsive build sources.
install -m0644 "$SRC/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"
install -m0644 "$SRC/creator_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_shell.py"

owner=''
for candidate in \
  "$STAGE/usr/local/bin/mechos-creator-mode.real" \
  "$STAGE/usr/local/bin/mechos-creator-mode" \
  "$STAGE/usr/local/libexec/mechos-creator-mode-v5.py"; do
  [ -f "$candidate" ] || continue
  if grep -Fq 'class Creator(' "$candidate"; then
    owner="$candidate"
    break
  fi
done
[ -n "$owner" ] || fail 'installed Creator owner with class Creator was not found'

# Refresh the owner injection even when the stable overlay supplied an older
# MECHOS_HOTFIX8_SURFACE_OWNER_CREATOR block. The patch clears the generated
# 1180x720 minimum size before fullscreen, which is the clipping seen at 720p,
# VMware scaled displays and other smaller logical resolutions.
python3 "$OWNER_PATCH" "$owner" creator
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_shell.py" \
  "$owner"

grep -Fq 'MECHOS_CREATOR_RESPONSIVE_FULLSCREEN_V15' "$owner" \
  || fail 'Creator owner did not receive responsive fullscreen patch'
grep -Fq 'self.setMinimumSize(1, 1)' "$owner" \
  || fail 'Creator owner still lacks minimum-size reset'
grep -Fq 'self.setMaximumSize(16777215, 16777215)' "$owner" \
  || fail 'Creator owner still lacks maximum-size reset'
grep -Fq 'self.showFullScreen' "$owner" \
  || fail 'Creator owner does not force fullscreen'
grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V3' \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  || fail 'installed payload lost responsive geometry'
grep -Fq 'class LiveCreatorHome' \
  "$STAGE/usr/local/share/mechos/ui/creator_shell.py" \
  || fail 'installed payload lost live Creator dashboard'

# Keep Creator in its own user-service cgroup so leaving MechScope cannot kill
# it. This is written again after the stable overlay for the same last-writer
# reason as the GUI source files above.
cat >"$STAGE/usr/lib/systemd/user/mechos-creator-mode.service" <<'EOF'
[Unit]
Description=MechOS Creator Mode
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=MECHOS_MODE=creator
ExecStart=/usr/local/bin/mechos-creator-mode
Restart=no
TimeoutStopSec=8
KillMode=control-group

[Install]
WantedBy=default.target
EOF

grep -Fq 'ExecStart=/usr/local/bin/mechos-creator-mode' \
  "$STAGE/usr/lib/systemd/user/mechos-creator-mode.service" \
  || fail 'Creator user service is invalid'

# Restore the public entry to the mode router instead of a stale direct desktop
# invocation. The router preserves the hardware/VM-specific handoff behavior.
cat >"$STAGE/usr/share/applications/mechos-creator-mode.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Creator Mode
Comment=Open the MechOS creator workstation
Exec=/usr/local/bin/mechos-mode-launch creator
TryExec=/usr/local/bin/mechos-mode-launch
Icon=applications-graphics
Terminal=false
StartupNotify=true
Categories=Graphics;AudioVideo;Development;
Keywords=MechOS;Creator;Blender;Unity;Unreal;VRChat;MechClip;
EOF

[ -x "$STAGE/usr/local/bin/mechos-mode-launch" ] || fail 'mode launcher missing after stable overlay'
grep -Fq 'MECHOS_CREATOR_EXTERNAL_QT_HANDOFF_V26' "$STAGE/usr/local/bin/mechos-mode-launch" \
  || fail 'Creator external Qt handoff missing after stable overlay'
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch creator' \
  "$STAGE/usr/share/applications/mechos-creator-mode.desktop" \
  || fail 'Creator desktop entry bypasses mode router'

cat >"$STAGE/usr/share/mechos/hardware-test/creator-final" <<'EOF'
MECHOS_HARDWARE_CREATOR_FINAL_V1
source=src/mechos_ui/creator_shell.py
canvas=MECHOS_VM_RESPONSIVE_GEOMETRY_V3
owner=MECHOS_CREATOR_RESPONSIVE_FULLSCREEN_V15
launch=external-user-service
EOF

if [ -f "$STAGE/etc/mechos/hardware-test-build" ]; then
  if grep -q '^creator_final=' "$STAGE/etc/mechos/hardware-test-build"; then
    sed -i 's/^creator_final=.*/creator_final=MECHOS_HARDWARE_CREATOR_FINAL_V1/' \
      "$STAGE/etc/mechos/hardware-test-build"
  else
    printf 'creator_final=MECHOS_HARDWARE_CREATOR_FINAL_V1\n' \
      >>"$STAGE/etc/mechos/hardware-test-build"
  fi
fi

TMP="$ARCHIVE.hardware-creator-final"
tar --zstd -cpf "$TMP" -C "$STAGE" .
mv -f "$TMP" "$ARCHIVE"

tar --zstd -tf "$ARCHIVE" ./usr/local/share/mechos/ui/fixed_canvas.py >/dev/null
tar --zstd -tf "$ARCHIVE" ./usr/local/share/mechos/ui/creator_shell.py >/dev/null
tar --zstd -tf "$ARCHIVE" ./usr/lib/systemd/user/mechos-creator-mode.service >/dev/null
tar --zstd -tf "$ARCHIVE" ./usr/share/mechos/hardware-test/creator-final >/dev/null

log 'current responsive Creator Mode reasserted after stable overlay'
log 'legacy 1180x720 owner constraint is cleared before fullscreen; mode bar and right column now scale into the available viewport'
