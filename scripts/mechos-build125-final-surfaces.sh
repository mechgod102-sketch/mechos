#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/workspace/archlive/airootfs
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
SRC=/workspace/src/mechos_ui
UPDATE=/workspace/scripts/mechos-update-center-reference-v8.py
OWNER_PATCH=/workspace/scripts/mechos-final-surface-owner-v8-patch.py
SETTINGS_PATCH=/workspace/scripts/mechos-creator-settings-v8-patch.py
VISUAL_PATCH=/workspace/scripts/mechos-visual-surfaces-v9-patch.py
STORE_APPLY=/workspace/scripts/mechos-apply-current-store-v8.sh
STORE_GENERATOR=/workspace/scripts/mechos-reference-v5-store-layout.sh
QLINE=/workspace/scripts/mechos-store-qlineedit-patch.py
REBOOT=/workspace/scripts/mechos-reboot-hotfix6.sh
THEME="$SRC/reference-v9.qss"

log(){ printf '[MechOS Final Surfaces v9] %s\n' "$*"; }
fail(){ printf '[MechOS Final Surfaces v9] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail 'Live rootfs missing'
[ -s "$ARCHIVE" ] || fail 'installed payload missing'
for f in "$UPDATE" "$OWNER_PATCH" "$SETTINGS_PATCH" "$VISUAL_PATCH" "$STORE_APPLY" "$STORE_GENERATOR" "$QLINE" "$REBOOT" "$THEME"; do
  [ -f "$f" ] || fail "missing source $f"
done
for f in fixed_canvas.py update_shell.py recovery_shell.py quick_actions_shell.py creator_shell.py; do
  [ -f "$SRC/$f" ] || fail "missing GUI source $SRC/$f"
done
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$UPDATE" "$OWNER_PATCH" "$SETTINGS_PATCH" "$VISUAL_PATCH" "$QLINE"
bash -n "$STORE_APPLY"; bash -n "$STORE_GENERATOR"; bash -n "$REBOOT"

authority_owner(){
  local tree="$1" name="$2" cls="$3" candidate
  for candidate in \
    "$tree/usr/local/bin/$name.real" \
    "$tree/usr/local/bin/$name" \
    "$tree/usr/local/libexec/${name}-v5.py"; do
    [ -f "$candidate" ] || continue
    grep -Fq "class $cls(" "$candidate" && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

patch_tree(){
  local tree="$1" scope="${2:-installed}" recovery quick='' creator='' mechscope
  local -a compile_targets

  case "$scope" in
    live|installed) ;;
    *) fail "invalid surface scope '$scope' for $tree" ;;
  esac

  mkdir -p "$tree/usr/local/share/mechos/ui" "$tree/usr/local/bin" "$tree/usr/local/libexec" "$tree/usr/share/applications" "$tree/usr/share/mechos/theme" "$tree/etc/mechos"

  # Shared visual system. Keep the historical load path so every older owner
  # automatically receives the v9 palette without another startup patch.
  install -m 0644 "$THEME" "$tree/usr/share/mechos/theme/reference-v9.qss"
  install -m 0644 "$THEME" "$tree/usr/share/mechos/theme/reference-v5.qss"

  # Live-authorized source surfaces.
  for f in fixed_canvas.py update_shell.py recovery_shell.py; do
    install -m 0644 "$SRC/$f" "$tree/usr/local/share/mechos/ui/$f"
  done
  if [ "$scope" = "installed" ]; then
    for f in quick_actions_shell.py creator_shell.py; do
      install -m 0644 "$SRC/$f" "$tree/usr/local/share/mechos/ui/$f"
    done
  fi

  # Update Center keeps its verified backend while the source shell owns look.
  install -m 0755 "$UPDATE" "$tree/usr/local/libexec/mechos-update-center-v8.py"
  install -m 0755 "$REBOOT" "$tree/usr/local/bin/mechos-reboot"
  cat > "$tree/usr/local/bin/mechos-update-center" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@"
EOF
  chmod 0755 "$tree/usr/local/bin/mechos-update-center"
  cat > "$tree/usr/share/applications/mechos-update-center.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Update Center
Comment=System Update Control
Exec=/usr/local/bin/mechos-update-center
TryExec=/usr/local/bin/mechos-update-center
Icon=system-software-update
Terminal=false
StartupNotify=true
Categories=System;Settings;
EOF

  recovery="$(authority_owner "$tree" mechos-recovery-center Recovery)" || fail "Recovery owner missing in $tree"
  python3 "$OWNER_PATCH" "$recovery" recovery

  if [ "$scope" = "installed" ]; then
    # Creator Mode and Quick Actions are intentionally post-install-only.
    quick="$(authority_owner "$tree" mechos-quick-actions QuickActions)" || fail "Quick Actions owner missing from installed payload: $tree"
    creator="$(authority_owner "$tree" mechos-creator-mode Creator)" || fail "Creator owner missing from installed payload: $tree"
    python3 "$OWNER_PATCH" "$quick" quick
    python3 "$OWNER_PATCH" "$creator" creator
    # Keep old exact-settings compatibility, then let v9 visual authority win.
    python3 "$SETTINGS_PATCH" "$creator"
  else
    [ ! -e "$tree/usr/local/bin/mechos-quick-actions" ] || fail "post-install-only Quick Actions leaked into Live tree"
    [ ! -e "$tree/usr/local/bin/mechos-quick-actions.real" ] || fail "post-install-only Quick Actions wrapper leaked into Live tree"
    [ ! -e "$tree/usr/local/bin/mechos-creator-mode" ] || fail "post-install-only Creator Mode leaked into Live tree"
    [ ! -e "$tree/usr/local/bin/mechos-creator-mode.real" ] || fail "post-install-only Creator Mode wrapper leaked into Live tree"
  fi

  # Rebuild the canonical store first, then apply the v9 visual structure.
  MECHOS_STORE_GENERATOR="$STORE_GENERATOR" bash "$STORE_APPLY" "$tree"
  if [ -f "$tree/usr/local/bin/mechscope.real" ]; then mechscope="$tree/usr/local/bin/mechscope.real"; else mechscope="$tree/usr/local/bin/mechscope"; fi
  [ -f "$mechscope" ] || fail "MechScope owner missing in $tree"
  python3 "$VISUAL_PATCH" unified-store "$mechscope"
  if [ "$scope" = "installed" ]; then
    python3 "$VISUAL_PATCH" creator "$creator"
  fi

  # Visual v9 introduces searchable store fields. Reassert imports afterwards.
  if grep -Fq 'QLineEdit' "$mechscope"; then python3 "$QLINE" "$mechscope"; fi
  if [ "$scope" = "installed" ] && grep -Fq 'QLineEdit' "$creator"; then python3 "$QLINE" "$creator"; fi

  compile_targets=(
    "$tree/usr/local/libexec/mechos-update-center-v8.py"
    "$recovery"
    "$mechscope"
  )
  if [ "$scope" = "installed" ]; then compile_targets+=("$quick" "$creator"); fi
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "${compile_targets[@]}"
  bash -n "$tree/usr/local/bin/mechos-update-center"

  # Common visual and functional contract.
  grep -Fq 'MECHOS_VISUAL_SURFACES_V9' "$tree/usr/share/mechos/theme/reference-v5.qss" || fail "v9 theme missing in $tree"
  grep -Fq 'MECHOS_VISUAL_SURFACES_V9_FIXED_CANVAS' "$tree/usr/local/share/mechos/ui/fixed_canvas.py" || fail "v9 source palette missing in $tree"
  grep -Fq 'MECHOS_UPDATE_CENTER_REFERENCE_V8' "$tree/usr/local/libexec/mechos-update-center-v8.py" || fail "Update Center backend marker missing in $tree"
  grep -Fq 'SYSTEM UPDATE CONTROL' "$tree/usr/local/share/mechos/ui/update_shell.py" || fail "Update GUI source missing in $tree"
  grep -Fq 'RECOVERY CENTER' "$tree/usr/local/share/mechos/ui/recovery_shell.py" || fail "Recovery GUI source missing in $tree"
  grep -Fq 'MECHOS_HOTFIX8_SURFACE_OWNER_RECOVERY' "$recovery" || fail "Recovery owner is not source-owned in $tree"
  grep -Fq 'MECHOS_REFERENCE_UNIFIED_STORE_V5' "$mechscope" || fail "Unified Store base missing in $tree"
  grep -Fq 'MECHOS_VISUAL_SURFACES_V9_UNIFIED_STORE' "$mechscope" || fail "Unified Store v9 look missing in $tree"
  for label in 'Search Selected Store' 'Refresh Local Library' 'Return to MechScope'; do
    grep -Fq "$label" "$mechscope" || fail "Unified Store v9 control missing: $label"
  done

  if [ "$scope" = "installed" ]; then
    grep -Fq 'MECHOS_QUICK_ACTIONS_VISUAL_V9' "$tree/usr/local/share/mechos/ui/quick_actions_shell.py" || fail "Quick Actions v9 look missing"
    grep -Fq 'MECHOS_VISUAL_SURFACES_V9_QUICK_ACTIONS_WIRING' "$quick" || fail "Quick Actions v9 wiring missing"
    grep -Fq 'MECHOS_HOTFIX8_SURFACE_OWNER_CREATOR' "$creator" || fail "Creator owner is not source-owned"
    grep -Fq 'MECHOS_VISUAL_SURFACES_V9_CREATOR_STORE' "$creator" || fail "Creator Store v9 look missing"
    grep -Fq 'MECHOS_VISUAL_SURFACES_V9_CREATOR_SETTINGS' "$creator" || fail "Creator Settings v9 look missing"
    for label in 'Creator Store' 'Windows Creator Installer' 'Gaming / MechScope' 'Quick Actions'; do
      grep -Fq "$label" "$creator" || fail "Creator visual control missing: $label"
    done
  fi

  printf '0.3.0-hotfix.9\n' > "$tree/etc/mechos/release"
  if [ -f "$tree/etc/mechos/mechos.conf" ]; then
    if grep -q '^MECHOS_VERSION=' "$tree/etc/mechos/mechos.conf"; then
      sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.9/' "$tree/etc/mechos/mechos.conf"
    else
      printf 'MECHOS_VERSION=0.3.0-hotfix.9\n' >> "$tree/etc/mechos/mechos.conf"
    fi
  fi
  printf 'MechOS v0.3.0 Hotfix 9\n' > "$tree/etc/system-release"
}

patch_tree "$ROOT" live
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp" installed
replacement="$ARCHIVE.visual-v9"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"; trap - EXIT

log 'v9 actual-look authority applied: modes, settings, Quick Actions, Update/Recovery, Creator Store and Unified Store are visually aligned and backend-wired'
