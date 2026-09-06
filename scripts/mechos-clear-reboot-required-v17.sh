#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_CLEAR_REBOOT_REQUIRED_V17
STATE=/var/lib/mechos
LOG=/var/log/mechos-update.log
mkdir -p "$STATE" /var/log
# Never clear the flag if the boot-time Hotfix 17 activation did not complete.
[ -e "$STATE/hotfix-0.3.0-17-applied" ] || exit 0
if [ -e "$STATE/reboot-required" ]; then
  rm -f "$STATE/reboot-required"
  printf '[%s] [reboot-clear-v17] cleared reboot-required after completed Hotfix 17 boot\n' "$(date -Is 2>/dev/null || date)" >>"$LOG" 2>/dev/null || true
fi
exit 0
