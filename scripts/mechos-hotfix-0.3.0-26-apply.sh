#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX26_OOBE_LAUNCHER_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-26-applied"
START=/usr/local/bin/mechos-oobe-start
SETUP_USER=mechos-setup

log(){ printf '[MechOS Hotfix 26] %s\n' "$*"; }
fail(){ printf '[MechOS Hotfix 26] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Hotfix 26] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to repair'; exit 0; }
[ -x "$START" ] || fail 'Hotfix 26 OOBE launcher missing'
grep -Fq 'MECHOS_OOBE_START_V26' "$START" || fail 'Hotfix 26 launcher marker missing'

mkdir -p /usr/share/applications /etc/xdg/autostart /usr/lib/systemd/user

cat >/usr/share/applications/mechos-oobe.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup
Comment=Create the permanent MechOS user account and finish first boot
Exec=/usr/local/bin/mechos-oobe-start
TryExec=/usr/local/bin/mechos-oobe-start
Icon=system-users
Terminal=false
StartupNotify=true
Categories=System;Settings;
EOF
chmod 0644 /usr/share/applications/mechos-oobe.desktop

cat >/etc/xdg/autostart/mechos-oobe-authority.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup Authority
Exec=/usr/local/bin/mechos-oobe-start
TryExec=/usr/local/bin/mechos-oobe-start
Terminal=false
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF
chmod 0644 /etc/xdg/autostart/mechos-oobe-authority.desktop

cat >/usr/lib/systemd/user/mechos-oobe-autostart.service <<'EOF'
[Unit]
Description=Launch MechOS post-install account creation
ConditionUser=mechos-setup
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/oobe-complete
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mechos-oobe-start
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target graphical-session.target
EOF

mkdir -p /etc/systemd/user/default.target.wants /etc/systemd/user/graphical-session.target.wants
ln -sfn /usr/lib/systemd/user/mechos-oobe-autostart.service /etc/systemd/user/default.target.wants/mechos-oobe-autostart.service
ln -sfn /usr/lib/systemd/user/mechos-oobe-autostart.service /etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service

if id "$SETUP_USER" >/dev/null 2>&1 && [ ! -f "$STATE/oobe-complete" ]; then
  home="$(getent passwd "$SETUP_USER" | cut -d: -f6)"
  [ -n "$home" ] || home="/home/$SETUP_USER"
  mkdir -p "$home/.config/autostart"
  cat >"$home/.config/autostart/mechos-oobe.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup
Exec=/usr/local/bin/mechos-oobe-start
TryExec=/usr/local/bin/mechos-oobe-start
Terminal=false
StartupNotify=true
X-KDE-autostart-after=panel
EOF
  chown -R "$SETUP_USER:$SETUP_USER" "$home/.config/autostart"
fi

systemctl daemon-reload || true

bash -n "$START"
grep -Fq 'systemctl --user show-environment' "$START" || fail 'graphical environment recovery missing'
grep -Fq 'QT_QPA_PLATFORM=wayland' "$START" || fail 'Wayland launch path missing'
grep -Fq 'QT_QPA_PLATFORM=xcb' "$START" || fail 'X11 fallback missing'
grep -Fq 'Exec=/usr/local/bin/mechos-oobe-start' /usr/share/applications/mechos-oobe.desktop || fail 'First System Setup menu entry not routed through repaired launcher'

touch "$MARKER"
log 'Hotfix 26 applied: First System Setup now restores the active graphical environment, retries across Wayland/X11, and reports visible launch failures.'
