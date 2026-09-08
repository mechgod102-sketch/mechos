#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX33_SOURCE_OWNED_MECHSCOPE_RUNTIME_V1

log(){ printf '[%s] [MechOS Hotfix 33] %s\n' "$(date -Is 2>/dev/null || date)" "$*" | tee -a /var/log/mechos-hotfix-0.3.0-33.log; }
fail(){ log "ERROR: $*"; exit 1; }
[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f /var/lib/mechos/installed ] || fail 'not an installed MechOS system'
[ ! -e /run/archiso/bootmnt ] || fail 'refusing live ISO'

RUNTIME=/usr/local/libexec/mechos-mechscope-source-runtime-v33
SHELL=/usr/local/share/mechos/mechscope/mechscope_shell.py
SAFE=/usr/local/libexec/mechos-mechscope-safe-launch-v31
SESSION=/usr/local/bin/mechscope-session
USER_CLEANUP=/usr/local/libexec/mechos-mechscope-user-cleanup-v33
MARKER=/var/lib/mechos/hotfix-0.3.0-33-applied

for f in "$RUNTIME" "$SHELL" "$SAFE" "$SESSION" "$USER_CLEANUP"; do
  [ -f "$f" ] || fail "required Hotfix 33 runtime missing: $f"
done

/usr/bin/python3 -m py_compile "$RUNTIME" "$SHELL" || fail 'source-owned MechScope Python validation failed'
bash -n "$SAFE" "$SESSION" "$USER_CLEANUP" || fail 'Hotfix 33 shell validation failed'
grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33' "$RUNTIME" || fail 'V33 runtime marker missing'
grep -Fq 'class MechScopeShell' "$SHELL" || fail 'source MechScopeShell missing'
grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_ROUTE_V33' "$SAFE" || fail 'safe-launch V33 route missing'
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V23_SOURCE_RUNTIME' "$SESSION" || fail 'hardware V33 session route missing'
if grep -Fq 'elif [ -f /usr/local/bin/mechscope.real ]' "$SAFE"; then
  fail 'installed safe launcher still contains automatic mechscope.real fallback'
fi

# Reassert canonical SDDM session ownership.
mkdir -p /etc/sddm.conf.d
cat >/etc/sddm.conf.d/99-mechos-final-user.conf <<'EOF'
[Autologin]
User=
Session=mechscope.desktop
Relogin=false
EOF
mkdir -p /usr/share/wayland-sessions
cat >/usr/share/wayland-sessions/mechscope.desktop <<'EOF'
[Desktop Entry]
Name=MechScope
Comment=MechOS Gamescope + Steam Gaming Mode
Exec=/usr/local/bin/mechscope-session
TryExec=/usr/local/bin/mechscope-session
Type=Application
DesktopNames=MechScope
EOF

# Disable system-wide historical launchers that compete with the SDDM session.
if [ -d /etc/xdg/autostart ]; then
  while IFS= read -r -d '' desktop; do
    case "$(basename "$desktop")" in
      mechos-mechscope-user-cleanup-v33.desktop) continue ;;
    esac
    if grep -Eq 'Exec=.*(mechscope|mechos-mechscope-safe-launch-v31|mechos-session-autostart-v(24|31))' "$desktop" 2>/dev/null; then
      if ! grep -Fq 'Hidden=true' "$desktop"; then
        printf '\n# MECHOS_HF33_DISABLED_LEGACY_SYSTEM_MECHSCOPE_AUTOSTART\nHidden=true\n' >>"$desktop"
      fi
      log "disabled legacy system MechScope autostart: $desktop"
    fi
  done < <(find /etc/xdg/autostart -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)
fi

# Preserve the HF31 tutorial/OOBE wrapper but require its final MechScope handoff
# to go through the safe launcher. If an older direct REAL exec survived, patch
# only that handoff in place rather than replacing the wrapper.
PUBLIC=/usr/local/bin/mechscope
if [ -f "$PUBLIC" ]; then
  python3 - "$PUBLIC" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
if 'MECHOS_TUTORIAL_WRAPPER_V' in t:
    direct='exec "$REAL" "$@"'
    safe='MECHOS_MECHSCOPE_TARGET="" exec /usr/local/libexec/mechos-mechscope-safe-launch-v31 "$@"'
    if direct in t:
        t=t.replace(direct,safe)
    if '# MECHOS_TUTORIAL_SOURCE_RUNTIME_V33' not in t:
        lines=t.splitlines()
        for i,line in enumerate(lines):
            if 'MECHOS_TUTORIAL_WRAPPER_V' in line:
                lines.insert(i+1,'# MECHOS_TUTORIAL_SOURCE_RUNTIME_V33')
                break
        t='\n'.join(lines)+'\n'
    p.write_text(t,encoding='utf-8')
PY
  chmod 0755 "$PUBLIC"
  bash -n "$PUBLIC" || fail 'public MechScope tutorial wrapper became invalid'
fi

# Remove stale crash-loop state so the new source-owned runtime gets one clean
# post-reboot attempt. Historical logs are retained for diagnostics.
rm -f /var/lib/mechos/hotfix-0.3.0-33-applied.tmp
for home in /home/*; do
  [ -d "$home/.local/state/mechos" ] || continue
  rm -f "$home/.local/state/mechos/mechscope-crash-loop-v30" "$home/.local/state/mechos/mechscope-crash-loop-v33" || true
done

touch "$MARKER"
log 'Hotfix 33 applied: installed MechScope now owns a complete source runtime; legacy .real automatic startup is disabled.'
