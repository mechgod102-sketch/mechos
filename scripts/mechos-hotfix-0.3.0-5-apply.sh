#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-5-applied"
LOG=/var/log/mechos-hotfix-0.3.0-5.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 5 apply start"
[ -e "$MARKER" ] && exit 0

is_live(){
  [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null
}
is_live && { echo "Live ISO detected; installed-system Hotfix 5 repair skipped."; exit 0; }

mkdir -p /usr/local/bin /etc/xdg/autostart /usr/share/applications

cat > /usr/local/bin/mechos-vm-mode-runtime <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-boot}"
STATE=/var/lib/mechos
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
MODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mechos"
MODE_FILE="$MODE_DIR/session-mode"
LOG="$STATE_DIR/vm-mode-runtime.log"
APP_LOG="$STATE_DIR/vm-mechscope-launch.log"
mkdir -p "$STATE_DIR" "$MODE_DIR"

log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -z "$virt" ] || [ "$virt" = none ]; then
  log "not a VM; declining VM runtime mode=$MODE"
  exit 3
fi
if [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; then
  log "Live ISO detected; installed VM runtime disabled"
  exit 0
fi

# Account creation remains authoritative. Do not let a VM launcher bypass OOBE.
if [ -e "$STATE/installed" ] && [ ! -e "$STATE/oobe-complete" ]; then
  if [ "$(id -un)" = mechos-setup ] && [ -x /usr/local/bin/mechos-oobe-start ]; then
    log "OOBE incomplete; routing setup account to account creation"
    exec /usr/local/bin/mechos-oobe-start
  fi
  log "OOBE incomplete for user=$(id -un); MechScope launch blocked"
  if command -v kdialog >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    kdialog --title 'MechOS First Setup' --error 'Account creation is still pending. Restart MechOS to enter the protected setup session.' >/dev/null 2>&1 || true
  fi
  exit 20
fi

export MECHOS_VM_MODE=1
export MECHOS_DISABLE_GAMESCOPE=1
export QT_OPENGL=software
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export QSG_RHI_BACKEND=software

import_graphics(){
  if systemctl --user show-environment >/dev/null 2>&1; then
    while IFS='=' read -r key value; do
      case "$key" in
        DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|KDE_FULL_SESSION|KDE_SESSION_VERSION)
          printf -v "$key" '%s' "$value"; export "$key" ;;
      esac
    done < <(systemctl --user show-environment)
    systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
      XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION KDE_SESSION_VERSION \
      MECHOS_VM_MODE MECHOS_DISABLE_GAMESCOPE QT_OPENGL LIBGL_ALWAYS_SOFTWARE \
      QT_QUICK_BACKEND QSG_RHI_BACKEND >/dev/null 2>&1 || true
  fi
}

wait_for_graphics(){
  local i
  for i in $(seq 1 80); do
    import_graphics
    if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then return 0; fi
    sleep 0.25
  done
  log "graphical environment never became ready"
  return 1
}

actual_mechscope(){
  # Tutorial integration may wrap /usr/local/bin/mechscope. VM mode switching
  # must start the real UI backend, while tutorial/OOBE remain independent
  # first-run authorities.
  if [ -x /usr/local/bin/mechscope.real ]; then
    printf '%s\n' /usr/local/bin/mechscope.real
  elif [ -x /usr/local/bin/mechscope ]; then
    printf '%s\n' /usr/local/bin/mechscope
  else
    return 1
  fi
}

python_health_check(){
  local target="$1"
  local first
  first="$(head -n1 "$target" 2>/dev/null || true)"
  case "$first" in
    *python*)
      PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$target" >>"$APP_LOG" 2>&1 || {
        log "MechScope Python health check failed target=$target"
        return 1
      }
      ;;
  esac
}

