#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX18_APPLY_V1
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-18-applied"
LOG=/var/log/mechos-hotfix-0.3.0-18.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 18 apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

for f in \
  /usr/local/bin/mechos-update-helper \
  /usr/local/libexec/mechos-update-helper-core-v18 \
  /usr/local/libexec/mechos-pacman-health-v18 \
  /usr/local/libexec/mechos-update-transaction-v14; do
  [ -x "$f" ] || { echo "ERROR: Hotfix18 component missing: $f"; exit 98; }
done
bash -n /usr/local/bin/mechos-update-helper
bash -n /usr/local/libexec/mechos-pacman-health-v18
bash -n /usr/local/libexec/mechos-update-transaction-v14

grep -Fq 'MECHOS_UPDATE_HELPER_V18' /usr/local/bin/mechos-update-helper
grep -Fq 'MECHOS_PACMAN_HEALTH_V18' /usr/local/libexec/mechos-pacman-health-v18
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' /usr/local/libexec/mechos-update-transaction-v14

# Repair package-manager parent permissions during activation as well as before
# every future package update.
/usr/local/libexec/mechos-pacman-health-v18

mkdir -p /etc/mechos
printf '0.3.0-hotfix.18\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.18/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.18\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 18\n' >/etc/system-release
rm -f "$STATE/reboot-required"
touch "$MARKER"
echo "[$(date -Is)] Hotfix18 applied: pacman download paths repaired; package failures no longer invalidate a committed MechOS update."
