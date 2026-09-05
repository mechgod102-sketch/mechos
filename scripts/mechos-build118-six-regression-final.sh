#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
log(){ printf '[MechOS Build 118 Final] %s\n' "$*"; }
fail(){ printf '[MechOS Build 118 Final] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail "Live rootfs missing"
[ -s "$ARCHIVE" ] || fail "installed payload missing"

# Live issue #1 and installed Creator issue #6 share the same cause: fixed pixel
# padding did not scale with the 1920x1080 geometry. The source-owned UI stage
# must have installed the responsive FixedCanvas before this final authority.
for file in \
  "$ROOT/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$ROOT/usr/local/share/mechos/ui/installer_shell.py"; do
  [ -f "$file" ] || fail "source UI missing: $file"
done
grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V2' "$ROOT/usr/local/share/mechos/ui/fixed_canvas.py" \
  || fail "responsive VM control geometry was not installed into Live rootfs"

STAGE="$(mktemp -d /tmp/mechos-build118-final.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$STAGE"

install_reboot_helper(){
  local tree="$1"
  mkdir -p "$tree/usr/local/bin"
  cat > "$tree/usr/local/bin/mechos-reboot" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if command -v loginctl >/dev/null 2>&1; then
  if loginctl reboot; then exit 0; fi
fi
if command -v pkexec >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  exec pkexec /usr/bin/systemctl reboot
fi
exec /usr/bin/systemctl reboot
EOF
  chmod 0755 "$tree/usr/local/bin/mechos-reboot"
}

install_firstboot_authority(){
  local tree="$1"
  mkdir -p \
    "$tree/usr/local/bin" "$tree/usr/local/libexec" \
    "$tree/usr/lib/systemd/system" "$tree/usr/lib/systemd/user" \
    "$tree/etc/systemd/system/graphical.target.wants" "$tree/etc/systemd/system/sddm.service.d" \
    "$tree/etc/systemd/user/default.target.wants" "$tree/etc/systemd/user/graphical-session.target.wants" \
    "$tree/etc/xdg/autostart" "$tree/etc/sddm.conf.d" "$tree/etc/polkit-1/rules.d"

  cat > "$tree/usr/local/bin/mechos-oobe-start" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/oobe-start.log"
mkdir -p "$(dirname "$LOG")"
[ -e "$STATE/installed" ] || exit 0
[ ! -e "$STATE/oobe-complete" ] || exit 0
[ "$(id -un)" = mechos-setup ] || exit 0
[ -x /usr/local/bin/mechos-oobe ] || exit 1
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
runtime="${XDG_RUNTIME_DIR:-/tmp}"; mkdir -p "$runtime"
exec 9>"$runtime/mechos-oobe.lock"; flock -n 9 || exit 0
exec /usr/local/bin/mechos-oobe >>"$LOG" 2>&1
EOF
  chmod 0755 "$tree/usr/local/bin/mechos-oobe-start"

  cat > "$tree/usr/local/libexec/mechos-firstboot-authority" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
SETUP_USER=mechos-setup
[ -e /run/archiso/bootmnt ] && exit 0
[ -e "$STATE/installed" ] || exit 0
[ ! -e "$STATE/oobe-complete" ] || exit 0

if [ ! -s "$STATE/installer-user" ]; then
  candidate="$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "mechos-setup" && $1 != "nobody" {print $1; exit}' /etc/passwd)"
  [ -z "$candidate" ] || printf '%s\n' "$candidate" > "$STATE/installer-user"
fi
if ! id "$SETUP_USER" >/dev/null 2>&1; then
  groups="$(for g in video audio input storage optical; do getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done | sed 's/,$//')"
  if [ -n "$groups" ]; then useradd -m -s /bin/bash -G "$groups" "$SETUP_USER"; else useradd -m -s /bin/bash "$SETUP_USER"; fi
fi
passwd -d "$SETUP_USER" >/dev/null 2>&1 || true
if getent group wheel >/dev/null 2>&1; then gpasswd -d "$SETUP_USER" wheel >/dev/null 2>&1 || true; fi

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
  chmod 0755 "$tree/usr/local/libexec/mechos-firstboot-authority"

  cat > "$tree/usr/lib/systemd/system/mechos-firstboot-authority.service" <<'EOF'
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
    "$tree/etc/systemd/system/graphical.target.wants/mechos-firstboot-authority.service"
  cat > "$tree/etc/systemd/system/sddm.service.d/20-mechos-oobe-gate.conf" <<'EOF'
[Unit]
Wants=mechos-firstboot-authority.service
After=mechos-firstboot-authority.service
EOF

  cat > "$tree/usr/lib/systemd/user/mechos-oobe-autostart.service" <<'EOF'
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
    "$tree/etc/systemd/user/default.target.wants/mechos-oobe-autostart.service"
  ln -sfn /usr/lib/systemd/user/mechos-oobe-autostart.service \
    "$tree/etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service"

  cat > "$tree/etc/xdg/autostart/mechos-oobe-authority.desktop" <<'EOF'
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
  cat > "$tree/etc/sddm.conf.d/95-mechos-oobe.conf" <<'EOF'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=false
EOF

  cat > "$tree/etc/polkit-1/rules.d/49-mechos-oobe.rules" <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        subject.user == "mechos-setup" &&
        action.lookup("program") == "/usr/local/libexec/mechos-oobe-apply") {
        return polkit.Result.YES;
    }
});
EOF
}

