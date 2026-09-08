#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_OOBE_REARM_V25
# Persistent pre-display-manager guard. It is enabled permanently but systemd
# runs it only while the installed system lacks /var/lib/mechos/oobe-complete.

STATE=/var/lib/mechos
SETUP_USER=mechos-setup
SDDM=/etc/sddm.conf.d
POLKIT=/etc/polkit-1/rules.d/49-mechos-firstboot.rules
OOBE_START=/usr/local/bin/mechos-oobe-start
OOBE=/usr/local/bin/mechos-oobe
APPLY=/usr/local/libexec/mechos-oobe-apply

log(){ printf '[MechOS OOBE rearm v25] %s\n' "$*"; }
fail(){ printf '[MechOS OOBE rearm v25] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || exit 0
[ ! -e /run/archiso/bootmnt ] || exit 0
[ ! -f "$STATE/oobe-complete" ] || exit 0

[ -x "$OOBE_START" ] || fail "missing $OOBE_START"
[ -x "$OOBE" ] || fail "missing $OOBE"
[ -x "$APPLY" ] || fail "missing $APPLY"

mkdir -p \
  "$STATE" "$SDDM" "$(dirname "$POLKIT")" \
  /usr/lib/systemd/user \
  /etc/systemd/user/default.target.wants \
  /etc/systemd/user/graphical-session.target.wants

if ! id "$SETUP_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$SETUP_USER"
fi
passwd -d "$SETUP_USER" >/dev/null 2>&1 || true
if getent group wheel >/dev/null 2>&1; then
  gpasswd -d "$SETUP_USER" wheel >/dev/null 2>&1 || true
fi

cat >/usr/lib/systemd/user/mechos-oobe-autostart.service <<'EOF'
[Unit]
Description=Launch MechOS post-install account creation
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

cat >"$POLKIT" <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        subject.user == "mechos-setup" &&
        (action.lookup("program") == "/usr/local/libexec/mechos-oobe-apply" ||
         action.lookup("program") == "/usr/local/libexec/mechos-firstboot-update-apply")) {
        return polkit.Result.YES;
    }
});
EOF
chmod 0644 "$POLKIT"

# Remove every stale setup-user fragment first, then recreate one authoritative
# temporary autologin route. This runs again on every boot until OOBE completes.
shopt -s nullglob
for cfg in "$SDDM"/*.conf; do
  if grep -Fq "$SETUP_USER" "$cfg" 2>/dev/null; then
    rm -f "$cfg"
  fi
done
shopt -u nullglob
rm -f "$SDDM/99-mechos-final-user.conf"

cat >"$SDDM/98-mechos-oobe.conf" <<'EOF'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=false
EOF
chmod 0644 "$SDDM/98-mechos-oobe.conf"

log 'incomplete OOBE re-armed; fullscreen account creation will launch in the temporary setup session'
