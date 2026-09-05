#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-4-applied"
LOG=/var/log/mechos-hotfix-0.3.0-4.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 4 apply start"
[ -e "$MARKER" ] && exit 0

is_live(){
  [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null
}
is_live && { echo "Live ISO detected; installed-system Hotfix 4 repair skipped."; exit 0; }

install_reboot_helper(){
  cat > /usr/local/bin/mechos-reboot <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

# Prefer logind for an active local graphical session. If policy requires
# authentication, fall back to an explicit PolicyKit systemctl request instead
# of silently doing nothing like the old detached Update Center call.
if command -v loginctl >/dev/null 2>&1; then
  if loginctl reboot; then
    exit 0
  fi
fi

if command -v pkexec >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  exec pkexec /usr/bin/systemctl reboot
fi
exec /usr/bin/systemctl reboot
EOF
  chmod 0755 /usr/local/bin/mechos-reboot
  bash -n /usr/local/bin/mechos-reboot
}

strip_competing_sddm_autologin(){
  mkdir -p /etc/sddm.conf.d
  python3 - <<'PY'
from pathlib import Path
root=Path('/etc/sddm.conf.d')
keep='95-mechos-oobe.conf'
for p in root.glob('*.conf'):
    if p.name == keep or not p.is_file():
        continue
    lines=p.read_text(encoding='utf-8',errors='ignore').splitlines(True)
    out=[]; skip=False
    for line in lines:
        stripped=line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            skip=(stripped.lower() == '[autologin]')
            if not skip:
                out.append(line)
            continue
        if not skip:
            out.append(line)
    p.write_text(''.join(out),encoding='utf-8')
PY
}

write_oobe_runtime_authority(){
  [ -e "$STATE/installed" ] || { echo "Installed marker absent; OOBE authority repair not needed."; return 0; }
  [ ! -e "$STATE/oobe-complete" ] || { echo "OOBE already complete; preserving permanent account handoff."; return 0; }

  echo "OOBE incomplete; forcing deterministic mechos-setup first-boot authority."

  # If an older broken first boot already exposed a normal user, remember that
  # account so OOBE can configure/rename it rather than failing on an existing
  # username when the owner selects the same name again.
  if [ ! -s "$STATE/installer-user" ]; then
    candidate="$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "mechos-setup" && $1 != "nobody" {print $1; exit}' /etc/passwd)"
    [ -z "$candidate" ] || printf '%s\n' "$candidate" > "$STATE/installer-user"
  fi

  if ! id mechos-setup >/dev/null 2>&1; then
    groups="$(for g in video audio input storage optical; do getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done | sed 's/,$//')"
    if [ -n "$groups" ]; then
      useradd -m -s /bin/bash -G "$groups" mechos-setup
    else
      useradd -m -s /bin/bash mechos-setup
    fi
  fi
  passwd -d mechos-setup >/dev/null 2>&1 || true
  if getent group wheel >/dev/null 2>&1; then
    gpasswd -d mechos-setup wheel >/dev/null 2>&1 || true
  fi

  mkdir -p \
    /usr/local/bin /usr/local/libexec \
    /usr/lib/systemd/system /usr/lib/systemd/user \
    /etc/systemd/system/graphical.target.wants /etc/systemd/system/sddm.service.d \
    /etc/systemd/user/default.target.wants /etc/systemd/user/graphical-session.target.wants \
    /etc/polkit-1/rules.d /etc/xdg/autostart /etc/sddm.conf.d

  cat > /etc/polkit-1/rules.d/49-mechos-oobe.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        subject.user == "mechos-setup" &&
        action.lookup("program") == "/usr/local/libexec/mechos-oobe-apply") {
        return polkit.Result.YES;
    }
});
EOF
  chmod 0644 /etc/polkit-1/rules.d/49-mechos-oobe.rules

  cat > /usr/local/bin/mechos-oobe-start <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/oobe-start.log"
mkdir -p "$(dirname "$LOG")"
[ -e "$STATE/installed" ] || exit 0
[ ! -e "$STATE/oobe-complete" ] || exit 0
[ "$(id -un)" = mechos-setup ] || exit 0
[ -x /usr/local/bin/mechos-oobe ] || { echo "MechOS OOBE executable missing" >>"$LOG"; exit 1; }

for _ in $(seq 1 120); do
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

runtime="${XDG_RUNTIME_DIR:-/tmp}"
mkdir -p "$runtime"
exec 9>"$runtime/mechos-oobe.lock"
flock -n 9 || exit 0
printf '[%s] launching account creation user=%s wayland=%s display=%s\n' \
  "$(date -Is 2>/dev/null || date)" "$(id -un)" "${WAYLAND_DISPLAY:-}" "${DISPLAY:-}" >>"$LOG"
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
  cat > "$setup_home/.config/ksplashrc" <<'EOF'
