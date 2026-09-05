#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-3-applied"
LOG=/var/log/mechos-hotfix-0.3.0-3.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 3 apply start"
[ -e "$MARKER" ] && exit 0

is_live(){
  [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null
}
is_live && { echo "Live ISO detected; Hotfix 3 installed-system repair skipped."; exit 0; }

write_no_kde_splash(){
  local cfg="$1"
  mkdir -p "$(dirname "$cfg")"
  cat > "$cfg" <<'EOF'
[KSplash]
Engine=none
Theme=None
EOF
}

# Keep the branded MechOS Plymouth boot screen, but remove Plasma's second KDE
# session splash so the first visible desktop UI can be MechOS account creation.
write_no_kde_splash /etc/xdg/ksplashrc
write_no_kde_splash /etc/skel/.config/ksplashrc

while IFS=: read -r user _ uid _ _ home _; do
  [ "$uid" -ge 1000 ] 2>/dev/null || continue
  [ "$uid" -lt 60000 ] 2>/dev/null || continue
  [ "$user" != nobody ] || continue
  [ -d "$home" ] || continue
  write_no_kde_splash "$home/.config/ksplashrc"
  chown "$user:$(id -gn "$user" 2>/dev/null || echo "$user")" "$home/.config/ksplashrc" 2>/dev/null || true
done < /etc/passwd

repair_firstboot(){
  [ -e "$STATE/installed" ] || { echo "Installed marker is absent; firstboot repair not required."; return 0; }
  [ ! -e "$STATE/oobe-complete" ] || { echo "Account creation is already complete."; return 0; }

  echo "OOBE incomplete; repairing automatic first-run account creation."

  command -v useradd >/dev/null 2>&1 || { echo "ERROR: useradd is unavailable."; return 1; }
  [ -x /usr/local/bin/mechos-oobe ] || { echo "ERROR: MechOS OOBE UI is missing from the update payload."; return 1; }
  [ -x /usr/local/libexec/mechos-oobe-apply ] || { echo "ERROR: MechOS OOBE apply helper is missing."; return 1; }

  mkdir -p \
    /usr/local/bin \
    /usr/local/libexec \
    /usr/lib/systemd/system \
    /usr/lib/systemd/user \
    /etc/systemd/system/graphical.target.wants \
    /etc/systemd/user/default.target.wants \
    /etc/systemd/user/graphical-session.target.wants \
    /etc/polkit-1/rules.d \
    /etc/sddm.conf.d \
    /etc/xdg/autostart

  if ! id mechos-setup >/dev/null 2>&1; then
    setup_groups="$(for g in video audio input storage optical; do getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done | sed 's/,$//')"
    if [ -n "$setup_groups" ]; then
      useradd -m -s /bin/bash -G "$setup_groups" mechos-setup
    else
      useradd -m -s /bin/bash mechos-setup
    fi
  fi

  # SDDM autologin needs an unlocked temporary account. It is deliberately not
  # an administrator; the one privileged OOBE helper is authorized by polkit.
  passwd -d mechos-setup >/dev/null 2>&1 || true
  if getent group wheel >/dev/null 2>&1; then
    gpasswd -d mechos-setup wheel >/dev/null 2>&1 || true
  fi

  cat > /etc/polkit-1/rules.d/49-mechos-oobe.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        subject.user == "mechos-setup" &&
        action.lookup("program") == "/usr/local/libexec/mechos-oobe-apply") {
        return polkit.Result.YES;
    }
});
EOF

  cat > /usr/local/bin/mechos-oobe-start <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/oobe-start.log"
mkdir -p "$(dirname "$LOG")"
[ -e "$STATE/installed" ] || exit 0
[ ! -e "$STATE/oobe-complete" ] || exit 0
[ "$(id -un)" = mechos-setup ] || exit 0
[ -x /usr/local/bin/mechos-oobe ] || exit 1

# Import the real Plasma display/session environment when systemd --user starts
# before KDE's XDG autostart has populated the shell environment.
for _ in $(seq 1 100); do
  if systemctl --user show-environment >/dev/null 2>&1; then
    while IFS='=' read -r key value; do
      case "$key" in
        DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|KDE_FULL_SESSION|KDE_SESSION_VERSION)
          printf -v "$key" '%s' "$value"; export "$key" ;;
      esac
    done < <(systemctl --user show-environment)
  fi
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && break
  sleep 0.2
done

