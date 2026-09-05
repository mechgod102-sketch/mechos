#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
PATCHER="/workspace/scripts/mechos-update-manifest-refresh-runtime.sh"

log(){ printf '[MechOS Update Manifest Final] %s\n' "$*"; }
fail(){ printf '[MechOS Update Manifest Final] ERROR: %s\n' "$*" >&2; exit 1; }

[ -x "$PATCHER" ] || fail "runtime manifest refresh patcher missing"
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
