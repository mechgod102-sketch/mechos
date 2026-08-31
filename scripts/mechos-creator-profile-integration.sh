#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS Creator Profiles] %s\n' "$*"; }
fail() { printf '[MechOS Creator Profiles] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$PAYLOAD/mechos-rootfs.tar.zst" ] || fail "installed-system payload archive is missing"

install_profile_launcher() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  mkdir -p "$bin"

  cat > "$bin/mechos-creator-profile-launch" <<'PYEOF'
#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
from pathlib import Path

CONFIG = Path.home() / ".config" / "mechos" / "creator-preset.json"
APP = "/usr/local/bin/mechos-creator-app"

# Deliberately small startup sets. Creator Mode itself is always the primary
# dashboard; profile apps are helpers for that workflow, not a second desktop.
PROFILES = {
    "VRChat Creator": ["unityhub", "blender"],
    "Game Dev": ["vscode", "gitkraken", "__engine__"],
    "3D Artist": ["blender", "krita"],
    "Streaming": ["obs", "discord"],
    "Manual": [],
}


def installed(app_id: str) -> bool:
    if not Path(APP).is_file():
        return False
    result = subprocess.run(
        [APP, "status", app_id],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=12,
        check=False,
    )
    return result.returncode == 0 and result.stdout.strip() == "installed"


def choose_engine() -> str | None:
    # Prefer an engine implied by projects already on disk, then fall back to
    # whichever supported launcher is installed. Unreal remains vendor-managed
    # in the current Creator catalog and is therefore not auto-started here.
    roots = [Path.home() / "MechOS" / "Projects", Path.home() / "Projects"]
    try:
        for root in roots:
            if not root.is_dir():
                continue
            if any(root.rglob("project.godot")) and installed("godot"):
                return "godot"
            if any(root.rglob("ProjectVersion.txt")) and installed("unityhub"):
                return "unityhub"
    except OSError:
        pass
    if installed("godot"):
        return "godot"
    if installed("unityhub"):
        return "unityhub"
    return None


def notify(message: str) -> None:
    if not message:
        return
    if subprocess.run(
        ["bash", "-lc", "command -v kdialog >/dev/null 2>&1"],
        check=False,
    ).returncode == 0:
        subprocess.Popen(
            ["kdialog", "--title", "MechOS Creator Profile", "--passivepopup", message, "8"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )


def main() -> int:
    # Creator profiles are installed-system behavior only. The Live ISO keeps
    # Creator Mode as a manual/test surface.
    if Path("/run/archiso/bootmnt").exists():
        return 0
    if not Path("/var/lib/mechos/oobe-complete").exists():
        return 0
    try:
        data = json.loads(CONFIG.read_text())
    except Exception:
        return 0

    profile = str(data.get("preset", "Manual"))
    if profile not in PROFILES:
        return 0
    if not bool(data.get("autolaunch", profile != "Manual")):
        return 0

    requested = list(PROFILES[profile])
    if "__engine__" in requested:
        requested.remove("__engine__")
        engine = choose_engine()
        if engine:
            requested.append(engine)

    launched = []
    missing = []
    seen = set()
    for app_id in requested:
        if app_id in seen:
            continue
        seen.add(app_id)
        if not installed(app_id):
            missing.append(app_id)
            continue
        subprocess.Popen(
            [APP, "launch", app_id],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        launched.append(app_id)
        time.sleep(0.8)

    parts = []
    if launched:
        parts.append(f"{profile}: opened " + ", ".join(launched))
    if missing:
        parts.append("Not installed: " + ", ".join(missing) + ". Install them from Creator Mode.")
    notify("\n".join(parts))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PYEOF
  chmod 755 "$bin/mechos-creator-profile-launch"
}

patch_creator_dashboard() {
  local target="$1"
  [ -f "$target" ] || return 0

  python3 - "$target" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
marker = "# MECHOS_CREATOR_PROFILE_AUTOLAUNCH_V1"
if marker in text:
    raise SystemExit(0)

old_buttons = 'for name in ["Game Dev","VRChat Creator","3D Artist","Streaming"]:'
new_buttons = 'for name in ["Game Dev","VRChat Creator","3D Artist","Streaming","Manual"]:'
if old_buttons not in text:
    raise SystemExit(f"Creator preset button block not found: {p}")
text = text.replace(old_buttons, new_buttons, 1)

old_title = 'QLabel("CREATOR MODE PRESETS")'
if old_title in text:
    text = text.replace(old_title, 'QLabel("CREATOR STARTUP PROFILES")', 1)

old_data = 'data={"preset":name,"updated":int(time.time())}'
new_data = 'data={"preset":name,"autolaunch":name!="Manual","updated":int(time.time())}  # MECHOS_CREATOR_PROFILE_AUTOLAUNCH_V1'
if old_data not in text:
    raise SystemExit(f"Creator apply_preset data block not found: {p}")
text = text.replace(old_data, new_data, 1)

old_message = 'QMessageBox.information(self,"Creator Preset",f"{name} preset activated.\\\nPower profile: {profile}")'
new_message = 'QMessageBox.information(self,"Creator Profile",f"{name} profile activated.\\\nPower profile: {profile}\\\nApp auto-launch: {\'off\' if name==\'Manual\' else \'on next Creator Mode start\'}")'
if old_message in text:
    text = text.replace(old_message, new_message, 1)

p.write_text(text, encoding="utf-8")
PY
}

patch_creator_session() {
  local target="$1"
  [ -f "$target" ] || return 0
  grep -Fq '# MECHOS_CREATOR_PROFILE_SESSION_V1' "$target" && return 0

  python3 - "$target" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
old = '''(
  sleep 6
  /usr/local/bin/mechos-creator-mode >/dev/null 2>&1 &
) &
exec /usr/bin/startplasma-wayland
'''
new = '''(
  sleep 6
  /usr/local/bin/mechos-creator-mode >/dev/null 2>&1 &
  # MECHOS_CREATOR_PROFILE_SESSION_V1
  # Give the dashboard a moment to render, then open the saved workflow apps.
  sleep 2
  /usr/local/bin/mechos-creator-profile-launch --startup >/dev/null 2>&1 &
) &
exec /usr/bin/startplasma-wayland
'''
if old not in text:
    raise SystemExit(f"Creator session launch block not found: {p}")
p.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
}

patch_tree() {
  local tree="$1"
  install_profile_launcher "$tree"
  patch_creator_dashboard "$tree/usr/local/bin/mechos-creator-mode"
  patch_creator_session "$tree/usr/local/bin/mechos-creator-session"
}

# Patch any Creator runtime still present in the build root for validation and
# recovery use. Current MechOS may later strip Creator-only runtime from Live.
patch_tree "$ROOT"

# The installed payload is authoritative for Creator Mode startup behavior.
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"

[ -x "$tmp/usr/local/bin/mechos-creator-profile-launch" ] || fail "Creator profile launcher missing from installed payload"
grep -Fq 'MECHOS_CREATOR_PROFILE_AUTOLAUNCH_V1' "$tmp/usr/local/bin/mechos-creator-mode" || fail "Creator dashboard profile patch missing"
grep -Fq 'MECHOS_CREATOR_PROFILE_SESSION_V1' "$tmp/usr/local/bin/mechos-creator-session" || fail "Creator session auto-launch hook missing"
grep -Fq '"VRChat Creator": ["unityhub", "blender"]' "$tmp/usr/local/bin/mechos-creator-profile-launch" || fail "VRChat profile mapping missing"
grep -Fq '"Streaming": ["obs", "discord"]' "$tmp/usr/local/bin/mechos-creator-profile-launch" || fail "Streaming profile mapping missing"

new_archive="$ARCHIVE.creator-profiles"
tar --zstd -cf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

if [ -f "$PROFILE" ] && ! grep -Fq 'file_permissions["/usr/local/bin/mechos-creator-profile-launch"]' "$PROFILE"; then
  printf '\nfile_permissions["/usr/local/bin/mechos-creator-profile-launch"]="0:0:755"\n' >> "$PROFILE"
fi

if [ -f "$ROOT/usr/local/bin/mechos-creator-profile-launch" ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$ROOT/usr/local/bin/mechos-creator-profile-launch" || fail "Creator profile launcher syntax validation failed"
fi
if [ -f "$ROOT/usr/local/bin/mechos-creator-mode" ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$ROOT/usr/local/bin/mechos-creator-mode" || fail "Creator Mode syntax validation failed after profile patch"
fi
if [ -f "$ROOT/usr/local/bin/mechos-creator-session" ]; then
  bash -n "$ROOT/usr/local/bin/mechos-creator-session" || fail "Creator session syntax validation failed after profile patch"
fi

log "Creator startup profiles installed: Game Dev, VRChat Creator, 3D Artist, Streaming, Manual"
