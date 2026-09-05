#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_REBOOT_V14
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$LOG_DIR/reboot-v14.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true
log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG" 2>/dev/null || true; }

# Prefer logind directly. This avoids Plasma's logout transition, which could
# leave VirtualBox on a bright/blank compositor background instead of rebooting.
if command -v busctl >/dev/null 2>&1; then
  if busctl call org.freedesktop.login1 /org/freedesktop/login1 \
      org.freedesktop.login1.Manager Reboot b true >>"$LOG" 2>&1; then
    log 'reboot accepted by systemd-logind'
    exit 0
  fi
fi
if command -v loginctl >/dev/null 2>&1; then
  if loginctl reboot >>"$LOG" 2>&1; then
    log 'reboot accepted by loginctl'
    exit 0
  fi
fi
# KDE remains a session-owned fallback for systems where login1 policy differs.
for qdbus in qdbus6 qdbus; do
  if command -v "$qdbus" >/dev/null 2>&1; then
    if "$qdbus" org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot >>"$LOG" 2>&1; then
      log "reboot accepted by KDE via $qdbus"
      exit 0
    fi
  fi
done
if [ "$(id -u)" -eq 0 ]; then
  log 'falling back to root systemctl reboot'
  exec /usr/bin/systemctl reboot
fi
if command -v pkexec >/dev/null 2>&1; then
  log 'requesting PolicyKit systemctl reboot'
  exec pkexec /usr/bin/systemctl reboot
fi
log 'ERROR: no reboot mechanism succeeded'
echo "MechOS could not restart. See $LOG" >&2
exit 1
