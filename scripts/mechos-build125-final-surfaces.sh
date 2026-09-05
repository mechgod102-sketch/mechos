#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/workspace/archlive/airootfs
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
SRC=/workspace/src/mechos_ui
UPDATE=/workspace/scripts/mechos-update-center-reference-v8.py
OWNER_PATCH=/workspace/scripts/mechos-final-surface-owner-v8-patch.py
SETTINGS_PATCH=/workspace/scripts/mechos-creator-settings-v8-patch.py
STORE_APPLY=/workspace/scripts/mechos-apply-current-store-v8.sh
STORE_GENERATOR=/workspace/scripts/mechos-reference-v5-store-layout.sh
QLINE=/workspace/scripts/mechos-store-qlineedit-patch.py
REBOOT=/workspace/scripts/mechos-reboot-hotfix6.sh

log(){ printf '[MechOS Build 125 Final Surfaces] %s\n' "$*"; }
fail(){ printf '[MechOS Build 125 Final Surfaces] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail 'Live rootfs missing'
[ -s "$ARCHIVE" ] || fail 'installed payload missing'
for f in "$UPDATE" "$OWNER_PATCH" "$SETTINGS_PATCH" "$STORE_APPLY" "$STORE_GENERATOR" "$QLINE" "$REBOOT"; do
  [ -f "$f" ] || fail "missing source $f"
done
for f in fixed_canvas.py update_shell.py recovery_shell.py quick_actions_shell.py creator_shell.py; do
  [ -f "$SRC/$f" ] || fail "missing GUI source $SRC/$f"
done
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$UPDATE" "$OWNER_PATCH" "$SETTINGS_PATCH" "$QLINE"
bash -n "$STORE_APPLY"; bash -n "$STORE_GENERATOR"; bash -n "$REBOOT"

resolve_owner(){
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

  mkdir -p "$tree/usr/local/share/mechos/ui" "$tree/usr/local/bin" "$tree/usr/local/libexec" "$tree/usr/share/applications" "$tree/etc/mechos"

  # Build 128 contract: Creator Mode and Quick Actions are intentionally
  # post-install-only. Never require or recreate their owners in the Live tree.
  # Common Live/installed surfaces still use the exact checked-in GUI source.
  for f in fixed_canvas.py update_shell.py recovery_shell.py; do
    install -m 0644 "$SRC/$f" "$tree/usr/local/share/mechos/ui/$f"
  done
  if [ "$scope" = "installed" ]; then
    for f in quick_actions_shell.py creator_shell.py; do
      install -m 0644 "$SRC/$f" "$tree/usr/local/share/mechos/ui/$f"
    done
  fi

  # Update Center: keep the Hotfix 7 backend behavior, but render the canonical
  # source-owned UpdateShell exactly instead of the temporary recovery UI.
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

  recovery="$(resolve_owner "$tree" mechos-recovery-center Recovery)" || fail "Recovery owner missing in $tree"
  python3 "$OWNER_PATCH" "$recovery" recovery

  if [ "$scope" = "installed" ]; then
    # MECHOS_BUILD128_POSTINSTALL_SCOPE_V1
    quick="$(resolve_owner "$tree" mechos-quick-actions QuickActions)" || fail "Quick Actions owner missing from installed payload: $tree"
    creator="$(resolve_owner "$tree" mechos-creator-mode Creator)" || fail "Creator owner missing from installed payload: $tree"
    python3 "$OWNER_PATCH" "$quick" quick
    python3 "$OWNER_PATCH" "$creator" creator
    python3 "$SETTINGS_PATCH" "$creator"
  else
    # The earlier post-install staging/finalizer deliberately removes these
    # executables from Live before this absolute-last surface pass.
    [ ! -e "$tree/usr/local/bin/mechos-quick-actions" ] || fail "post-install-only Quick Actions leaked into Live tree"
    [ ! -e "$tree/usr/local/bin/mechos-quick-actions.real" ] || fail "post-install-only Quick Actions wrapper leaked into Live tree"
    [ ! -e "$tree/usr/local/bin/mechos-creator-mode" ] || fail "post-install-only Creator Mode leaked into Live tree"
    [ ! -e "$tree/usr/local/bin/mechos-creator-mode.real" ] || fail "post-install-only Creator Mode wrapper leaked into Live tree"
  fi

  # Re-run the exact current v5 Unified Store generator at the absolute-last
  # stage. This prevents older MechScope recovery code from leaving a partial
  # store behind. Then reassert the QLineEdit import repair.
  MECHOS_STORE_GENERATOR="$STORE_GENERATOR" bash "$STORE_APPLY" "$tree"
  if [ -f "$tree/usr/local/bin/mechscope.real" ]; then mechscope="$tree/usr/local/bin/mechscope.real"; else mechscope="$tree/usr/local/bin/mechscope"; fi
  [ -f "$mechscope" ] || fail "MechScope owner missing in $tree"
  if grep -Fq 'QLineEdit' "$mechscope"; then python3 "$QLINE" "$mechscope"; fi
  if [ "$scope" = "installed" ] && grep -Fq 'QLineEdit' "$creator"; then python3 "$QLINE" "$creator"; fi

  compile_targets=(
    "$tree/usr/local/libexec/mechos-update-center-v8.py"
    "$recovery"
    "$mechscope"
  )
  if [ "$scope" = "installed" ]; then
    compile_targets+=("$quick" "$creator")
  fi
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "${compile_targets[@]}"
  bash -n "$tree/usr/local/bin/mechos-update-center"

  # Common final content contract for Live and installed trees.
  grep -Fq 'MECHOS_UPDATE_CENTER_REFERENCE_V8' "$tree/usr/local/libexec/mechos-update-center-v8.py" || fail "Update Center v8 marker missing in $tree"
  grep -Fq "SYSTEM UPDATE CONTROL" "$tree/usr/local/share/mechos/ui/update_shell.py" || fail "Update GUI source missing in $tree"
  grep -Fq "RECOVERY CENTER" "$tree/usr/local/share/mechos/ui/recovery_shell.py" || fail "Recovery GUI source missing in $tree"
  grep -Fq 'MECHOS_HOTFIX8_SURFACE_OWNER_RECOVERY' "$recovery" || fail "Recovery owner is not source-owned in $tree"
  grep -Fq 'MECHOS_REFERENCE_UNIFIED_STORE_V5' "$mechscope" || fail "Unified Store v5 missing in $tree"
  for label in 'Explore All Games' 'Manage Library' 'Return to MechScope'; do
    grep -Fq "$label" "$mechscope" || fail "Unified Store control missing: $label"
  done

  # Creator Mode, Creator Settings and Quick Actions exist only in the installed
  # payload. Validate their exact owners there instead of forcing them into Live.
  if [ "$scope" = "installed" ]; then
    grep -Fq "QUICK ACTIONS" "$tree/usr/local/share/mechos/ui/quick_actions_shell.py" || fail "Quick Actions GUI source missing in installed payload"
    grep -Fq 'MECHOS_HOTFIX8_SURFACE_OWNER_QUICK' "$quick" || fail "Quick Actions owner is not source-owned in installed payload"
    grep -Fq 'MECHOS_HOTFIX8_SURFACE_OWNER_CREATOR' "$creator" || fail "Creator owner is not source-owned in installed payload"
    grep -Fq 'MECHOS_CREATOR_SETTINGS_V8_EXACT' "$creator" || fail "Creator Settings exact page missing in installed payload"
    for label in 'System Settings' 'Performance Center' 'Update Center' 'Creator Folder Setup' 'Windows Creator Installer'; do
      grep -Fq "$label" "$creator" || fail "Creator Settings control missing: $label"
    done
  fi

  printf '0.3.0-hotfix.8\n' > "$tree/etc/mechos/release"
  if [ -f "$tree/etc/mechos/mechos.conf" ]; then
    if grep -q '^MECHOS_VERSION=' "$tree/etc/mechos/mechos.conf"; then
      sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.8/' "$tree/etc/mechos/mechos.conf"
    else
      printf 'MECHOS_VERSION=0.3.0-hotfix.8\n' >> "$tree/etc/mechos/mechos.conf"
    fi
  fi
  printf 'MechOS v0.3.0 Hotfix 8\n' > "$tree/etc/system-release"
}

# Live contains only Live-authorized surfaces. Creator Mode and Quick Actions
# are patched after extracting the installed payload where they actually live.
patch_tree "$ROOT" live
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp" installed
replacement="$ARCHIVE.build125-final-surfaces"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"; trap - EXIT

log 'Live Update/Recovery/Unified Store and installed Update/Recovery/Unified Store/Creator Settings/Quick Actions are exact current GUI authorities'
