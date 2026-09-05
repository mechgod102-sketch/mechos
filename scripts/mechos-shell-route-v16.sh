#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_SHELL_ROUTE_V16
ROUTE="${1:-}"
case "$ROUTE" in
  gaming|mechscope|store|creator|performance|updates|recovery) ;;
  *) echo 'usage: mechos-shell-route {gaming|mechscope|store|creator|performance|updates|recovery}' >&2; exit 2 ;;
esac
[ "$ROUTE" = mechscope ] && ROUTE=gaming
RUNTIME="${XDG_RUNTIME_DIR:-/tmp/mechos-$(id -u)}"
mkdir -p "$RUNTIME"
printf '%s\n' "$ROUTE" >"$RUNTIME/mechos-shell-route-v16"

# If MechScope is not currently alive, bring the gaming shell up through the
# pre-Hotfix16 launcher and leave the requested route queued for its poller.
if ! pgrep -u "$(id -u)" -f '(/usr/local/bin/)?mechscope([[:space:]]|$)|mechscope-session' >/dev/null 2>&1; then
  BASE=/usr/local/libexec/mechos-mode-launch-base-v15
  if [ -x "$BASE" ]; then
    nohup "$BASE" gaming >/dev/null 2>&1 </dev/null &
  elif [ -x /usr/local/bin/mechscope-session ]; then
    nohup /usr/local/bin/mechscope-session >/dev/null 2>&1 </dev/null &
  fi
fi
