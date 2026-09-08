#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX24_MECHSCOPE_AUTOLAUNCH_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-24-applied"
SDDM=/etc/sddm.conf.d
SESSION=/usr/share/wayland-sessions/mechscope.desktop
VM_RUNTIME=/usr/local/bin/mechos-vm-mode-runtime
AUTOSTART=/usr/local/bin/mechos-session-autostart-v24
AUTOSTART_DESKTOP=/etc/xdg/autostart/mechos-session-autostart-v24.desktop

log(){ printf '[MechOS Hotfix 24] %s\n' "$*"; }
fail(){ printf '[MechOS Hotfix 24] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Hotfix 24] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to repair'; exit 0; }
mkdir -p "$STATE" "$SDDM" "$(dirname "$SESSION")" "$(dirname "$AUTOSTART_DESKTOP")"

# Hotfix 23 wrote a historical/nonexistent session name. Reassert the real
# installed MechScope Wayland session so SDDM starts the OS shell after login.
cat >"$SESSION" <<'EOF'
[Desktop Entry]
Name=MechScope
Comment=MechOS Gaming Mode
Exec=/usr/local/bin/mechscope-session
TryExec=/usr/local/bin/mechscope-session
Type=Application
DesktopNames=MechScope
EOF
chmod 0644 "$SESSION"

