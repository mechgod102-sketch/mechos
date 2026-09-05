#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/workspace/archlive/airootfs
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
RUNTIME=/workspace/scripts/mechos-vm-mode-runtime-hotfix5.sh
LAUNCHER=/workspace/scripts/mechos-mode-launch-hotfix5.sh
STORE_PATCH=/workspace/scripts/mechos-store-qlineedit-patch.py
CENTER=/workspace/scripts/mechos-update-center-recovery-v7.py
REBOOT=/workspace/scripts/mechos-reboot-hotfix6.sh

log(){ printf '[MechOS Build 122 VM Recovery] %s\n' "$*"; }
fail(){ printf '[MechOS Build 122 VM Recovery] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail 'Live rootfs missing'
[ -s "$ARCHIVE" ] || fail 'installed payload missing'
for f in "$RUNTIME" "$LAUNCHER" "$STORE_PATCH" "$CENTER" "$REBOOT"; do [ -f "$f" ] || fail "missing source $f"; done
bash -n "$RUNTIME"; bash -n "$LAUNCHER"; bash -n "$REBOOT"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$STORE_PATCH" "$CENTER"

patch_tree(){
  local tree="$1" target=""
  mkdir -p "$tree/usr/local/bin" "$tree/usr/local/libexec" "$tree/usr/share/applications"
  install -m 0755 "$RUNTIME" "$tree/usr/local/bin/mechos-vm-mode-runtime"
  install -m 0755 "$LAUNCHER" "$tree/usr/local/bin/mechos-mode-launch"
  install -m 0755 "$CENTER" "$tree/usr/local/libexec/mechos-update-center-v7.py"
  install -m 0755 "$STORE_PATCH" "$tree/usr/local/libexec/mechos-store-qlineedit-patch"
  install -m 0755 "$REBOOT" "$tree/usr/local/bin/mechos-reboot"

  cat > "$tree/usr/local/bin/mechos-update-center" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v7.py "$@"
EOF
  chmod 0755 "$tree/usr/local/bin/mechos-update-center"

  cat > "$tree/usr/share/applications/mechos-update-center.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Update Center
Comment=Check, install, and finish MechOS updates
Exec=/usr/local/bin/mechos-update-center
TryExec=/usr/local/bin/mechos-update-center
Icon=system-software-update
Terminal=false
StartupNotify=true
Categories=System;Settings;
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

  if [ -f "$tree/usr/local/bin/mechscope.real" ]; then target="$tree/usr/local/bin/mechscope.real";
  elif [ -f "$tree/usr/local/bin/mechscope" ]; then target="$tree/usr/local/bin/mechscope"; fi
  if [ -n "$target" ] && grep -Fq 'QLineEdit' "$target"; then
    python3 "$STORE_PATCH" "$target"
  fi

  for candidate in "$target" "$tree/usr/local/bin/mechos-creator-mode" "$tree/usr/local/libexec/mechos-creator-mode-v5.py"; do
    [ -n "$candidate" ] && [ -f "$candidate" ] || continue
    if grep -Fq 'QLineEdit' "$candidate"; then python3 "$STORE_PATCH" "$candidate"; fi
    head -n1 "$candidate" | grep -q python && PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$candidate" || true
  done

  bash -n "$tree/usr/local/bin/mechos-update-center"
  bash -n "$tree/usr/local/bin/mechos-vm-mode-runtime"
  grep -Fq 'MECHOS_UPDATE_CENTER_RECOVERY_V7' "$tree/usr/local/libexec/mechos-update-center-v7.py" || fail "Update Center v7 missing in $tree"
  grep -Fq 'MECHOS_VM_MECHSCOPE_PYTHON_EXEC_V2' "$tree/usr/local/bin/mechos-vm-mode-runtime" || fail "VM Python execution fix missing in $tree"
  grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$tree/usr/share/applications/mechos-return-gaming.desktop" || fail "VM shortcut missing in $tree"
}

patch_tree "$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"
replacement="$ARCHIVE.build122-vm-recovery"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"; trap - EXIT

log 'Update Center v7, Creator Store QLineEdit repair, and raw-Python VM MechScope launch are authoritative in Live and installed payloads'
