#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
SAFE_SOURCE="/workspace/scripts/mechos-mechscope-safe-launch-v31.sh"

log() { printf '[MechOS Tutorial Guard] %s\n' "$*"; }
fail() { printf '[MechOS Tutorial Guard] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -f "$SAFE_SOURCE" ] || fail "Python-safe MechScope launcher source is missing: $SAFE_SOURCE"

install_safe_launcher() {
  local tree="$1"
  mkdir -p "$tree/usr/local/libexec"
  install -m0755 "$SAFE_SOURCE" "$tree/usr/local/libexec/mechos-mechscope-safe-launch-v31"
}

patch_wrapper() {
  local wrapper="$1"
  [ -f "$wrapper" ] || return 0

  python3 - "$wrapper" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if not any(f"# MECHOS_TUTORIAL_WRAPPER_V{v}" in text for v in (1,2)):
    raise SystemExit(f"tutorial wrapper marker missing: {path}")

guard_marker = "# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V3"
if guard_marker not in text:
    # Remove older post-install guards before inserting the current one.
    for old_marker in ("# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V1", "# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V2"):
        if old_marker in text:
            start = text.index(old_marker)
            launch = text.index('if [ ! -e "$MARKER" ] && [ -x /usr/local/bin/mechos-tutorial ]; then', start)
            text = text[:start] + text[launch:]
            break

    needle = '''if [ ! -e "$MARKER" ] && [ -x /usr/local/bin/mechos-tutorial ]; then
'''
    replacement = '''# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V3
# Live media remains usable normally. Installed MechOS, however, cannot enter
# MechScope or Creator Mode until the owner finishes first system setup.
if [ ! -e /var/lib/mechos/installed ]; then
  exec "$REAL" "$@"
fi

if [ ! -e /var/lib/mechos/oobe-complete ]; then
  if [ -x /usr/local/bin/mechos-oobe ]; then
    exec /usr/local/bin/mechos-oobe
  fi
  echo "MechOS first system setup must be completed before this mode can start." >&2
  exit 1
fi

if [ ! -e "$MARKER" ] && [ -x /usr/local/bin/mechos-tutorial ]; then
'''
    if needle not in text:
        raise SystemExit(f"tutorial launch block not found: {path}")
    text = text.replace(needle, replacement, 1)

# MechScope's preserved .real file is Python on current hardware builds. Never
# execute it as a shell program. Creator Mode keeps its existing wrapper path.
if path.name == "mechscope":
    safe_marker = "# MECHOS_TUTORIAL_PYTHON_SAFE_V31"
    direct = 'exec "$REAL" "$@"'
    safe = 'MECHOS_MECHSCOPE_TARGET="$REAL" exec /usr/local/libexec/mechos-mechscope-safe-launch-v31 "$@"'
    if safe_marker not in text:
        if direct not in text:
            raise SystemExit(f"MechScope tutorial wrapper contains no REAL exec to repair: {path}")
        text = text.replace(direct, safe)
        lines = text.splitlines()
        for i, line in enumerate(lines):
            if "MECHOS_TUTORIAL_WRAPPER_V" in line:
                lines.insert(i + 1, safe_marker)
                break
        text = "\n".join(lines) + "\n"

path.write_text(text, encoding="utf-8")
PY
}

patch_tree() {
  local tree="$1"
  install_safe_launcher "$tree"
  patch_wrapper "$tree/usr/local/bin/mechscope"
  patch_wrapper "$tree/usr/local/bin/mechos-creator-mode"
}

patch_tree "$ROOT"

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
  grep -Fq '# MECHOS_POSTINSTALL_FIRST_RUN_GUARD_V3' "$wrapper" \
    || fail "post-install/OOBE mode guard missing from $wrapper"
  grep -Fq '/var/lib/mechos/installed' "$wrapper" \
    || fail "installed completion marker check missing from $wrapper"
  grep -Fq '/var/lib/mechos/oobe-complete' "$wrapper" \
    || fail "OOBE completion marker check missing from $wrapper"
  grep -Fq 'exec /usr/local/bin/mechos-oobe' "$wrapper" \
    || fail "incomplete OOBE does not redirect to setup in $wrapper"
done

grep -Fq '# MECHOS_TUTORIAL_PYTHON_SAFE_V31' "$tmp/usr/local/bin/mechscope" \
  || fail "MechScope tutorial wrapper is not Python-safe"
grep -Fq 'mechos-mechscope-safe-launch-v31' "$tmp/usr/local/bin/mechscope" \
  || fail "MechScope wrapper does not route through safe launcher"
if grep -Fq 'exec "$REAL" "$@"' "$tmp/usr/local/bin/mechscope"; then
  fail "MechScope tutorial wrapper still directly executes raw .real target"
fi
grep -Fq 'MECHOS_MECHSCOPE_SAFE_LAUNCH_V31' "$tmp/usr/local/libexec/mechos-mechscope-safe-launch-v31" \
  || fail "Python-safe MechScope launcher missing from installed payload"

new_archive="$ARCHIVE.postinstall-tutorial-guard"
tar --zstd -cf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

grep -Fq 'touch /var/lib/mechos/installed' "$PAYLOAD/mechos-postinstall-target" \
  || fail "post-install completion marker is not created by installer"
grep -Fq 'oobe-complete' "$ROOT/usr/local/libexec/mechos-oobe-apply" \
  || fail "OOBE completion marker is not created by first-run setup"

bash -n "$ROOT/usr/local/bin/mechscope" \
  || fail "MechScope wrapper syntax validation failed"
bash -n "$ROOT/usr/local/libexec/mechos-mechscope-safe-launch-v31" \
  || fail "safe MechScope launcher syntax validation failed"
if [ -f "$ROOT/usr/local/bin/mechos-creator-mode" ]; then
  bash -n "$ROOT/usr/local/bin/mechos-creator-mode" \
    || fail "Creator Mode wrapper syntax validation failed"
fi

log "MechScope/Creator Mode gated behind completed post-install OOBE; MechScope raw Python target is interpreter-safe"