patch_oobe(){
  local tree="$1" apply="$1/usr/local/libexec/mechos-oobe-apply" gui="$1/usr/local/bin/mechos-oobe"
  [ -f "$apply" ] || fail "OOBE apply helper missing in installed payload"
  [ -f "$gui" ] || fail "OOBE GUI missing in installed payload"
  python3 - "$apply" "$gui" <<'PY'
from pathlib import Path
import sys
apply=Path(sys.argv[1]); gui=Path(sys.argv[2])
t=apply.read_text(encoding='utf-8')
t=t.replace('Session=mechos-gaming.desktop','Session=mechscope.desktop')
marker='# MECHOS_BUILD118_OOBE_MODE_V1'
anchor='state = Path("/var/lib/mechos"); state.mkdir(parents=True, exist_ok=True)'
if marker not in t:
    if anchor not in t: raise SystemExit('OOBE state anchor missing')
    block='''# MECHOS_BUILD118_OOBE_MODE_V1\nhome = Path(pwd.getpwnam(username).pw_dir)\nmode_dir = home / ".config" / "mechos"\nmode_dir.mkdir(parents=True, exist_ok=True)\nmode_file = mode_dir / "session-mode"\nmode_file.write_text("gaming\\n")\ntry:\n    uid = pwd.getpwnam(username).pw_uid\n    gid = pwd.getpwnam(username).pw_gid\n    for item in (mode_dir.parent, mode_dir, mode_file): os.chown(item, uid, gid)\nexcept Exception:\n    pass\n\n'''
    t=t.replace(anchor,block+anchor,1)
compile(t,str(apply),'exec'); apply.write_text(t,encoding='utf-8')

g=gui.read_text(encoding='utf-8')
g=g.replace('subprocess.Popen(["systemctl", "reboot"])','subprocess.Popen(["/usr/local/bin/mechos-reboot"])')
compile(g,str(gui),'exec'); gui.write_text(g,encoding='utf-8')
PY
  chmod 0755 "$apply" "$gui"
}

