#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX_0312_UPDATE_SELF_REPAIR_V1
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.1-2-applied"
LOG=/var/log/mechos-hotfix-0.3.1-2.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1
log(){ printf '[%s] [MechOS 0.3.1-hotfix.2] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }
[ "$(id -u)" -eq 0 ] || { log 'ERROR: must run as root'; exit 1; }
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to apply'; exit 0; }
[ ! -e /run/archiso/bootmnt ] || { log 'Live ISO detected; apply skipped'; exit 0; }
[ ! -e "$MARKER" ] || { log 'Hotfix already applied'; exit 0; }

/usr/local/libexec/mechos-update-self-repair-v0312 --repair

install -d -m0755 /etc/mechos
printf '0.3.1-hotfix.2\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.1-hotfix.2/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.1-hotfix.2\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.1 Hotfix 2\n' >/etc/system-release
touch "$MARKER"
log 'Hotfix applied: Update Center self-repair is active.'
