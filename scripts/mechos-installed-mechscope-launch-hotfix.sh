#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log(){ printf '[MechOS Installed MechScope Launch] %s\n' "$*"; }
fail(){ printf '[MechOS Installed MechScope Launch] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Installed MechScope Launch] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -d "$ROOT" ] || fail "ArchISO rootfs missing"
[ -s "$ARCHIVE" ] || fail "installed-system payload missing"

install_session_wrapper(){
  local tree="$1"
  local target="$tree/usr/local/bin/mechscope-session"
  mkdir -p "$(dirname "$target")"
  cat > "$target" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
source /usr/local/lib/mechos/runtime.sh

MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/session-mode"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG_FILE="$STATE_DIR/mechscope-session.log"
mkdir -p "$(dirname "$MODE_FILE")" "$STATE_DIR"

if [[ -r "$MODE_FILE" ]]; then
  MODE="$(cat "$MODE_FILE")"
elif mechos_is_live; then
  MODE=desktop
else
  MODE=gaming
fi

start_plasma_mechscope(){
  export MECHOS_DISABLE_GAMESCOPE=1
  export XDG_SESSION_TYPE=wayland
  export XDG_CURRENT_DESKTOP=KDE
  export XDG_SESSION_DESKTOP=KDE
  export DESKTOP_SESSION=plasma

  # Virtual GPUs and unsupported Gamescope paths keep the same MechScope UI,
  # but Plasma supplies the compositor. The app itself switches Qt to software
  # rendering when systemd-detect-virt reports a VM.
  (
    sleep 3
    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE XDG_CURRENT_DESKTOP >/dev/null 2>&1 || true
    /usr/local/bin/mechscope >>"$LOG_FILE" 2>&1 || true
  ) &
  exec /usr/bin/startplasma-wayland
}

if [[ "$MODE" == "desktop" ]]; then
  exec /usr/bin/startplasma-wayland
fi

if [[ ! -x /usr/local/bin/mechscope ]]; then
  printf '[MechOS] MechScope executable missing; falling back to Plasma.\n' >>"$LOG_FILE"
  exec /usr/bin/startplasma-wayland
fi

VIRT="$(systemd-detect-virt 2>/dev/null || true)"
if [[ -n "$VIRT" && "$VIRT" != "none" ]]; then
  export MECHOS_VM_MODE=1
  export QT_OPENGL=software
  export LIBGL_ALWAYS_SOFTWARE=1
  export QT_QUICK_BACKEND=software
  export QSG_RHI_BACKEND=software
  printf '[MechOS] virtualization=%s; bypassing Gamescope and starting MechScope through Plasma.\n' "$VIRT" >>"$LOG_FILE"
  start_plasma_mechscope
fi

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=gamescope
export STEAM_ALLOW_DRIVE_UNMOUNT=1
export STEAM_GAMESCOPE_VRR_SUPPORTED=1
export STEAM_GAMESCOPE_TEARING_SUPPORTED=1
export STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT=1
export STEAM_GAMESCOPE_COLOR_MANAGED=1
export STEAM_MULTIPLE_XWAYLANDS=1
export STEAM_DISABLE_AUDIO_DEVICE_SWITCHING=1
export STEAM_UPDATEUI_PNG_BACKGROUND=/usr/share/backgrounds/mechos/mechscope-loading.png

if [[ "${MECHOS_HDR:-0}" == "1" ]]; then
  export STEAM_GAMESCOPE_HDR_SUPPORTED=1
  export STEAM_GAMESCOPE_VIRTUAL_WHITE=1
fi

if lspci 2>/dev/null | grep -qi nvidia; then
  export GBM_BACKEND=nvidia-drm
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi

if [[ ! -x /usr/bin/gamescope ]]; then
  printf '[MechOS] Gamescope missing; using Plasma compositor fallback for MechScope.\n' >>"$LOG_FILE"
  start_plasma_mechscope
fi

GS_ARGS=(-e -f)
[[ "${MECHOS_DISABLE_VRR:-0}" != "1" ]] && GS_ARGS+=(--adaptive-sync)
[[ "${MECHOS_HDR:-0}" == "1" ]] && GS_ARGS+=(--hdr-enabled)

set +e
/usr/bin/gamescope "${GS_ARGS[@]}" -- /usr/local/bin/mechscope >>"$LOG_FILE" 2>&1
RC=$?
set -e

if [[ "$RC" -eq 0 ]]; then
  exit 0
fi

printf '[MechOS] Gamescope exited with %s; retrying MechScope through Plasma.\n' "$RC" >>"$LOG_FILE"
start_plasma_mechscope
EOF
  chmod 755 "$target"
  bash -n "$target" || fail "MechScope session wrapper syntax failed in $tree"
}

patch_oobe_handoff(){
  local tree="$1"
  local helper="$tree/usr/local/libexec/mechos-oobe-apply"
  [ -f "$helper" ] || return 0

  python3 - "$helper" <<'PY'
from pathlib import Path
import re
import sys

p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')

# SDDM must point to the session that actually exists in
# /usr/share/wayland-sessions. Older OOBE builds used more than one historical
# gaming session name, so normalize any generated SDDM Session= assignment
# instead of depending on one exact legacy string.
t, session_count = re.subn(
    r'Session=[A-Za-z0-9_.-]+\.desktop',
    'Session=mechscope.desktop',
    t,
)
if session_count == 0 and 'Session=mechscope.desktop' not in t:
    raise SystemExit('[MechOS Installed MechScope Launch] OOBE SDDM Session assignment missing')

marker='# MECHOS_FORCE_INITIAL_GAMING_MODE_V1'
needle='state = Path("/var/lib/mechos"); state.mkdir(parents=True, exist_ok=True)'
if marker not in t:
    block='''# MECHOS_FORCE_INITIAL_GAMING_MODE_V1\n# The OOBE runs in Plasma, but the permanent account must start in Gaming Mode.\nhome = Path(pwd.getpwnam(username).pw_dir)\nmode_dir = home / ".config" / "mechos"\nmode_dir.mkdir(parents=True, exist_ok=True)\nmode_file = mode_dir / "session-mode"\nmode_file.write_text("gaming\\n")\ntry:\n    uid = pwd.getpwnam(username).pw_uid\n    gid = pwd.getpwnam(username).pw_gid\n    for item in (mode_dir.parent, mode_dir, mode_file):\n        os.chown(item, uid, gid)\nexcept Exception:\n    pass\n\n'''
    if needle not in t:
        raise SystemExit('[MechOS Installed MechScope Launch] OOBE state anchor missing')
    t=t.replace(needle, block+needle, 1)

compile(t,str(p),'exec')
p.write_text(t,encoding='utf-8')
PY

  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$helper" || fail "OOBE helper syntax failed in $tree"
  grep -Fq 'Session=mechscope.desktop' "$helper" || {
    grep -n 'Session=' "$helper" >&2 || true
    fail "OOBE still points at the wrong SDDM session in $tree"
  }
  grep -Fq 'MECHOS_FORCE_INITIAL_GAMING_MODE_V1' "$helper" || fail "OOBE does not force initial Gaming Mode in $tree"
}

patch_tree(){
  local tree="$1"
  [ -f "$tree/usr/share/wayland-sessions/mechscope.desktop" ] || fail "mechscope.desktop missing from $tree"
  install_session_wrapper "$tree"
  patch_oobe_handoff "$tree"
}

patch_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"
replacement="$ARCHIVE.mechscope-launch"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log 'Installed MechScope now uses the real SDDM session, forces initial Gaming Mode, bypasses Gamescope in VMs, and falls back to Plasma if Gamescope fails'
