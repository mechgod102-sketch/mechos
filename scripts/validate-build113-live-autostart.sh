#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/mechos-build113-live-boot-splash-fix.sh"

fail(){ echo "[validate-build113-live-autostart] ERROR: $*" >&2; exit 1; }

[ -f "$SCRIPT" ] || fail "Build 113 Live boot fix is missing"
bash -n "$SCRIPT" || fail "Build 113 Live boot fix has invalid shell syntax"

grep -Fq '"$ROOT/etc/xdg/autostart"' "$SCRIPT" \
  || fail "Live XDG autostart directory is not recreated by the final Live stage"
grep -Fq 'cat > "$ROOT/etc/xdg/autostart/mechos-live-welcome.desktop"' "$SCRIPT" \
  || fail "Live installer XDG desktop file is not recreated authoritatively"
grep -Fq 'Exec=/usr/local/bin/mechos-live-autostart' "$SCRIPT" \
  || fail "Live XDG autostart bypasses the single-instance wrapper"
grep -Fq '[ -f "$ROOT/etc/xdg/autostart/mechos-live-welcome.desktop" ]' "$SCRIPT" \
  || fail "final Live stage does not verify the XDG autostart exists"

if grep -Fq 'if [ -f "$ROOT/etc/xdg/autostart/mechos-live-welcome.desktop" ]; then' "$SCRIPT"; then
  fail "optional-only XDG patching regression returned; final Live stage must recreate the file"
fi

echo '[validate-build113-live-autostart] OK: final Live stage recreates and validates the installer XDG autostart'