printf '[%s] launching MechOS account creation wayland=%s display=%s\n' \
  "$(date -Is 2>/dev/null || date)" "${WAYLAND_DISPLAY:-}" "${DISPLAY:-}" >>"$LOG"
exec /usr/local/bin/mechos-oobe >>"$LOG" 2>&1
EOF
  chmod 0755 /usr/local/bin/mechos-oobe-start

  setup_home="$(getent passwd mechos-setup | cut -d: -f6)"
  [ -n "$setup_home" ] || setup_home=/home/mechos-setup
  mkdir -p "$setup_home/.config/autostart"
  cat > "$setup_home/.config/autostart/mechos-oobe.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup
Exec=/usr/local/bin/mechos-oobe-start
TryExec=/usr/local/bin/mechos-oobe-start
Terminal=false
X-KDE-autostart-after=panel
EOF
  write_no_kde_splash "$setup_home/.config/ksplashrc"
  chown -R mechos-setup:mechos-setup "$setup_home/.config"

  cat > /etc/xdg/autostart/mechos-oobe-authority.desktop <<'EOF'
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

  cat > /usr/lib/systemd/user/mechos-oobe-autostart.service <<'EOF'
[Unit]
Description=Launch MechOS account creation on first installed login
ConditionUser=mechos-setup
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/oobe-complete
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mechos-oobe-start
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target graphical-session.target
EOF
  ln -sfn /usr/lib/systemd/user/mechos-oobe-autostart.service \
    /etc/systemd/user/default.target.wants/mechos-oobe-autostart.service
  ln -sfn /usr/lib/systemd/user/mechos-oobe-autostart.service \
    /etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service

  cat > /usr/local/libexec/mechos-firstboot-authority <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
SETUP_USER=mechos-setup
[ -e /run/archiso/bootmnt ] && exit 0
[ -e "$STATE/installed" ] || exit 0
[ ! -e "$STATE/oobe-complete" ] || exit 0

mkdir -p "$STATE" /etc/sddm.conf.d
if ! id "$SETUP_USER" >/dev/null 2>&1; then
  groups="$(for g in video audio input storage optical; do getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done | sed 's/,$//')"
  if [ -n "$groups" ]; then useradd -m -s /bin/bash -G "$groups" "$SETUP_USER"; else useradd -m -s /bin/bash "$SETUP_USER"; fi
fi
passwd -d "$SETUP_USER" >/dev/null 2>&1 || true
if getent group wheel >/dev/null 2>&1; then gpasswd -d "$SETUP_USER" wheel >/dev/null 2>&1 || true; fi

home="$(getent passwd "$SETUP_USER" | cut -d: -f6)"; [ -n "$home" ] || home="/home/$SETUP_USER"
mkdir -p "$home/.config/autostart"
cat > "$home/.config/autostart/mechos-oobe.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup
Exec=/usr/local/bin/mechos-oobe-start
TryExec=/usr/local/bin/mechos-oobe-start
Terminal=false
X-KDE-autostart-after=panel
DESKTOP
cat > "$home/.config/ksplashrc" <<'KSPLASH'
[KSplash]
Engine=none
Theme=None
KSPLASH
chown -R "$SETUP_USER:$SETUP_USER" "$home/.config"

cat > /etc/sddm.conf.d/95-mechos-oobe.conf <<'SDDM'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=false
SDDM
printf 'pending\n' > "$STATE/oobe-pending"
printf 'desktop\n' > "$STATE/firstboot-session"
EOF
  chmod 0755 /usr/local/libexec/mechos-firstboot-authority

  cat > /usr/lib/systemd/system/mechos-firstboot-authority.service <<'EOF'
[Unit]
Description=Prepare MechOS first-run account creation before SDDM
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/oobe-complete

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-firstboot-authority

[Install]
WantedBy=graphical.target
EOF
  ln -sfn /usr/lib/systemd/system/mechos-firstboot-authority.service \
    /etc/systemd/system/graphical.target.wants/mechos-firstboot-authority.service

  cat > /etc/sddm.conf.d/95-mechos-oobe.conf <<'EOF'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=false
EOF
  printf 'pending\n' > "$STATE/oobe-pending"

  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable mechos-firstboot-authority.service >/dev/null 2>&1 || true
}

repair_firstboot

mkdir -p /etc/mechos
printf '0.3.0-hotfix.3\n' > /etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.3/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.3\n' >> /etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 3\n' > /etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix 3 applied. Reboot required."
