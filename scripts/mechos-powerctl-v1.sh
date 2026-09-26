#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_POWERCTL_V1_FROZEN
# Stable MechOS power authority. Normal OS hotfixes must never replace this file.

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$LOG_DIR/powerctl-v1.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

log(){
  printf '[%s] [powerctl-v1] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG" 2>/dev/null || true
}

run_timeout(){
  if command -v timeout >/dev/null 2>&1; then
    timeout 8s "$@"
  else
    "$@"
  fi
}

selftest(){
  local found=0
  for cmd in qdbus6 qdbus busctl systemctl pkexec; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf 'POWERCTL_%s=1\n' "$(printf '%s' "$cmd" | tr '[:lower:]-' '[:upper:]_')"
      found=1
    fi
  done
  if [[ "$found" -ne 1 ]]; then
    echo 'No supported reboot authority is available.' >&2
    return 1
  fi
  printf 'MECHOS_POWERCTL_SELFTEST=1\n'
  return 0
}

kde_reboot(){
  local q
  for q in qdbus6 qdbus; do
    command -v "$q" >/dev/null 2>&1 || continue
    if run_timeout "$q" org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot >>"$LOG" 2>&1; then
      log "reboot accepted by KDE Plasma shutdown service via $q"
      return 0
    fi
  done
  return 1
}

logind_reboot(){
  command -v busctl >/dev/null 2>&1 || return 1
  if run_timeout busctl call org.freedesktop.login1 /org/freedesktop/login1       org.freedesktop.login1.Manager Reboot b true >>"$LOG" 2>&1; then
    log 'reboot accepted by systemd-logind'
    return 0
  fi
  return 1
}

system_reboot(){
  if [[ "$(id -u)" -eq 0 ]]; then
    log 'rebooting with root systemctl'
    exec /usr/bin/systemctl reboot
  fi
  if command -v pkexec >/dev/null 2>&1; then
    log 'requesting PolicyKit systemctl reboot'
    exec pkexec /usr/bin/systemctl reboot
  fi
  return 1
}

kde_poweroff(){
  local q
  for q in qdbus6 qdbus; do
    command -v "$q" >/dev/null 2>&1 || continue
    if run_timeout "$q" org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndShutdown >>"$LOG" 2>&1; then
      log "poweroff accepted by KDE Plasma shutdown service via $q"
      return 0
    fi
  done
  return 1
}

logind_poweroff(){
  command -v busctl >/dev/null 2>&1 || return 1
  if run_timeout busctl call org.freedesktop.login1 /org/freedesktop/login1       org.freedesktop.login1.Manager PowerOff b true >>"$LOG" 2>&1; then
    log 'poweroff accepted by systemd-logind'
    return 0
  fi
  return 1
}

system_poweroff(){
  if [[ "$(id -u)" -eq 0 ]]; then
    log 'powering off with root systemctl'
    exec /usr/bin/systemctl poweroff
  fi
  if command -v pkexec >/dev/null 2>&1; then
    log 'requesting PolicyKit systemctl poweroff'
    exec pkexec /usr/bin/systemctl poweroff
  fi
  return 1
}

power_menu(){
  local q
  for q in qdbus6 qdbus; do
    command -v "$q" >/dev/null 2>&1 || continue
    if run_timeout "$q" org.kde.LogoutPrompt /LogoutPrompt promptAll >>"$LOG" 2>&1; then
      log "power menu opened through KDE via $q"
      return 0
    fi
  done
  echo 'KDE power menu is unavailable.' >&2
  return 1
}

case "${1:-selftest}" in
  selftest)
    selftest
    ;;
  reboot|restart)
    log 'reboot requested'
    kde_reboot || logind_reboot || system_reboot || {
      log 'ERROR: no reboot mechanism succeeded'
      echo "MechOS could not restart. See $LOG" >&2
      exit 1
    }
    ;;
  poweroff|shutdown)
    log 'poweroff requested'
    kde_poweroff || logind_poweroff || system_poweroff || {
      log 'ERROR: no poweroff mechanism succeeded'
      echo "MechOS could not shut down. See $LOG" >&2
      exit 1
    }
    ;;
  menu)
    power_menu
    ;;
  *)
    echo 'Usage: mechos-powerctl-v1 {selftest|reboot|restart|poweroff|shutdown|menu}' >&2
    exit 2
    ;;
esac