install_tutorial_fallback(){
  local tree="$1"
  mkdir -p "$tree/usr/local/bin" "$tree/etc/xdg/autostart"
  cat > "$tree/usr/local/bin/mechos-first-run-tutorial-start" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/tutorial-v1-complete"
[ -e "$STATE/installed" ] || exit 0
[ -e "$STATE/oobe-complete" ] || exit 0
[ "$(id -un)" != mechos-setup ] || exit 0
[ ! -e "$MARKER" ] || exit 0
[ -x /usr/local/bin/mechos-tutorial ] || exit 0
runtime="${XDG_RUNTIME_DIR:-/tmp}"; mkdir -p "$runtime"
exec 9>"$runtime/mechos-first-run-tutorial.lock"; flock -n 9 || exit 0
exec /usr/local/bin/mechos-tutorial --mode all --first-run
EOF
  chmod 0755 "$tree/usr/local/bin/mechos-first-run-tutorial-start"
  cat > "$tree/etc/xdg/autostart/mechos-first-run-tutorial.desktop" <<'EOF'
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

repair_wrapper(){
  local tree="$1" name="$2" mode="$3" marker_rel="$4"
  local public="$tree/usr/local/bin/$name" real="$tree/usr/local/bin/$name.real"
  [ -x "$real" ] || return 0
  cat > "$public" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_TUTORIAL_WRAPPER_V2
REAL="/usr/local/bin/$name.real"
MARKER="\${XDG_CONFIG_HOME:-\$HOME/.config}/mechos/$marker_rel"
if [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; then exec "\$REAL" "\$@"; fi
if [ -e /var/lib/mechos/installed ] && [ ! -e /var/lib/mechos/oobe-complete ]; then
  if [ "\$(id -un)" = mechos-setup ]; then exec /usr/local/bin/mechos-oobe-start; fi
  exit 20
fi
if [ ! -e "\$MARKER" ] && [ -x /usr/local/bin/mechos-tutorial ]; then
  /usr/local/bin/mechos-tutorial --mode $mode --first-run || true
fi
exec "\$REAL" "\$@"
EOF
  chmod 0755 "$public"
}

patch_mode_launcher(){
  local tree="$1" file="$1/usr/local/bin/mechos-mode-launch"
  [ -f "$file" ] || return 0
  python3 - "$file" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_BUILD118_DIRECT_MECHSCOPE_FALLBACK'
if marker in t: raise SystemExit(0)
old='''    if "$CONTROL" start >>"$LOG" 2>&1; then\n      log "MechScope launch request accepted"\n      exit 0\n    fi\n    notify_error "MechScope could not be started."\n    exit 1\n'''
new='''    if "$CONTROL" start >>"$LOG" 2>&1; then\n      log "MechScope launch request accepted"\n      exit 0\n    fi\n    # MECHOS_BUILD118_DIRECT_MECHSCOPE_FALLBACK\n    if [ -e /var/lib/mechos/oobe-complete ] && [ -x /usr/local/bin/mechscope ]; then\n      nohup /usr/local/bin/mechscope >>"$LOG" 2>&1 &\n      _pid=$!; sleep 0.8\n      if kill -0 "$_pid" >/dev/null 2>&1; then exit 0; fi\n    fi\n    notify_error "MechScope could not be started."\n    exit 1\n'''
if old not in t: raise SystemExit('MechScope launcher fallback anchor missing')
p.write_text(t.replace(old,new,1),encoding='utf-8')
PY
  chmod 0755 "$file"
}

patch_update_reboot(){
  local tree="$1" owner=""
  for c in "$tree/usr/local/bin/mechos-update-center" "$tree/usr/local/bin/mechos-update-center.real" "$tree/usr/local/libexec/mechos-update-center-v5.py"; do
    if [ -f "$c" ] && grep -Fq 'class UpdateCenter(' "$c"; then owner="$c"; break; fi
  done
  [ -n "$owner" ] || fail "Update Center owner missing in installed payload"
  python3 - "$owner" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_BUILD118_REBOOT_V1'
if marker in t: raise SystemExit(0)
cls=t.find('class UpdateCenter('); start=t.find('    def reboot(self):',cls)
if start < 0: raise SystemExit('UpdateCenter.reboot missing')
end=t.find('\n    def ',start+8)
if end < 0: end=t.find('\ndef main():',start)
if end < 0: raise SystemExit('UpdateCenter.reboot end missing')
new='''    def reboot(self):\n        # MECHOS_BUILD118_REBOOT_V1\n        response = QMessageBox.question(self, \"Restart MechOS\", \"Restart now to finish applying system updates?\")\n        if response == QMessageBox.StandardButton.Yes:\n            try: subprocess.Popen([\"/usr/local/bin/mechos-reboot\"])\n            except Exception as exc: QMessageBox.critical(self, \"Restart MechOS\", f\"Restart could not be started: {exc}\")\n'''
t=t[:start]+new+t[end:]; compile(t,str(p),'exec'); p.write_text(t,encoding='utf-8')
PY
  chmod 0755 "$owner"
}

install_reboot_helper "$STAGE"
install_firstboot_authority "$STAGE"
patch_oobe "$STAGE"
install_tutorial_fallback "$STAGE"
repair_wrapper "$STAGE" mechscope all tutorial-v1-complete
repair_wrapper "$STAGE" mechos-creator-mode creator tutorial-creator-v1.done
patch_mode_launcher "$STAGE"
patch_update_reboot "$STAGE"

# Final installed-payload validation before repack.
for f in \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/mechscope_shell.py" \
  "$STAGE/usr/local/bin/mechos-oobe" \
  "$STAGE/usr/local/libexec/mechos-oobe-apply"; do
  [ -f "$f" ] || fail "installed runtime missing: $f"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$f" || fail "Python validation failed: $f"
done
bash -n "$STAGE/usr/local/bin/mechos-reboot" || fail "reboot helper syntax failed"
bash -n "$STAGE/usr/local/bin/mechos-oobe-start" || fail "OOBE launcher syntax failed"
bash -n "$STAGE/usr/local/libexec/mechos-firstboot-authority" || fail "firstboot authority syntax failed"
grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V2' "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" || fail "installed responsive UI missing"
grep -Fq 'Session=mechscope.desktop' "$STAGE/usr/local/libexec/mechos-oobe-apply" || fail "OOBE permanent session is wrong"
grep -Fq 'MECHOS_BUILD118_REBOOT_V1' "$(for c in "$STAGE/usr/local/bin/mechos-update-center" "$STAGE/usr/local/bin/mechos-update-center.real" "$STAGE/usr/local/libexec/mechos-update-center-v5.py"; do [ -f "$c" ] && grep -Fq 'class UpdateCenter(' "$c" && { echo "$c"; break; }; done)" || fail "Update Center reboot repair missing"

TMP="$ARCHIVE.build118-final"
tar --zstd -cpf "$TMP" -C "$STAGE" .
mv -f "$TMP" "$ARCHIVE"
rm -rf "$STAGE"; trap - EXIT

log 'six reported regressions guarded: responsive Live/Creator UI, deterministic OOBE/tutorial, robust reboot and MechScope fallback'
