#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX23_POSTINSTALL_ACCOUNT_REPAIR_V1

STATE=/var/lib/mechos
SETUP_USER=mechos-setup
OOBE=/usr/local/bin/mechos-oobe
APPLY=/usr/local/libexec/mechos-oobe-apply
CLEANUP=/usr/local/libexec/mechos-oobe-cleanup
AUTH=/usr/local/libexec/mechos-firstboot-authority
FIRSTBOOT_UPDATE=/usr/local/libexec/mechos-firstboot-update-apply
POLKIT=/etc/polkit-1/rules.d/49-mechos-firstboot.rules
SDDM=/etc/sddm.conf.d
MARKER="$STATE/hotfix-0.3.0-23-applied"

log(){ printf '[MechOS Hotfix 23] %s\n' "$*"; }
fail(){ printf '[MechOS Hotfix 23] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Hotfix 23] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker is absent; nothing to repair'; exit 0; }
mkdir -p "$STATE" "$SDDM" "$(dirname "$POLKIT")"

remove_setup_sddm_fragments(){
  local cfg
  shopt -s nullglob
  for cfg in "$SDDM"/*.conf; do
    if grep -Fq "$SETUP_USER" "$cfg" 2>/dev/null; then
      rm -f "$cfg"
    fi
  done
  shopt -u nullglob
}

write_final_sddm(){
  remove_setup_sddm_fragments
  cat >"$SDDM/99-mechos-final-user.conf" <<'EOF'
[Autologin]
User=
Session=mechos-gaming.desktop
Relogin=false
EOF
}

install_firstboot_policy(){
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
}

patch_runtime(){
  [ -x "$OOBE" ] || fail "missing $OOBE"
  [ -x "$APPLY" ] || fail "missing $APPLY"
  [ -x "$CLEANUP" ] || fail "missing $CLEANUP"

  python3 - "$OOBE" "$APPLY" "$CLEANUP" "$AUTH" <<'PY'
from pathlib import Path
import sys

oobe=Path(sys.argv[1]); apply=Path(sys.argv[2]); cleanup=Path(sys.argv[3]); auth=Path(sys.argv[4])

# UI: fullscreen OOBE only; privileged helper owns the reboot.
t=oobe.read_text(encoding='utf-8')
t=t.replace('        subprocess.Popen(["systemctl", "reboot"])', '        # Reboot is scheduled by the privileged OOBE apply helper.')
t=t.replace('w = OOBE(); w.showMaximized(); return app.exec()', 'w = OOBE(); w.showFullScreen(); return app.exec()')
oobe.write_text(t, encoding='utf-8')

# Permanent-account handoff: clean SDDM, enable cleanup, then schedule a root reboot.
t=apply.read_text(encoding='utf-8')
marker='# MECHOS_POSTINSTALL_ACCOUNT_FINISH_V2'
if marker not in t:
    anchor='subprocess.run(["systemctl", "enable", "mechos-oobe-cleanup.service"], check=False)\nprint("MechOS first system setup complete.")'
    if anchor not in t:
        raise SystemExit('OOBE completion anchor missing')
    replacement='''# MECHOS_POSTINSTALL_ACCOUNT_FINISH_V2
for cfg in sddm.glob("*.conf"):
    try:
        if "mechos-setup" in cfg.read_text(errors="ignore"):
            cfg.unlink()
    except OSError:
        pass
(sddm / "99-mechos-final-user.conf").write_text(
    "[Autologin]\\n"
    "User=\\n"
    "Session=mechos-gaming.desktop\\n"
    "Relogin=false\\n"
)
subprocess.run(["systemctl", "enable", "mechos-oobe-cleanup.service"], check=False)
subprocess.run([
    "systemd-run", "--unit=mechos-oobe-finish-reboot", "--on-active=3s",
    "--collect", "/usr/bin/systemctl", "reboot"
], check=True)
print("MechOS first system setup complete; reboot scheduled.")'''
    t=t.replace(anchor,replacement,1)
apply.write_text(t, encoding='utf-8')

# Next-boot cleanup is authoritative and runs before SDDM.
t=cleanup.read_text(encoding='utf-8')
marker='# MECHOS_POSTINSTALL_ACCOUNT_CLEANUP_V2'
if marker not in t:
    anchor='rm -rf /home/mechos-setup\nmkdir -p /var/lib/mechos\ntouch /var/lib/mechos/oobe-cleaned'
    if anchor not in t:
        raise SystemExit('OOBE cleanup anchor missing')
    replacement='''rm -rf /home/mechos-setup
# MECHOS_POSTINSTALL_ACCOUNT_CLEANUP_V2
mkdir -p /etc/sddm.conf.d /var/lib/mechos
for cfg in /etc/sddm.conf.d/*.conf; do
  [ -f "$cfg" ] || continue
  if grep -Fq 'mechos-setup' "$cfg"; then rm -f "$cfg"; fi
done
cat > /etc/sddm.conf.d/99-mechos-final-user.conf <<'SDDMFINAL'
[Autologin]
User=
Session=mechos-gaming.desktop
Relogin=false
SDDMFINAL
rm -f /etc/systemd/user/default.target.wants/mechos-oobe-autostart.service
rm -f /etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service
touch /var/lib/mechos/oobe-cleaned'''
    t=t.replace(anchor,replacement,1)
cleanup.write_text(t, encoding='utf-8')

# Firstboot authority must create an unlocked, non-admin temporary transport user.
if auth.is_file():
    t=auth.read_text(encoding='utf-8')
    t=t.replace('passwd -l "$SETUP_USER" >/dev/null 2>&1 || true', 'passwd -d "$SETUP_USER" >/dev/null 2>&1 || true')
    t=t.replace('Relogin=true', 'Relogin=false')
    marker='# MECHOS_POSTINSTALL_ACCOUNT_AUTHORITY_V2'
    needle='passwd -d "$SETUP_USER" >/dev/null 2>&1 || true\n'
    if marker not in t and needle in t:
        t=t.replace(needle, needle+marker+'\nif getent group wheel >/dev/null 2>&1; then\n  gpasswd -d "$SETUP_USER" wheel >/dev/null 2>&1 || true\nfi\n',1)
    auth.write_text(t, encoding='utf-8')
PY

  chmod 0755 "$OOBE" "$APPLY" "$CLEANUP"
  python3 -m py_compile "$OOBE" "$APPLY"
  bash -n "$CLEANUP"
  if [ -f "$AUTH" ]; then chmod 0755 "$AUTH"; bash -n "$AUTH"; fi

  grep -Fq 'showFullScreen()' "$OOBE" || fail 'OOBE fullscreen repair missing'
  ! grep -Fq 'subprocess.Popen(["systemctl", "reboot"])' "$OOBE" || fail 'unprivileged OOBE reboot remains'
  grep -Fq 'mechos-oobe-finish-reboot' "$APPLY" || fail 'privileged OOBE reboot handoff missing'
  grep -Fq '99-mechos-final-user.conf' "$APPLY" || fail 'final SDDM handoff missing'
  grep -Fq 'MECHOS_POSTINSTALL_ACCOUNT_CLEANUP_V2' "$CLEANUP" || fail 'cleanup repair missing'
}

install_oobe_autostart(){
  mkdir -p /usr/lib/systemd/user /etc/systemd/user/default.target.wants /etc/systemd/user/graphical-session.target.wants
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
  ln -sfn /usr/lib/systemd/user/mechos-oobe-autostart.service /etc/systemd/user/default.target.wants/mechos-oobe-autostart.service
  ln -sfn /usr/lib/systemd/user/mechos-oobe-autostart.service /etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service
}

if [ -f "$STATE/oobe-complete" ]; then
  log 'OOBE is already complete; removing any leftover transport-account state'
  if id "$SETUP_USER" >/dev/null 2>&1; then
    userdel -r "$SETUP_USER" >/dev/null 2>&1 || userdel "$SETUP_USER" >/dev/null 2>&1 || true
  fi
  rm -rf /home/mechos-setup
  rm -f /etc/systemd/user/default.target.wants/mechos-oobe-autostart.service
  rm -f /etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service
  write_final_sddm
  install_firstboot_policy
  touch "$STATE/oobe-cleaned" "$MARKER"
  exit 0
fi

log 'repairing incomplete firstboot account-creation flow'
patch_runtime

if ! id "$SETUP_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$SETUP_USER"
fi
passwd -d "$SETUP_USER" >/dev/null 2>&1 || true
if getent group wheel >/dev/null 2>&1; then
  gpasswd -d "$SETUP_USER" wheel >/dev/null 2>&1 || true
fi

install_oobe_autostart
install_firstboot_policy

# Remove stale setup-user SDDM fragments, then create exactly one temporary
# autologin route. Relogin=false prevents a loop if OOBE terminates unexpectedly.
remove_setup_sddm_fragments
rm -f "$SDDM/99-mechos-final-user.conf"
cat >"$SDDM/98-mechos-oobe.conf" <<'EOF'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=false
EOF

touch "$MARKER"
log 'Hotfix 23 account repair staged; next login will be fullscreen account creation'
