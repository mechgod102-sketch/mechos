#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"

log() { printf '[MechOS Tutorial Guard] %s\n' "$*"; }
fail() { printf '[MechOS Tutorial Guard] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

patch_wrapper() {
  local wrapper="$1"
  [ -f "$wrapper" ] || return 0

  python3 - "$wrapper" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "# MECHOS_TUTORIAL_WRAPPER_V1" not in text:
    raise SystemExit(f"tutorial wrapper marker missing: {path}")

marker = "# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V2"
if marker in text:
    raise SystemExit(0)

# Upgrade an older guard if it is already present.
if "# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V1" in text:
    old = '''# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V1
# Automatic tutorials are post-install only. The main installer creates this
# marker only after the MechOS payload and post-install stage complete.
if [ ! -e /var/lib/mechos/installed ]; then
  exec "$REAL" "$@"
fi
'''
    new = '''# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V2
# Automatic tutorials are post-install only and must wait until the owner has
# finished the MechOS account/region setup wizard.
if [ ! -e /var/lib/mechos/installed ] || [ ! -e /var/lib/mechos/oobe-complete ]; then
  exec "$REAL" "$@"
fi
'''
    if old not in text:
        raise SystemExit(f"older tutorial guard could not be upgraded: {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    raise SystemExit(0)

needle = '''if [ ! -e "$MARKER" ] && [ -x /usr/local/bin/mechos-tutorial ]; then
'''
replacement = '''# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V2
# Automatic tutorials are post-install only and must wait until the owner has
# finished the MechOS account/region setup wizard.
if [ ! -e /var/lib/mechos/installed ] || [ ! -e /var/lib/mechos/oobe-complete ]; then
  exec "$REAL" "$@"
fi

if [ ! -e "$MARKER" ] && [ -x /usr/local/bin/mechos-tutorial ]; then
'''

if needle not in text:
    raise SystemExit(f"tutorial launch block not found: {path}")

path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")
PY
}

patch_tree() {
  local tree="$1"
  patch_wrapper "$tree/usr/local/bin/mechscope"
  patch_wrapper "$tree/usr/local/bin/mechos-creator-mode"
}

# Defense in depth for the Live rootfs.
patch_tree "$ROOT"

# The installed payload is the authoritative runtime for first-run behavior.
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
[ -s "$ARCHIVE" ] || fail "installed-system payload archive is missing"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tar --zstd -xf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"

for wrapper in \
  "$tmp/usr/local/bin/mechscope" \
  "$tmp/usr/local/bin/mechos-creator-mode"; do
  [ -f "$wrapper" ] || continue
  grep -Fq '# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V2' "$wrapper" \
    || fail "post-install/OOBE tutorial guard missing from $wrapper"
  grep -Fq '/var/lib/mechos/installed' "$wrapper" \
    || fail "installed completion marker check missing from $wrapper"
  grep -Fq '/var/lib/mechos/oobe-complete' "$wrapper" \
    || fail "OOBE completion marker check missing from $wrapper"
done

new_archive="$ARCHIVE.postinstall-tutorial-guard"
tar --zstd -cf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

# Verify the installer and OOBE create both markers used by the runtime gate.
grep -Fq 'touch /var/lib/mechos/installed' "$PAYLOAD/mechos-postinstall-target" \
  || fail "post-install completion marker is not created by installer"
grep -Fq 'oobe-complete' "$ROOT/usr/local/libexec/mechos-oobe-apply" \
  || fail "OOBE completion marker is not created by first-run setup"

bash -n "$ROOT/usr/local/bin/mechscope" \
  || fail "MechScope tutorial wrapper syntax validation failed"
if [ -f "$ROOT/usr/local/bin/mechos-creator-mode" ]; then
  bash -n "$ROOT/usr/local/bin/mechos-creator-mode" \
    || fail "Creator Mode tutorial wrapper syntax validation failed"
fi

log "tutorial auto-launch locked behind completed post-install OOBE"
