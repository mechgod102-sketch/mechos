#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_SESSION_AUTOSTART_V31

[ "$(id -un)" != mechos-setup ] || exit 0
[ -f /var/lib/mechos/installed ] || exit 0
[ -f /var/lib/mechos/oobe-complete ] || exit 0
[ ! -e /run/archiso/bootmnt ] || exit 0

MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/session-mode"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/mechscope-autostart-v31.log"
SAFE=/usr/local/libexec/mechos-mechscope-safe-launch-v31
mkdir -p "$STATE_DIR"

MODE=gaming
[ -r "$MODE_FILE" ] && MODE="$(tr -d '[:space:]' <"$MODE_FILE")"
[ "$MODE" = gaming ] || exit 0

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -n "$virt" ] && [ "$virt" != none ]; then
  exec /usr/local/bin/mechos-vm-mode-runtime gaming
fi

pgrep -u "$(id -u)" -f '(/usr/bin/python3[[:space:]]+)?/usr/local/(bin/mechscope(\.real)?|libexec/mechos-mechscope-runtime-v23)([[:space:]]|$)' >/dev/null 2>&1 && exit 0
[ -x "$SAFE" ] || {
  printf '[%s] ERROR: safe MechScope launcher missing: %s\n' "$(date -Is 2>/dev/null || date)" "$SAFE" >>"$LOG"
  exit 1
}

nohup "$SAFE" >>"$LOG" 2>&1 </dev/null &
exit 0
