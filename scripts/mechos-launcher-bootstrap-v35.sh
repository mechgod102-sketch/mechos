#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_LAUNCHER_BOOTSTRAP_V35

LAUNCHER="${1:-}"
BASE="/usr/local/libexec/mechos-provider-bootstrap-v15"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/store"
LOG="$STATE_DIR/launcher-bootstrap-v35.log"
mkdir -p "$STATE_DIR"
exec >>"$LOG" 2>&1
log(){ printf '[%s] [launcher-bootstrap-v35] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }

case "$LAUNCHER" in
  steam)
    [ -x "$BASE" ] || { log 'ERROR: provider bootstrap v15 missing'; exit 20; }
    exec "$BASE" steam
    ;;
  heroic)
    [ -x "$BASE" ] || { log 'ERROR: provider bootstrap v15 missing'; exit 30; }
    exec "$BASE" heroic
    ;;
  lutris)
    if command -v lutris >/dev/null 2>&1; then
      log 'Lutris already installed.'
      exit 0
    fi
    command -v pacman >/dev/null 2>&1 || { log 'ERROR: pacman unavailable'; exit 40; }
    command -v pkexec >/dev/null 2>&1 || { log 'ERROR: pkexec unavailable'; exit 41; }
    log 'Lutris missing; requesting fixed system package installation.'
    pkexec /usr/bin/pacman -S --needed --noconfirm lutris
    command -v lutris >/dev/null 2>&1 || { log 'ERROR: Lutris installation completed but executable is still missing'; exit 42; }
    log 'Lutris installation complete.'
    ;;
  *)
    echo 'Usage: mechos-launcher-bootstrap-v35 {steam|heroic|lutris}' >&2
    exit 2
    ;;
esac