launch_mechscope(){
  local target pid i
  target="$(actual_mechscope)" || {
    log "MechScope executable missing"
    return 1
  }
  python_health_check "$target" || return 1

  # Stop stale user-service instances from older builds. Hotfix 5 owns the VM
  # launch path directly so a broken service/controller cannot block the UI.
  systemctl --user stop mechos-vm-mechscope.service >/dev/null 2>&1 || true

  if pgrep -u "$(id -u)" -f '(/usr/local/bin/mechscope.real|/usr/local/bin/mechscope)( |$)' >/dev/null 2>&1; then
    log "MechScope already running"
    return 0
  fi

  : >"$APP_LOG"
  log "launching MechScope directly in Plasma VM session target=$target virt=$virt"
  nohup "$target" >>"$APP_LOG" 2>&1 </dev/null &
  pid=$!
  for i in $(seq 1 30); do
    sleep 0.1
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      wait "$pid" >/dev/null 2>&1 || true
      log "MechScope exited during startup; see $APP_LOG"
      return 1
    fi
    if [ "$i" -ge 10 ]; then
      printf '%s\n' "$pid" > "$STATE_DIR/mechscope.pid"
      log "MechScope launch healthy pid=$pid"
      return 0
    fi
  done
  return 0
}

launch_creator(){
  [ -x /usr/local/bin/mechos-creator-mode ] || return 1
  nohup /usr/local/bin/mechos-creator-mode >>"$STATE_DIR/vm-creator-launch.log" 2>&1 </dev/null &
  local pid=$!
  sleep 1
  kill -0 "$pid" >/dev/null 2>&1
}

wait_for_graphics || exit 4

case "$MODE" in
  boot)
    MODE=gaming
    if [ -r "$MODE_FILE" ]; then MODE="$(tr -d '[:space:]' < "$MODE_FILE")"; fi
    case "$MODE" in gaming|creator|desktop) ;; *) MODE=gaming ;; esac
    ;;
  start|mechscope) MODE=gaming ;;
  gaming|creator|desktop|stop) ;;
  *) log "invalid mode=$MODE"; exit 2 ;;
esac

case "$MODE" in
  gaming)
    printf 'gaming\n' > "$MODE_FILE"
    launch_mechscope
    ;;
  creator)
    printf 'creator\n' > "$MODE_FILE"
    pkill -u "$(id -u)" -f '(/usr/local/bin/mechscope.real|/usr/local/bin/mechscope)( |$)' >/dev/null 2>&1 || true
    launch_creator
    ;;
  desktop)
    printf 'desktop\n' > "$MODE_FILE"
    systemctl --user stop mechos-vm-mechscope.service mechos-vm-creator.service >/dev/null 2>&1 || true
    pkill -u "$(id -u)" -f '(/usr/local/bin/mechscope.real|/usr/local/bin/mechscope)( |$)' >/dev/null 2>&1 || true
    ;;
  stop)
    systemctl --user stop mechos-vm-mechscope.service mechos-vm-creator.service >/dev/null 2>&1 || true
    ;;
esac
EOF
chmod 0755 /usr/local/bin/mechos-vm-mode-runtime
bash -n /usr/local/bin/mechos-vm-mode-runtime

cat > /usr/local/bin/mechos-mode-launch <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
MODE="${1:-}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$STATE_DIR/mode-shortcut.log"
mkdir -p "$STATE_DIR"
log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }
notify_error(){
  local msg="$1"; log "ERROR: $msg"
  if command -v kdialog >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    kdialog --title 'MechOS Mode Launcher' --error "$msg\n\nLog: $LOG" >/dev/null 2>&1 || true
  fi
}
case "$MODE" in gaming|mechscope|creator|desktop) ;; *) echo 'Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}' >&2; exit 2 ;; esac

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -n "$virt" ] && [ "$virt" != none ] && [ ! -e /run/archiso/bootmnt ] && ! grep -q archiso /proc/cmdline 2>/dev/null; then
  # MECHOS_HOTFIX5_VM_DIRECT_ROUTER_V1
  # Do not depend on the historical gaming-layer controller in a VM. Some
  # upgraded installations never received its VM router, which is why Hotfix 4
  # still produced 'MechScope could not be started'.
  case "$MODE" in mechscope) MODE=gaming ;; esac
  log "virtualization=$virt; routing mode=$MODE directly to VM runtime"
  if /usr/local/bin/mechos-vm-mode-runtime "$MODE" >>"$LOG" 2>&1; then
    log "VM mode=$MODE launch accepted"
    exit 0
  fi
  notify_error "${MODE^} could not be started in the virtual machine."
  exit 1
