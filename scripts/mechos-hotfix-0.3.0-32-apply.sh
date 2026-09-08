#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX32_SINGLE_MECHSCOPE_OWNER_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-32-applied"
LOG=/var/log/mechos-hotfix-0.3.0-32.log
SESSION=/usr/local/bin/mechscope-session
SAFE=/usr/local/libexec/mechos-mechscope-safe-launch-v31
AUTOSTART_SOURCE=/usr/local/libexec/mechos-session-autostart-v31
AUTOSTART=/usr/local/bin/mechos-session-autostart-v24
AUTOSTART_DESKTOP=/etc/xdg/autostart/mechos-session-autostart-v24.desktop

mkdir -p "$STATE" /var/log /etc/xdg/autostart
exec >>"$LOG" 2>&1
log(){ printf '[%s] [MechOS Hotfix 32] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }
fail(){ log "ERROR: $*"; exit 1; }
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to repair'; exit 0; }
is_live && { log 'Live ISO detected; installed-system apply skipped'; exit 0; }
[ ! -e "$MARKER" ] || { log 'Hotfix 32 already applied'; exit 0; }

for f in "$SESSION" "$SAFE" "$AUTOSTART_SOURCE"; do
  [ -f "$f" ] || fail "required runtime missing: $f"
done
bash -n "$SESSION" "$SAFE" "$AUTOSTART_SOURCE"
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V22_SINGLE_OWNER' "$SESSION" || fail 'single-owner hardware session V22 missing'
grep -Fq '/usr/bin/flock -n "$LOCK_FILE"' "$SESSION" || fail 'hardware session lock missing'
grep -Fq 'MECHOS_MECHSCOPE_SINGLE_OWNER_V32' "$SAFE" || fail 'safe-launch single-owner lock missing'
grep -Fq 'duplicate launch suppressed' "$SAFE" || fail 'safe-launch duplicate suppression missing'
grep -Fq 'MECHOS_SESSION_SINGLE_OWNER_V32' "$AUTOSTART_SOURCE" || fail 'KDE single-owner fallback missing'
grep -Fq 'MECHOS_SESSION_SUPERVISED' "$AUTOSTART_SOURCE" || fail 'KDE supervised-session skip missing'

# Keep exactly one supported KDE fallback. It is only a recovery route for a
# plain Plasma login and now exits when the canonical hardware supervisor owns
# Gaming Mode.
install -m0755 "$AUTOSTART_SOURCE" "$AUTOSTART"
cat >"$AUTOSTART_DESKTOP" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Session Autostart
Comment=Recovery-only MechScope startup when a plain KDE session is entered
Exec=/usr/local/bin/mechos-session-autostart-v24
TryExec=/usr/local/bin/mechos-session-autostart-v24
Terminal=false
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF
chmod 0644 "$AUTOSTART_DESKTOP"

# Disable historical system-wide MechScope autostarts that directly spawn the
# app or another MechScope fallback. Leave unrelated KDE autostarts untouched.
while IFS= read -r -d '' f; do
  [ "$f" = "$AUTOSTART_DESKTOP" ] && continue
  if grep -Eq '^Exec=.*(mechscope|mechos-session-autostart|mechos-mechscope-safe-launch)' "$f" 2>/dev/null; then
    mv -f "$f" "$f.disabled-hf32"
    log "disabled duplicate graphical autostart: $f"
  fi
done < <(find /etc/xdg/autostart -maxdepth 1 -type f -name '*.desktop' -print0)

# Reassert canonical MechScope session ownership.
install -d -m0755 /usr/share/wayland-sessions
cat >/usr/share/wayland-sessions/mechscope.desktop <<'EOF'
[Desktop Entry]
Name=MechScope
Comment=MechOS Gamescope + Steam Gaming Mode
Exec=/usr/local/bin/mechscope-session
TryExec=/usr/local/bin/mechscope-session
Type=Application
DesktopNames=MechScope
EOF
chmod 0644 /usr/share/wayland-sessions/mechscope.desktop

install -d -m0755 /etc/mechos
printf '0.3.0-hotfix.32\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.32/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.32\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 32\n' >/etc/system-release

touch "$MARKER"
log 'Hotfix 32 applied: physical hardware now has one MechScope supervisor, KDE duplicate launch is suppressed, and all launch paths share the owner lock.'
