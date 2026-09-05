#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
PATCHER="/workspace/scripts/mechos-update-manifest-refresh-runtime.sh"

log(){ printf '[MechOS Update Manifest Final] %s\n' "$*"; }
fail(){ printf '[MechOS Update Manifest Final] ERROR: %s\n' "$*" >&2; exit 1; }

# This helper is intentionally invoked through `bash "$PATCHER"`, so it only
# needs to exist as a readable shell source file. GitHub content writes keep
# these integration helpers at mode 100644; requiring -x caused Build #114 to
# fail even though the patcher was present and valid.
[ -f "$PATCHER" ] || fail "runtime manifest refresh patcher missing"
[ -r "$PATCHER" ] || fail "runtime manifest refresh patcher unreadable"
bash -n "$PATCHER" || fail "runtime manifest refresh patcher syntax invalid"
[ -d "$ROOT" ] || fail "ArchISO rootfs missing"
[ -s "$ARCHIVE" ] || fail "installed-system payload missing"

bash "$PATCHER" "$ROOT"

tmp="$(mktemp -d /tmp/mechos-update-manifest-final.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
bash "$PATCHER" "$tmp"
replacement="$ARCHIVE.manifest-refresh"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log 'Live and installed Update Center helpers now bypass stale stable-manifest caches'
