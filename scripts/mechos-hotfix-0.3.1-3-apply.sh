#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX_0313_AB_UPDATE_ENGINE_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.1-3-applied"
LOG=/var/log/mechos-hotfix-0.3.1-3.log

mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1
log(){ printf '[%s] [MechOS 0.3.1-hotfix.3] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }

[ "$(id -u)" -eq 0 ] || { log 'ERROR: must run as root'; exit 1; }
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to apply'; exit 0; }
[ ! -e /run/archiso/bootmnt ] || { log 'Live ISO detected; apply skipped'; exit 0; }
[ ! -e "$MARKER" ] || { log 'Hotfix already applied'; exit 0; }

for f in   /usr/local/bin/mechos-update-helper   /usr/local/bin/mechos-update-center   /usr/local/libexec/mechos-update-engine-switch-v38   /usr/local/libexec/mechos-update-self-repair-v0313; do
  [ -x "$f" ] || { log "ERROR: missing required updater component: $f"; exit 2; }
done

grep -Fq 'MECHOS_UPDATE_HELPER_AB_LAUNCHER_V38' /usr/local/bin/mechos-update-helper
grep -Fq 'MECHOS_UPDATE_CENTER_AB_LAUNCHER_V38' /usr/local/bin/mechos-update-center
/usr/local/libexec/mechos-update-engine-switch-v38 --recover
/usr/local/libexec/mechos-update-self-repair-v0313 --repair
/usr/local/bin/mechos-update-helper selftest >/dev/null

install -d -m0755 /etc/mechos
printf '0.3.1-hotfix.3\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.1-hotfix.3/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.1-hotfix.3\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.1 Hotfix 3\n' >/etc/system-release

touch "$MARKER"
log 'Hotfix applied: A/B Update Engine isolation is active.'
