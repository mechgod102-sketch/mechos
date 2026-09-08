#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_SESSION_AUTOSTART_V31
# MECHOS_SESSION_SINGLE_OWNER_V32

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

# The canonical hardware mechscope-session already owns MechScope supervision.
# Plasma fallback inherits this marker. Do not start a second copy from KDE
# autostart during its startup delay.
if [ "${MECHOS_SESSION_SUPERVISED:-0}" = 1 ]; then
  printf '[%s] supervised hardware session owns MechScope; KDE fallback skipped\n' "$(date -Is 2>/dev/null || date)" >>"$LOG"
  exit 0
fi
case ":${XDG_SESSION_DESKTOP:-}:${DESKTOP_SESSION:-}:" in
  *:MechScope:*|*:mechscope:*)
    printf '[%s] MechScope session detected; KDE fallback skipped\n' "$(date -Is 2>/dev/null || date)" >>"$LOG"
    exit 0
    ;;
esac

pgrep -u "$(id -u)" -f '(/usr/bin/python3[[:space:]]+)?/usr/local/(bin/mechscope(\.real)?|libexec/mechos-mechscope-runtime-v23)([[:space:]]|$)' >/dev/null 2>&1 && exit 0
[ -x "$SAFE" ] || {
  printf '[%s] ERROR: safe MechScope launcher missing: %s\n' "$(date -Is 2>/dev/null || date)" "$SAFE" >>"$LOG"
  exit 1
}

nohup "$SAFE" >>"$LOG" 2>&1 </dev/null &
exit 0