fix_session_name(){
  local f
  shopt -s nullglob
  for f in "$SDDM"/*.conf; do
    sed -i 's/^Session=mechos-gaming\.desktop$/Session=mechscope.desktop/' "$f"
  done
  shopt -u nullglob

  # Keep normal sign-in, but make the selected session the actual MechScope
  # entry. This also repairs systems that already completed OOBE on Hotfix 23.
  cat >"$SDDM/99-mechos-final-user.conf" <<'EOF'
[Autologin]
User=
Session=mechscope.desktop
Relogin=false
EOF
}

patch_oobe_future_handoff(){
  local f
  for f in /usr/local/libexec/mechos-oobe-apply /usr/local/libexec/mechos-oobe-cleanup; do
    [ -f "$f" ] || continue
    sed -i 's/Session=mechos-gaming\.desktop/Session=mechscope.desktop/g' "$f"
    chmod 0755 "$f"
  done
  if [ -f /usr/local/libexec/mechos-oobe-apply ]; then
    python3 -m py_compile /usr/local/libexec/mechos-oobe-apply
  fi
  if [ -f /usr/local/libexec/mechos-oobe-cleanup ]; then
    bash -n /usr/local/libexec/mechos-oobe-cleanup
  fi
}

# VMware/QEMU/VirtualBox keep Plasma as compositor. The previous VM runtime
# launched MechScope through a systemd --user service; on affected VMware
# sessions that service exits rc=1 even though the graphical session is alive.
# V24 launches the app from the graphical-session process environment directly
# and retries through X11 if the Wayland Qt path exits immediately.
cat >"$VM_RUNTIME" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VM_MODE_RUNTIME_V24

MODE="${1:-boot}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
MODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mechos"
MODE_FILE="$MODE_DIR/session-mode"
LOG="$STATE_DIR/vm-mode-runtime.log"
mkdir -p "$STATE_DIR" "$MODE_DIR"
log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }

is_live(){ [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; }
virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -z "$virt" ] || [ "$virt" = none ]; then
  log "not a VM; declined mode=$MODE"
  exit 3
fi
is_live && exit 0

restore_graphics_env(){
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  while IFS= read -r line; do
    case "$line" in
      DISPLAY=*|WAYLAND_DISPLAY=*|DBUS_SESSION_BUS_ADDRESS=*|XDG_SESSION_TYPE=*|XDG_CURRENT_DESKTOP=*)
        export "$line"
        ;;
    esac
  done < <(systemctl --user show-environment 2>/dev/null || true)
}

wait_for_graphics(){
  local i
  restore_graphics_env
  for i in $(seq 1 60); do
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then return 0; fi
    if [ -n "${DISPLAY:-}" ]; then return 0; fi
    sleep 0.25
    restore_graphics_env
  done
  log "graphics unavailable wayland=${WAYLAND_DISPLAY:-} display=${DISPLAY:-} runtime=${XDG_RUNTIME_DIR:-}"
  return 1
}

write_mode(){ printf '%s\n' "$1" >"$MODE_FILE"; }
app_running(){ pgrep -u "$(id -u)" -f "$1" >/dev/null 2>&1; }

launch_mechscope(){
  app_running '(^|[[:space:]])(/usr/bin/python3[[:space:]]+)?/usr/local/bin/mechscope(\.real)?([[:space:]]|$)' && {
    log 'MechScope already running'; return 0;
  }
  [ -x /usr/local/bin/mechscope ] || { log 'MechScope executable missing'; return 1; }

  export MECHOS_VM_MODE=1 MECHOS_DISABLE_GAMESCOPE=1
  export QT_OPENGL=software LIBGL_ALWAYS_SOFTWARE=1
  wait_for_graphics || return 1
  systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE XDG_CURRENT_DESKTOP MECHOS_VM_MODE MECHOS_DISABLE_GAMESCOPE QT_OPENGL LIBGL_ALWAYS_SOFTWARE >/dev/null 2>&1 || true

  local pid i rc
  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    log "launching MechScope direct on Wayland virtualization=$virt"
    nohup env QT_QPA_PLATFORM=wayland /usr/local/bin/mechscope >>"$LOG" 2>&1 </dev/null &
    pid=$!
    for i in $(seq 1 15); do
      kill -0 "$pid" 2>/dev/null && { sleep 0.1; continue; }
      wait "$pid" 2>/dev/null || rc=$?
      log "Wayland MechScope exited early rc=${rc:-1}"
      pid=
      break
    done
    [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null && { log 'MechScope active on Wayland'; return 0; }
  fi

  if [ -n "${DISPLAY:-}" ]; then
    log "retrying MechScope direct through X11 display=$DISPLAY"
    nohup env QT_QPA_PLATFORM=xcb /usr/local/bin/mechscope >>"$LOG" 2>&1 </dev/null &
    pid=$!
    sleep 1.5
    kill -0 "$pid" 2>/dev/null && { log 'MechScope active through X11 fallback'; return 0; }
    wait "$pid" 2>/dev/null || rc=$?
    log "X11 MechScope exited rc=${rc:-1}"
  fi
  return 1
}

launch_creator(){
  [ -x /usr/local/bin/mechos-creator-mode ] || return 1
  app_running '/usr/local/bin/mechos-creator-mode' && return 0
  wait_for_graphics || return 1
  nohup /usr/local/bin/mechos-creator-mode >>"$LOG" 2>&1 </dev/null &
  sleep 1
  kill -0 "$!" 2>/dev/null
}

if [ "$MODE" = boot ]; then
  MODE=gaming
  [ -r "$MODE_FILE" ] && MODE="$(tr -d '[:space:]' <"$MODE_FILE")"
  case "$MODE" in gaming|creator|desktop) ;; *) MODE=gaming ;; esac
  log "graphical autostart virtualization=$virt remembered_mode=$MODE"
fi

case "$MODE" in
  start|gaming|mechscope)
    write_mode gaming
    launch_mechscope || { log 'ERROR: gaming could not be started in the virtual machine (direct runtime rc=1).'; exit 1; }
    ;;
  creator)
    write_mode creator
    launch_creator || { log 'Creator Mode could not be started in the virtual machine'; exit 1; }
    ;;
  desktop)
    write_mode desktop
    pkill -u "$(id -u)" -f '/usr/local/bin/mechscope' >/dev/null 2>&1 || true
    ;;
  stop)
    pkill -u "$(id -u)" -f '/usr/local/bin/mechscope' >/dev/null 2>&1 || true
    pkill -u "$(id -u)" -f '/usr/local/bin/mechos-creator-mode' >/dev/null 2>&1 || true
    ;;
  *) exit 2 ;;
esac
EOF
chmod 0755 "$VM_RUNTIME"
bash -n "$VM_RUNTIME"

# A KDE graphical-session fallback makes MechScope self-healing if SDDM lands
# in Plasma because of an old saved session. It intentionally does nothing in
# Desktop Mode, Live ISO, mechos-setup, or before OOBE is complete.
cat >"$AUTOSTART" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_SESSION_AUTOSTART_V24
[ "$(id -un)" != mechos-setup ] || exit 0
[ -f /var/lib/mechos/installed ] || exit 0
[ -f /var/lib/mechos/oobe-complete ] || exit 0
[ ! -e /run/archiso/bootmnt ] || exit 0
MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/session-mode"
MODE=gaming
[ -r "$MODE_FILE" ] && MODE="$(tr -d '[:space:]' <"$MODE_FILE")"
[ "$MODE" != desktop ] || exit 0
virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -n "$virt" ] && [ "$virt" != none ]; then
  exec /usr/local/bin/mechos-vm-mode-runtime gaming
fi
pgrep -u "$(id -u)" -f '(^|[[:space:]])(/usr/bin/python3[[:space:]]+)?/usr/local/bin/mechscope(\.real)?([[:space:]]|$)' >/dev/null 2>&1 && exit 0
[ -x /usr/local/bin/mechscope ] || exit 0
nohup /usr/local/bin/mechscope >>"${XDG_STATE_HOME:-$HOME/.local/state}/mechos/mechscope-autostart.log" 2>&1 </dev/null &
exit 0
EOF
chmod 0755 "$AUTOSTART"
bash -n "$AUTOSTART"

cat >"$AUTOSTART_DESKTOP" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Session Autostart
Comment=Ensure MechScope starts after the graphical desktop is ready
Exec=/usr/local/bin/mechos-session-autostart-v24
TryExec=/usr/local/bin/mechos-session-autostart-v24
Terminal=false
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF
chmod 0644 "$AUTOSTART_DESKTOP"

fix_session_name
patch_oobe_future_handoff

# Regression guards for the two field failures that triggered Hotfix 24.
grep -Fq 'Exec=/usr/local/bin/mechscope-session' "$SESSION" || fail 'canonical MechScope session entry missing'
grep -Fq 'Session=mechscope.desktop' "$SDDM/99-mechos-final-user.conf" || fail 'SDDM still does not select MechScope'
! grep -Rq '^Session=mechos-gaming\.desktop$' "$SDDM" 2>/dev/null || fail 'obsolete MechScope session name remains in SDDM'
grep -Fq 'MECHOS_VM_MODE_RUNTIME_V24' "$VM_RUNTIME" || fail 'VM runtime V24 missing'
grep -Fq 'QT_QPA_PLATFORM=wayland' "$VM_RUNTIME" || fail 'VM Wayland direct launch missing'
grep -Fq 'QT_QPA_PLATFORM=xcb' "$VM_RUNTIME" || fail 'VM X11 fallback missing'
grep -Fq 'MECHOS_SESSION_AUTOSTART_V24' "$AUTOSTART" || fail 'MechScope graphical autostart fallback missing'

touch "$MARKER"
log 'Hotfix 24 applied: SDDM now selects mechscope.desktop; MechScope autolaunch is restored; VMware uses the direct graphical runtime with X11 fallback.'
