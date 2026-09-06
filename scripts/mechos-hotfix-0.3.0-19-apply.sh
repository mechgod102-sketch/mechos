#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX19_APPLY_V1
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-19-applied"
LOG=/var/log/mechos-hotfix-0.3.0-19.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 19 apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

for f in \
  /usr/local/bin/mechos-update-center \
  /usr/local/bin/mechos-update-helper \
  /usr/local/bin/mechos-reboot \
  /usr/local/bin/mechos-update-rescue \
  /usr/local/bin/mechos-mode-launch \
  /usr/local/bin/mechos-shell-route \
  /usr/local/bin/mechscope-session \
  /usr/local/libexec/mechos-creator-launch-v19 \
  /usr/local/libexec/mechos-update-transaction-v14; do
  [ -x "$f" ] || { echo "ERROR: Hotfix19 component missing: $f"; exit 99; }
done

for f in \
  /usr/local/bin/mechos-update-helper \
  /usr/local/bin/mechos-reboot \
  /usr/local/bin/mechos-update-rescue \
  /usr/local/bin/mechos-mode-launch \
  /usr/local/bin/mechos-shell-route \
  /usr/local/bin/mechscope-session \
  /usr/local/libexec/mechos-creator-launch-v19 \
  /usr/local/libexec/mechos-update-transaction-v14; do
  bash -n "$f"
done

python3 -m py_compile /usr/local/libexec/mechos-update-center-v8.py

grep -Fq 'MECHOS_UPDATE_HELPER_V19' /usr/local/bin/mechos-update-helper
grep -Fq 'MECHOS_UPDATE_RESCUE_V19' /usr/local/bin/mechos-update-rescue
grep -Fq 'MECHOS_MODE_LAUNCH_V19' /usr/local/bin/mechos-mode-launch
grep -Fq 'MECHOS_SHELL_ROUTE_V19' /usr/local/bin/mechos-shell-route
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V19' /usr/local/bin/mechscope-session
grep -Fq 'MECHOS_CREATOR_HANDOFF_V15' /usr/local/libexec/mechos-creator-launch-v19
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' /usr/local/libexec/mechos-update-transaction-v14

# Creator must be a first-class target: if the shell is absent, launch Creator
# directly rather than bootstrapping Gaming/MechScope first.
grep -Fq 'exec "$CREATOR" creator' /usr/local/bin/mechos-mode-launch
grep -Fq 'exec "$CREATOR" creator' /usr/local/bin/mechos-shell-route

# Physical MechScope must have a safe fallback and must not force VRR/HDR.
grep -Fq 'MECHOS_ENABLE_VRR' /usr/local/bin/mechscope-session
grep -Fq 'starting MechScope inside Plasma fallback' /usr/local/bin/mechscope-session
! grep -Fq '[[ "${MECHOS_DISABLE_VRR:-0}" != "1" ]] && GS_ARGS+=(--adaptive-sync)' /usr/local/bin/mechscope-session

# Public updater trio must survive the transaction and remain callable.
/usr/local/bin/mechos-update-helper status >/tmp/mechos-hotfix19-status.$$ 2>&1 || {
  cat /tmp/mechos-hotfix19-status.$$ || true
  rm -f /tmp/mechos-hotfix19-status.$$
  echo 'ERROR: update helper status self-test failed' >&2
  exit 100
}
grep -Fq 'CURRENT_MECHOS_VERSION=' /tmp/mechos-hotfix19-status.$$
rm -f /tmp/mechos-hotfix19-status.$$

mkdir -p /etc/mechos
printf '0.3.0-hotfix.19\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.19/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.19\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 19\n' >/etc/system-release
rm -f "$STATE/reboot-required"
touch "$MARKER"
echo "[$(date -Is)] Hotfix19 applied: updater trio restored, staged transaction bootstrap enabled, Creator routes directly, and hardware MechScope has a conservative Gamescope/Plasma fallback."
