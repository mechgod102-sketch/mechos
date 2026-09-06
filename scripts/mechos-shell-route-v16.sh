#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_SHELL_ROUTE_V16
# MECHOS_CREATOR_FIRST_ROUTE_REPAIR_V19
ROUTE="${1:-}"
case "$ROUTE" in
  gaming|mechscope|store|creator|performance|updates|recovery) ;;
  *) echo 'usage: mechos-shell-route {gaming|mechscope|store|creator|performance|updates|recovery}' >&2; exit 2 ;;
esac
[ "$ROUTE" = mechscope ] && ROUTE=gaming

RUNTIME="${XDG_RUNTIME_DIR:-/tmp/mechos-$(id -u)}"
ROUTE_FILE="$RUNTIME/mechos-shell-route-v16"
BASE=/usr/local/libexec/mechos-mode-launch-base-v15
mkdir -p "$RUNTIME"

mechscope_host_running(){
  pgrep -u "$(id -u)" -f '(^|[[:space:]])(/usr/bin/python3[[:space:]]+)?/usr/local/bin/mechscope(\.real)?([[:space:]]|$)' >/dev/null 2>&1
}

if mechscope_host_running; then
  printf '%s\n' "$ROUTE" >"$ROUTE_FILE"
  exit 0
fi

# Creator is a first-class target. Do not start Gaming/MechScope just to reach
# Creator; use the proven Creator handoff directly when the shell is absent.
if [ "$ROUTE" = creator ]; then
  rm -f "$ROUTE_FILE"
  [ -x "$BASE" ] || { echo 'MechOS Creator launcher base missing' >&2; exit 1; }
  exec "$BASE" creator
fi

# Other internal pages require the MechScope shell host. Queue the page and
# start Gaming; the shell poller consumes the route after MechScope is alive.
printf '%s\n' "$ROUTE" >"$ROUTE_FILE"
[ -x "$BASE" ] || { echo 'MechOS base mode launcher missing' >&2; exit 1; }
nohup "$BASE" gaming >/dev/null 2>&1 </dev/null &
exit 0