fi

CONTROL=/usr/local/bin/mechos-gaming-layer-control
[ -x "$CONTROL" ] || { notify_error 'MechOS mode controller is missing.'; exit 1; }
case "$MODE" in
  gaming|mechscope) "$CONTROL" start >>"$LOG" 2>&1 ;;
  creator) "$CONTROL" creator >>"$LOG" 2>&1 ;;
  desktop) "$CONTROL" desktop >>"$LOG" 2>&1 ;;
esac || { notify_error "${MODE^} could not be started."; exit 1; }
EOF
chmod 0755 /usr/local/bin/mechos-mode-launch
bash -n /usr/local/bin/mechos-mode-launch

cat > /etc/xdg/autostart/mechos-vm-mode-runtime.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS VM Mode Runtime
Comment=Restore the selected MechOS mode after Plasma is ready in a virtual machine
Exec=/usr/local/bin/mechos-vm-mode-runtime boot
TryExec=/usr/local/bin/mechos-vm-mode-runtime
Terminal=false
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF
chmod 0644 /etc/xdg/autostart/mechos-vm-mode-runtime.desktop

cat > /usr/share/applications/mechos-return-gaming.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Return to MechScope
Comment=Open MechScope using the VM-safe MechOS launcher
Exec=/usr/local/bin/mechos-mode-launch gaming
TryExec=/usr/local/bin/mechos-mode-launch
Icon=applications-games
Terminal=false
StartupNotify=true
Categories=Game;System;
EOF
chmod 0644 /usr/share/applications/mechos-return-gaming.desktop

# Refresh existing users' desktop shortcut when it is already present. Do not
# create desktop clutter for users who removed it intentionally.
while IFS=: read -r user _ uid _ _ home _; do
  [ "$uid" -ge 1000 ] 2>/dev/null || continue
  [ "$uid" -lt 60000 ] 2>/dev/null || continue
  [ "$user" != mechos-setup ] || continue
  for f in "$home/Desktop/Return-to-MechScope.desktop" "$home/Desktop/MechScope.desktop"; do
    if [ -e "$f" ]; then
      cp -f /usr/share/applications/mechos-return-gaming.desktop "$f"
      chown "$user:$user" "$f" 2>/dev/null || true
      chmod 0755 "$f"
    fi
  done
done < /etc/passwd

# Keep the installed session entry canonical for future logins. In a VM Plasma
# remains the compositor; the runtime above starts the MechScope app after KDE.
mkdir -p /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/mechscope.desktop <<'EOF'
[Desktop Entry]
Name=MechScope
Comment=MechOS Gaming Mode
Exec=/usr/local/bin/mechscope-session
TryExec=/usr/local/bin/mechscope-session
Type=Application
DesktopNames=MechScope
EOF
chmod 0644 /usr/share/wayland-sessions/mechscope.desktop

# Update release metadata only after every repair above validates.
printf '0.3.0-hotfix.5\n' > /etc/mechos/release
printf '0.3.0-hotfix.5\n' > /etc/system-release
mkdir -p "$STATE"
touch "$MARKER"
echo "[$(date -Is)] Hotfix 5 complete: VM MechScope launcher now bypasses stale gaming-layer routing and directly starts the real MechScope UI in Plasma."