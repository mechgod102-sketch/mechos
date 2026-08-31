#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PACKAGES="/workspace/archlive/packages.x86_64"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ROOTFS_ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
INSTALLER_MEMBER="./usr/local/libexec/mechos-creator-app-installer"

log() { printf '[MechOS Footprint] %s\n' "$*"; }
fail() { printf '[MechOS Footprint] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Footprint] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -f "$PACKAGES" ] || fail "ArchISO package list is missing"
[ -s "$ROOTFS_ARCHIVE" ] || fail "installed-system payload archive is missing"

# Large creator applications remain available through Creator Mode but no
# longer inflate every Live ISO and installed system by default.
OPTIONAL_CREATOR_PACKAGES=(
  blender
  obs-studio
  kdenlive
  krita
)

for pkg in "${OPTIONAL_CREATOR_PACKAGES[@]}"; do
  sed -i "/^${pkg}$/d" "$PACKAGES"
  if grep -qx "$pkg" "$PACKAGES"; then
    fail "optional Creator package still present in core ISO list: $pkg"
  fi
done

# Creator Mode runtime is intentionally post-install-only. By this point the
# cumulative integration has already packed it into mechos-rootfs.tar.zst and
# removed it from the Live SquashFS. Validate the installed-system copy instead
# of requiring the helper to leak back into the Live image.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
INSTALLER="$tmp/mechos-creator-app-installer"
if ! tar --zstd -xOf "$ROOTFS_ARCHIVE" "$INSTALLER_MEMBER" > "$INSTALLER"; then
  fail "Creator Mode app installer is missing from installed-system payload"
fi
[ -s "$INSTALLER" ] || fail "Creator Mode app installer in payload is empty"

# Verify the one-click Creator installer still exposes every deferred app.
grep -Fq 'blender) PKG=blender' "$INSTALLER" || fail "Blender on-demand installer mapping is missing"
grep -Fq 'obs) PKG=obs-studio' "$INSTALLER" || fail "OBS on-demand installer mapping is missing"
grep -Fq 'kdenlive) PKG=kdenlive' "$INSTALLER" || fail "Kdenlive on-demand installer mapping is missing"
grep -Fq 'krita) PKG=krita' "$INSTALLER" || fail "Krita on-demand installer mapping is missing"

rm -rf "$tmp"
trap - EXIT

log "Core ISO slimmed: Blender, OBS Studio, Kdenlive and Krita are Creator Mode on-demand installs; installed payload verified"
