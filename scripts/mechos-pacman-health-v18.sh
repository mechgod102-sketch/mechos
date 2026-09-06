#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_PACMAN_HEALTH_V18

LOG=/var/log/mechos-update.log
log(){ printf '[%s] [pacman-health-v18] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG" 2>/dev/null || true; }

[ "$(id -u)" -eq 0 ] || { echo 'Administrator privileges required.' >&2; exit 77; }
command -v install >/dev/null 2>&1 || { echo 'Base command missing: install' >&2; exit 71; }
command -v find >/dev/null 2>&1 || { echo 'Base command missing: find' >&2; exit 71; }

# pacman 7 downloads repository databases through its restricted download user.
# Keep the parent paths traversable and remove stale interrupted download dirs so
# pacman can create a fresh sandbox directory on the next synchronization.
install -d -m0755 -o root -g root /var/lib/pacman
install -d -m0755 -o root -g root /var/lib/pacman/sync
install -d -m0755 -o root -g root /var/cache/pacman
install -d -m0755 -o root -g root /var/cache/pacman/pkg
find /var/lib/pacman/sync -mindepth 1 -maxdepth 1 -type d -name 'download-*' -exec rm -rf -- {} + 2>/dev/null || true

if [ -f /etc/pacman.conf ] && grep -Eq '^[[:space:]]*DownloadUser[[:space:]]*=[[:space:]]*alpm([[:space:]]|$)' /etc/pacman.conf; then
  getent passwd alpm >/dev/null 2>&1 || {
    log 'ERROR: pacman DownloadUser=alpm is configured but the alpm system user is missing'
    echo 'Pacman download sandbox user alpm is missing.' >&2
    exit 72
  }
  # Preserve owner write bits while guaranteeing directory traversal/readability
  # required by the restricted download process.
  chmod a+rx /etc /var /var/lib /var/lib/pacman /var/lib/pacman/sync /var/cache /var/cache/pacman /var/cache/pacman/pkg
fi

log 'pacman download paths verified and stale download sandboxes cleared'
exit 0
