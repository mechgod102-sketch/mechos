#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_PROVIDER_BOOTSTRAP_V15
PROVIDER="${1:-}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/store"
LOG="$STATE_DIR/provider-bootstrap-v15.log"
mkdir -p "$STATE_DIR"
exec >>"$LOG" 2>&1

log(){ printf '[%s] [provider-bootstrap-v15] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }

case "$PROVIDER" in
  steam)
    if command -v steam >/dev/null 2>&1; then
      log 'Steam already installed.'
      exit 0
    fi
    command -v pacman >/dev/null 2>&1 || { log 'ERROR: pacman unavailable'; exit 20; }
    command -v pkexec >/dev/null 2>&1 || { log 'ERROR: pkexec unavailable'; exit 21; }
    log 'Steam missing; requesting system installation through pacman.'
    pkexec /usr/bin/pacman -S --needed --noconfirm steam
    command -v steam >/dev/null 2>&1 || { log 'ERROR: Steam install completed but executable is still missing'; exit 22; }
    log 'Steam installation complete.'
    ;;

  heroic)
    command -v flatpak >/dev/null 2>&1 || { log 'ERROR: flatpak unavailable'; exit 30; }
    if flatpak info com.heroicgameslauncher.hgl >/dev/null 2>&1; then
      log 'Heroic already installed.'
      exit 0
    fi
    log 'Heroic missing; ensuring user Flathub remote.'
    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    log 'Installing Heroic Games Launcher as a user Flatpak.'
    flatpak install --user -y flathub com.heroicgameslauncher.hgl
    flatpak info com.heroicgameslauncher.hgl >/dev/null 2>&1 || { log 'ERROR: Heroic install verification failed'; exit 31; }
    log 'Heroic installation complete.'
    ;;

  *)
    echo 'Usage: mechos-provider-bootstrap-v15 {steam|heroic}' >&2
    exit 2
    ;;
esac
