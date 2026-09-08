#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MECHSCOPE_USER_CLEANUP_V33

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/mechscope-user-cleanup-v33.log"
MARKER="$STATE_DIR/mechscope-user-cleanup-v33-complete"
mkdir -p "$STATE_DIR"
log(){ printf '[%s] [mechscope-user-cleanup-v33] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }
[ -e "$MARKER" ] && exit 0

# Disable per-user XDG launchers copied from older hotfixes. The canonical
# hardware owner is /usr/local/bin/mechscope-session via SDDM, not a user
# autostart. Keep unrelated Creator/Update/desktop autostarts untouched.
USER_AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
if [ -d "$USER_AUTOSTART" ]; then
  while IFS= read -r -d '' file; do
    if grep -Eq '(^|[ =/])(mechscope|mechos-mechscope-safe-launch-v31|mechos-session-autostart-v(24|31))([ ."/]|$)' "$file" 2>/dev/null; then
      if ! grep -Fq 'Hidden=true' "$file"; then
        printf '\n# MECHOS_HF33_DISABLED_LEGACY_MECHSCOPE_AUTOSTART\nHidden=true\n' >>"$file"
      fi
      log "disabled user XDG MechScope autostart: $file"
    fi
  done < <(find "$USER_AUTOSTART" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)
fi

# Stop/disable user services that directly execute the historical MechScope
# launchers. Do not disable generic KDE services just because their logs mention
# MechScope.
USER_UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
if [ -d "$USER_UNITS" ]; then
  while IFS= read -r -d '' unitfile; do
    if grep -Eq '^Exec(Start|StartPre)=.*(mechscope|mechos-mechscope-safe-launch-v31|mechos-session-autostart-v(24|31))' "$unitfile" 2>/dev/null; then
      unit="$(basename "$unitfile")"
      systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
      log "disabled user MechScope unit: $unit"
    fi
  done < <(find "$USER_UNITS" -maxdepth 1 -type f \( -name '*.service' -o -name '*.timer' \) -print0 2>/dev/null)
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true
touch "$MARKER"
log 'legacy per-user MechScope launch cleanup complete'
exit 0
