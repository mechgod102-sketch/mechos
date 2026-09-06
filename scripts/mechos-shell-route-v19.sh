#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_SHELL_ROUTE_V19
# Backward-compatibility marker: v19 keeps the Hotfix 16 route-file contract
# for MechScope-owned pages.
# MECHOS_SHELL_ROUTE_V16
# MECHOS_CREATOR_EXTERNAL_QT_HANDOFF_V26
# Route only into MechScope when the actual MechScope application is alive.
# Creator Mode is deliberately excluded: it owns a separate QApplication.

ROUTE="${1:-}"
case "$ROUTE" in
  gaming|mechscope|store|creator|performance|updates|recovery) ;;
  *) echo 'usage: mechos-shell-route {gaming|mechscope|store|creator|performance|updates|recovery}' >&2; exit 2 ;;
esac
[ "$ROUTE" = mechscope ] && ROUTE=gaming

RUNTIME="${XDG_RUNTIME_DIR:-/tmp/mechos-$(id -u)}"
ROUTE_FILE="$RUNTIME/mechos-shell-route-v16"
BASE=/usr/local/libexec/mechos-mode-launch-base-v15
CREATOR=/usr/local/libexec/mechos-creator-launch-v19
mkdir -p "$RUNTIME"

# Creator is a first-class external target. Handle it before checking for a
# live MechScope host so it can never be queued back into the in-process v16
# SourceFileLoader path that reinitializes Qt/Wayland and aborts MechScope.
if [ "$ROUTE" = creator ]; then
  rm -f "$ROUTE_FILE"
  [ -x "$CREATOR" ] || { echo 'MechOS Creator launcher missing' >&2; exit 1; }
  exec "$CREATOR" creator
fi

mechscope_host_running(){
  pgrep -u "$(id -u)" -f '(^|[[:space:]])(/usr/bin/python3[[:space:]]+)?/usr/local/bin/mechscope(\.real)?([[:space:]]|$)' >/dev/null 2>&1
}

if mechscope_host_running; then
  printf '%s\n' "$ROUTE" >"$ROUTE_FILE"
  exit 0
fi

# Other internal pages need the MechScope shell host. Queue the requested page
# and start Gaming through the proven launcher; the Hotfix 16 poller consumes
# the route once MechScope is genuinely running.
printf '%s\n' "$ROUTE" >"$ROUTE_FILE"
[ -x "$BASE" ] || { echo 'MechOS base mode launcher missing' >&2; exit 1; }
nohup "$BASE" gaming >/dev/null 2>&1 </dev/null &
exit 0
