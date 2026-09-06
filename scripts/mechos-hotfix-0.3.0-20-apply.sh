#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX20_APPLY_V1
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-20-applied"
LOG=/var/log/mechos-hotfix-0.3.0-20.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 20 apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

for f in \
  /usr/local/libexec/mechos-update-transaction-v14 \
  /usr/local/libexec/mechos-update-transaction-v13 \
  /usr/local/libexec/mechos-update-transaction-core-v20; do
  [ -x "$f" ] || { echo "ERROR: Hotfix20 transaction component missing: $f"; exit 101; }
  bash -n "$f"
done

grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' /usr/local/libexec/mechos-update-transaction-v14
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' /usr/local/libexec/mechos-update-transaction-v13
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' /usr/local/libexec/mechos-update-transaction-core-v20

mode="$(stat -c '%a' /)"
other="${mode: -1}"
case "$other" in
  1|3|5|7) ;;
  *) echo "ERROR: installed root directory is not traversable by normal users (mode=$mode). Repair from Live ISO before continuing." >&2; exit 102 ;;
esac

mkdir -p /etc/mechos
printf '0.3.0-hotfix.20\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.20/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.20\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 20\n' >/etc/system-release
rm -f "$STATE/reboot-required"
touch "$MARKER"
echo "[$(date -Is)] Hotfix20 applied: update transactions preserve root directory permissions and verify root traversal before reporting success."