[KSplash]
Engine=none
Theme=None
EOF
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

if ! id "$SETUP_USER" >/dev/null 2>&1; then
  groups="$(for g in video audio input storage optical; do getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done | sed 's/,$//')"
  if [ -n "$groups" ]; then useradd -m -s /bin/bash -G "$groups" "$SETUP_USER"; else useradd -m -s /bin/bash "$SETUP_USER"; fi
fi
passwd -d "$SETUP_USER" >/dev/null 2>&1 || true
if getent group wheel >/dev/null 2>&1; then gpasswd -d "$SETUP_USER" wheel >/dev/null 2>&1 || true; fi

# Remove only competing Autologin sections. Other SDDM settings survive.
python3 - <<'PY'
from pathlib import Path
root=Path('/etc/sddm.conf.d'); root.mkdir(parents=True,exist_ok=True)
for p in root.glob('*.conf'):
    if p.name == '95-mechos-oobe.conf' or not p.is_file(): continue
    lines=p.read_text(encoding='utf-8',errors='ignore').splitlines(True)
    out=[]; skip=False
    for line in lines:
        s=line.strip()
        if s.startswith('[') and s.endswith(']'):
            skip=(s.lower() == '[autologin]')
            if not skip: out.append(line)
            continue
        if not skip: out.append(line)
    p.write_text(''.join(out),encoding='utf-8')
PY

home="$(getent passwd "$SETUP_USER" | cut -d: -f6)"; [ -n "$home" ] || home="/home/$SETUP_USER"
mkdir -p "$home/.config/autostart" /etc/sddm.conf.d
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

  cat > /etc/systemd/system/sddm.service.d/20-mechos-oobe-gate.conf <<'EOF'
[Unit]
Wants=mechos-firstboot-authority.service
After=mechos-firstboot-authority.service
EOF

  strip_competing_sddm_autologin
  cat > /etc/sddm.conf.d/95-mechos-oobe.conf <<'EOF'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=false
EOF
  printf 'pending\n' > "$STATE/oobe-pending"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable mechos-firstboot-authority.service >/dev/null 2>&1 || true
  /usr/local/libexec/mechos-firstboot-authority || true
}

install_tutorial_autostart(){
  cat > /usr/local/bin/mechos-first-run-tutorial-start <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/tutorial-v1-complete"
[ -e "$STATE/installed" ] || exit 0
[ -e "$STATE/oobe-complete" ] || exit 0
[ "$(id -un)" != mechos-setup ] || exit 0
[ ! -e "$MARKER" ] || exit 0
[ -x /usr/local/bin/mechos-tutorial ] || exit 0

for _ in $(seq 1 100); do
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && break
  sleep 0.2
done
runtime="${XDG_RUNTIME_DIR:-/tmp}"; mkdir -p "$runtime"
exec 9>"$runtime/mechos-first-run-tutorial.lock"
flock -n 9 || exit 0
exec /usr/local/bin/mechos-tutorial --mode all --first-run
EOF
  chmod 0755 /usr/local/bin/mechos-first-run-tutorial-start

  cat > /etc/xdg/autostart/mechos-first-run-tutorial.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS First-Run Tutorial
Exec=/usr/local/bin/mechos-first-run-tutorial-start
TryExec=/usr/local/bin/mechos-first-run-tutorial-start
Terminal=false
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF
}

