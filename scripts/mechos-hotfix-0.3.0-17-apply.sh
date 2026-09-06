#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX17_APPLY_V1
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-17-applied"
LOG=/var/log/mechos-hotfix-0.3.0-17.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 17 apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

# Hotfix 17 is layered after the single-window Hotfix 16 activation.
[ -e "$STATE/hotfix-0.3.0-16-applied" ] || { echo 'ERROR: Hotfix 16 activation has not completed'; exit 98; }

TX=/usr/local/libexec/mechos-update-transaction-v13
PATCH=/usr/local/libexec/mechos-hotfix17-updater-patch
CLEAR=/usr/local/libexec/mechos-clear-reboot-required-v17
for f in "$TX" "$PATCH" "$CLEAR"; do
  [ -x "$f" ] || { echo "ERROR: Hotfix17 component missing: $f"; exit 99; }
done

grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$TX"
! grep -Eq '^[[:space:]]*rsync[[:space:]]' "$TX"
bash -n "$TX"
python3 -m py_compile "$PATCH"
bash -n "$CLEAR"

# Silence harmless guest-clock timestamp warnings on future bundle extraction.
for helper in /usr/local/bin/mechos-update-helper /usr/local/libexec/mechos-update-helper-v14; do
  [ -f "$helper" ] || continue
  python3 "$PATCH" helper "$helper"
  bash -n "$helper"
  grep -Fq 'MECHOS_HOTFIX17_HELPER_WARNING_FIX' "$helper"
done

# Make failed installs visually unambiguous. A nonzero update must never leave
# the main status text claiming the update was successfully installed.
for center in /usr/local/libexec/mechos-update-center-v8.py /usr/local/libexec/mechos-update-center-v8-rescue.py; do
  [ -f "$center" ] || continue
  python3 "$PATCH" center "$center"
  python3 -m py_compile "$center"
  grep -Fq 'MECHOS_HOTFIX17_FAILURE_STATE_FIX' "$center"
done

mkdir -p /etc/mechos
printf '0.3.0-hotfix.17\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.17/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.17\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 17\n' >/etc/system-release

touch "$MARKER"
# This process itself runs during the user-requested restart, so the restart
# requirement has now been satisfied. The boot service repeats this safely on
# future boots so the flag can never remain stale forever.
rm -f "$STATE/reboot-required"

echo "[$(date -Is)] Hotfix17 applied: rsync-free transaction engine active, timestamp warnings suppressed, failure-state UI corrected, and stale reboot-required state cleared."
