#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX25_UPDATE_OOBE_RECOVERY_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-25-applied"
REARM=/usr/local/libexec/mechos-oobe-rearm-v25
SDDM=/etc/sddm.conf.d
SETUP_USER=mechos-setup

log(){ printf '[MechOS Hotfix 25] %s\n' "$*"; }
fail(){ printf '[MechOS Hotfix 25] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Hotfix 25] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to repair'; exit 0; }

mkdir -p "$STATE" "$SDDM"

[ -x /usr/local/bin/mechos-update-helper ] || fail 'update helper missing after cumulative payload'
grep -Fq 'MECHOS_UPDATE_HELPER_V25_RELEASE_COMMIT_V1' /usr/local/bin/mechos-update-helper \
  || fail 'Hotfix 25 update helper not installed'
[ -x /usr/local/libexec/mechos-update-transaction-v14 ] || fail 'transaction v14 path missing'
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V25_RELEASE_COMMIT_V1' /usr/local/libexec/mechos-update-transaction-v14 \
  || fail 'Hotfix 25 transaction engine not installed'
[ -x "$REARM" ] || fail 'persistent OOBE rearm helper missing'

# If account setup did not finish, reconstruct the temporary transport account,
# SDDM route, polkit rule and user autostart now. The permanently enabled rearm
# service repeats this before SDDM on every future boot until oobe-complete.
if [ ! -f "$STATE/oobe-complete" ]; then
  "$REARM"
else
  # Completed systems must never be sent back into mechos-setup.
  shopt -s nullglob
  for cfg in "$SDDM"/*.conf; do
    if grep -Fq "$SETUP_USER" "$cfg" 2>/dev/null; then rm -f "$cfg"; fi
  done
  shopt -u nullglob
  rm -f \
    /etc/systemd/user/default.target.wants/mechos-oobe-autostart.service \
    /etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service
  if id "$SETUP_USER" >/dev/null 2>&1; then
    userdel -r "$SETUP_USER" >/dev/null 2>&1 || userdel "$SETUP_USER" >/dev/null 2>&1 || true
  fi
  rm -rf /home/mechos-setup
  cat >"$SDDM/99-mechos-final-user.conf" <<'EOF'
[Autologin]
User=
Session=mechscope.desktop
Relogin=false
EOF
fi

systemctl daemon-reload || true

# Regression contracts.
grep -Fq 'ConditionPathExists=!/var/lib/mechos/oobe-complete' \
  /usr/lib/systemd/system/mechos-oobe-rearm-v25.service \
  || fail 'OOBE rearm service is not completion-gated'
grep -Fq 'User=mechos-setup' "$SDDM/98-mechos-oobe.conf" 2>/dev/null \
  || [ -f "$STATE/oobe-complete" ] \
  || fail 'incomplete OOBE has no setup-user SDDM route'

touch "$MARKER"
log 'Hotfix 25 applied: update version commits are verified and incomplete OOBE now self-rearms until completion.'