repair_tutorial_wrapper(){
  local name="$1" mode="$2" marker_rel="$3"
  local public="/usr/local/bin/$name" real="/usr/local/bin/$name.real"
  [ -x "$real" ] || { echo "No $real; leaving $public unchanged."; return 0; }
  cat > "$public" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_TUTORIAL_WRAPPER_V2
REAL="$real"
MARKER="\${XDG_CONFIG_HOME:-\$HOME/.config}/mechos/$marker_rel"

if [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; then
  exec "\$REAL" "\$@"
fi
if [ -e /var/lib/mechos/installed ] && [ ! -e /var/lib/mechos/oobe-complete ]; then
  if [ "\$(id -un)" = mechos-setup ]; then
    exec /usr/local/bin/mechos-oobe-start
  fi
  if command -v kdialog >/dev/null 2>&1 && [ -n "\${DISPLAY:-}\${WAYLAND_DISPLAY:-}" ]; then
    kdialog --title 'MechOS First Setup' --error 'Account creation is still pending. Restart MechOS to enter the protected setup session.' >/dev/null 2>&1 || true
  fi
  exit 20
fi
if [ ! -e "\$MARKER" ] && [ -x /usr/local/bin/mechos-tutorial ]; then
  /usr/local/bin/mechos-tutorial --mode $mode --first-run || true
fi
exec "\$REAL" "\$@"
EOF
  chmod 0755 "$public"
  bash -n "$public"
}

patch_mode_launcher_fallback(){
  local launch=/usr/local/bin/mechos-mode-launch
  [ -f "$launch" ] || return 0
  python3 - "$launch" <<'PY'
from pathlib import Path
p=Path('/usr/local/bin/mechos-mode-launch')
t=p.read_text(encoding='utf-8')
marker='# MECHOS_HOTFIX4_DIRECT_MECHSCOPE_FALLBACK'
if marker in t:
    raise SystemExit(0)
old='''    if "$CONTROL" start >>"$LOG" 2>&1; then\n      log "MechScope launch request accepted"\n      exit 0\n    fi\n    notify_error "MechScope could not be started."\n    exit 1\n'''
new='''    if "$CONTROL" start >>"$LOG" 2>&1; then\n      log "MechScope launch request accepted"\n      exit 0\n    fi\n    # MECHOS_HOTFIX4_DIRECT_MECHSCOPE_FALLBACK\n    # If the VM user service fails, keep Plasma as compositor and start the\n    # guarded MechScope wrapper directly instead of leaving a dead shortcut.\n    if [ -e /var/lib/mechos/oobe-complete ] && [ -x /usr/local/bin/mechscope ]; then\n      nohup /usr/local/bin/mechscope >>"$LOG" 2>&1 &\n      _pid=$!\n      sleep 0.8\n      if kill -0 "$_pid" >/dev/null 2>&1; then\n        log "MechScope direct Plasma fallback active pid=$_pid"\n        exit 0\n      fi\n    fi\n    notify_error "MechScope could not be started."\n    exit 1\n'''
if old not in t:
    raise SystemExit('[Hotfix 4] MechScope launcher fallback anchor missing')
p.write_text(t.replace(old,new,1),encoding='utf-8')
PY
  chmod 0755 "$launch"
  bash -n "$launch"
}

patch_update_center_reboot(){
  local owner=""
  for candidate in \
    /usr/local/bin/mechos-update-center \
    /usr/local/bin/mechos-update-center.real \
    /usr/local/libexec/mechos-update-center-v5.py; do
    if [ -f "$candidate" ] && grep -Fq 'class UpdateCenter(' "$candidate"; then owner="$candidate"; break; fi
  done
  [ -n "$owner" ] || { echo "Update Center owner not found; reboot helper still installed."; return 0; }

  python3 - "$owner" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_HOTFIX4_REBOOT_V1'
if marker in t: raise SystemExit(0)
cls=t.find('class UpdateCenter(')
start=t.find('    def reboot(self):',cls)
if start < 0: raise SystemExit('[Hotfix 4] UpdateCenter.reboot missing')
end=t.find('\n    def ',start+8)
if end < 0:
    end=t.find('\ndef main():',start)
if end < 0: raise SystemExit('[Hotfix 4] UpdateCenter.reboot end missing')
new='''    def reboot(self):\n        # MECHOS_HOTFIX4_REBOOT_V1\n        response = QMessageBox.question(\n            self, \"Restart MechOS\",\n            \"Restart now to finish applying system updates?\"\n        )\n        if response == QMessageBox.StandardButton.Yes:\n            try:\n                subprocess.Popen([\"/usr/local/bin/mechos-reboot\"])\n            except Exception as exc:\n                QMessageBox.critical(self, \"Restart MechOS\", f\"Restart could not be started: {exc}\")\n'''
t=t[:start]+new+t[end:]
compile(t,str(p),'exec')
p.write_text(t,encoding='utf-8')
PY
  chmod 0755 "$owner"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$owner"
}

runtime_python_audit(){
  local f
  for f in \
    /usr/local/bin/mechos-oobe \
    /usr/local/libexec/mechos-oobe-apply \
    /usr/local/share/mechos/ui/fixed_canvas.py \
    /usr/local/share/mechos/ui/creator_shell.py \
    /usr/local/share/mechos/ui/mechscope_shell.py; do
    [ -f "$f" ] || continue
    PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$f"
  done
  for f in /usr/local/bin/mechscope.real /usr/local/bin/mechos-creator-mode.real; do
    [ -f "$f" ] || continue
    if ! PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$f"; then
      echo "WARNING: existing generated runtime failed Python audit: $f"
      printf '%s\n' "$f" >> "$STATE/hotfix-0.3.0-4-python-audit-failures"
    fi
  done
}

install_reboot_helper
write_oobe_runtime_authority
install_tutorial_autostart
repair_tutorial_wrapper mechscope all tutorial-v1-complete
repair_tutorial_wrapper mechos-creator-mode creator tutorial-creator-v1.done
patch_mode_launcher_fallback
patch_update_center_reboot
runtime_python_audit

mkdir -p /etc/mechos
printf '0.3.0-hotfix.4\n' > /etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.4/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.4\n' >> /etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 4\n' > /etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix 4 applied. Reboot required."
