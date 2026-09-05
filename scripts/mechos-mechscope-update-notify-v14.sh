#!/usr/bin/env bash
set -u
# MECHOS_MECHSCOPE_UPDATE_NOTIFY_V14
HELPER=/usr/local/bin/mechos-update-helper
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/mechos-$UID}"
MARKER="$RUNTIME_DIR/mechos-mechscope-update-check-v14.done"
LOG="$STATE_DIR/mechscope-update-check.log"
mkdir -p "$STATE_DIR" "$RUNTIME_DIR" 2>/dev/null || exit 0
[ -e "$MARKER" ] && exit 0
: >"$MARKER"
exec >>"$LOG" 2>&1
printf '[%s] MechScope boot update check started\n' "$(date -Is 2>/dev/null || date)"
[ -x "$HELPER" ] || { echo 'update helper missing'; exit 0; }

# Give NetworkManager a short opportunity to finish bringing the gaming session online.
for _ in 1 2 3 4 5; do
  if command -v nm-online >/dev/null 2>&1 && nm-online -q -x -t 1 >/dev/null 2>&1; then break; fi
  sleep 2
done

OUT="$(timeout 75 "$HELPER" check 2>&1)" || {
  printf '%s\n' "$OUT"
  echo 'update check unavailable; no user notification emitted'
  exit 0
}
printf '%s\n' "$OUT"
value(){ printf '%s\n' "$OUT" | awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}'; }
current="$(value CURRENT_MECHOS_VERSION)"
latest="$(value LATEST_MECHOS_VERSION)"
mechos="$(value MECHOS_UPDATE_AVAILABLE)"
total="$(value TOTAL_COUNT)"
[ -n "$total" ] || total="$(value UPDATE_COUNT)"
arch="$(value ARCH_COUNT)"; [ -n "$arch" ] || arch="$(value PACMAN_COUNT)"
flat="$(value FLATPAK_COUNT)"
case "$total" in ''|*[!0-9]*) total=0;; esac
available=0
[ "$mechos" = 1 ] && available=1
[ -n "$latest" ] && [ -n "$current" ] && [ "$latest" != "$current" ] && available=1
[ "$total" -gt 0 ] 2>/dev/null && available=1
[ "$available" -eq 1 ] || { echo 'system reports no available updates'; exit 0; }

summary="MechOS updates are available"
detail="Open Update Center to review and install them."
if [ -n "$latest" ] && [ "$latest" != "$current" ]; then detail="MechOS $latest is available. Open Update Center to review it."; fi
if [ "$total" -gt 0 ] 2>/dev/null; then detail="$total update(s) are available across MechOS, Arch and Flatpak sources."; fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send -a 'MechOS Update Center' -u normal -i system-software-update "$summary" "$detail" >/dev/null 2>&1 || true
elif command -v kdialog >/dev/null 2>&1; then
  kdialog --title 'MechOS Update Center' --passivepopup "$summary\n$detail" 12 >/dev/null 2>&1 || true
fi
printf '[%s] notification emitted: current=%s latest=%s total=%s arch=%s flatpak=%s\n' "$(date -Is 2>/dev/null || date)" "$current" "$latest" "$total" "$arch" "$flat"
exit 0
