#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/workspace/archlive/airootfs
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
RUNTIME=/workspace/scripts/mechos-vm-mode-runtime-hotfix5.sh
LAUNCHER=/workspace/scripts/mechos-mode-launch-hotfix5.sh

log(){ printf '[MechOS Build 119 VM MechScope] %s\n' "$*"; }
fail(){ printf '[MechOS Build 119 VM MechScope] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail 'Live rootfs missing'
[ -s "$ARCHIVE" ] || fail 'installed payload missing'
[ -f "$RUNTIME" ] || fail 'Hotfix 5 VM runtime source missing'
[ -f "$LAUNCHER" ] || fail 'Hotfix 5 mode launcher source missing'
bash -n "$RUNTIME" || fail 'Hotfix 5 VM runtime source syntax failed'
bash -n "$LAUNCHER" || fail 'Hotfix 5 launcher source syntax failed'

install_tree(){
  local tree="$1"
  mkdir -p "$tree/usr/local/bin" "$tree/etc/xdg/autostart" "$tree/usr/share/applications" "$tree/usr/share/wayland-sessions"
  install -m 0755 "$RUNTIME" "$tree/usr/local/bin/mechos-vm-mode-runtime"
  install -m 0755 "$LAUNCHER" "$tree/usr/local/bin/mechos-mode-launch"

  cat > "$tree/etc/xdg/autostart/mechos-vm-mode-runtime.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS VM Mode Runtime
Comment=Restore the selected MechOS mode after Plasma is ready in a virtual machine
Exec=/usr/local/bin/mechos-vm-mode-runtime boot
TryExec=/usr/local/bin/mechos-vm-mode-runtime
Terminal=false
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF

  cat > "$tree/usr/share/applications/mechos-return-gaming.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Return to MechScope
Comment=Open MechScope using the VM-safe MechOS launcher
Exec=/usr/local/bin/mechos-mode-launch gaming
TryExec=/usr/local/bin/mechos-mode-launch
Icon=applications-games
Terminal=false
StartupNotify=true
Categories=Game;System;
EOF

  # Do not change the physical-hardware session wrapper. The canonical session
  # entry continues to launch mechscope-session; only VM desktop mode switches
  # are routed directly to the Plasma-hosted runtime.
  cat > "$tree/usr/share/wayland-sessions/mechscope.desktop" <<'EOF'
[Desktop Entry]
Name=MechScope
Comment=MechOS Gaming Mode
Exec=/usr/local/bin/mechscope-session
TryExec=/usr/local/bin/mechscope-session
Type=Application
DesktopNames=MechScope
EOF

  bash -n "$tree/usr/local/bin/mechos-vm-mode-runtime" || fail "VM runtime syntax failed in $tree"
  bash -n "$tree/usr/local/bin/mechos-mode-launch" || fail "mode launcher syntax failed in $tree"
  grep -Fq 'MECHOS_HOTFIX5_VM_DIRECT_ROUTER_V1' "$tree/usr/local/bin/mechos-mode-launch" || fail "direct VM router missing in $tree"
  grep -Fq '/usr/local/bin/mechscope.real' "$tree/usr/local/bin/mechos-vm-mode-runtime" || fail "real MechScope backend fallback missing in $tree"
  grep -Fq 'oobe-complete' "$tree/usr/local/bin/mechos-vm-mode-runtime" || fail "OOBE gate missing in $tree"
  grep -Fq 'Exec=/usr/local/bin/mechos-vm-mode-runtime boot' "$tree/etc/xdg/autostart/mechos-vm-mode-runtime.desktop" || fail "VM boot autostart missing in $tree"
}

install_tree "$ROOT"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
install_tree "$tmp"
replacement="$ARCHIVE.build119-vm-mechscope"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"; trap - EXIT

log 'VM MechScope mode switches now bypass stale gaming-layer controllers and directly launch the real MechScope UI in Plasma; hardware routing remains unchanged'
