#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_CLEAR_REBOOT_REQUIRED_V17
STATE=/var/lib/mechos
LOG=/var/log/mechos-update.log
mkdir -p "$STATE" /var/log
if [ -e "$STATE/reboot-required" ]; then
  rm -f "$STATE/reboot-required"
  printf '[%s] [reboot-clear-v17] cleared reboot-required after completed boot\n' "$(date -Is 2>/dev/null || date)" >>"$LOG" 2>/dev/null || true
fi
exit 0
