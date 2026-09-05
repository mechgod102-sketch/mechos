#!/usr/bin/env bash
set -Eeuo pipefail

# MechOS reboot authority for graphical sessions.
# KDE's shutdown service is preferred because it follows the same path as the
# Plasma system menu. login1 is the compositor-independent fallback. Only if
# both session-owned mechanisms fail do we ask PolicyKit to run systemctl.
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$LOG_DIR/reboot.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true
log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG" 2>/dev/null || true; }

if command -v qdbus6 >/dev/null 2>&1; then
  if qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot >>"$LOG" 2>&1; then
    log 'reboot accepted by KDE Plasma shutdown service (qdbus6)'
    exit 0
  fi
fi

if command -v qdbus >/dev/null 2>&1; then
  if qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot >>"$LOG" 2>&1; then
    log 'reboot accepted by KDE Plasma shutdown service (qdbus)'
    exit 0
  fi
fi

if command -v busctl >/dev/null 2>&1; then
  if busctl call org.freedesktop.login1 /org/freedesktop/login1 \
      org.freedesktop.login1.Manager Reboot b true >>"$LOG" 2>&1; then
    log 'reboot accepted by systemd-logind'
    exit 0
  fi
fi

if [ "$(id -u)" -eq 0 ]; then
  log 'falling back to root systemctl reboot'
  exec /usr/bin/systemctl reboot
fi

if command -v pkexec >/dev/null 2>&1; then
  log 'session-owned reboot paths failed; requesting PolicyKit systemctl reboot'
  exec pkexec /usr/bin/systemctl reboot
fi

log 'ERROR: no usable reboot mechanism is available'
echo "MechOS could not request a reboot. See $LOG" >&2
exit 1
