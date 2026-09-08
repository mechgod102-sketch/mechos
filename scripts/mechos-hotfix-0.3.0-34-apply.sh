#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX34_MECHSCOPE_RESPONSIVE_UI_V1

log(){ printf '[%s] [MechOS Hotfix 34] %s\n' "$(date -Is 2>/dev/null || date)" "$*" | tee -a /var/log/mechos-hotfix-0.3.0-34.log; }
fail(){ log "ERROR: $*"; exit 1; }
[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f /var/lib/mechos/installed ] || fail 'not an installed MechOS system'
[ ! -e /run/archiso/bootmnt ] || fail 'refusing live ISO'

SHELL=/usr/local/share/mechos/mechscope/mechscope_shell.py
RUNTIME=/usr/local/libexec/mechos-mechscope-source-runtime-v33
SAFE=/usr/local/libexec/mechos-mechscope-safe-launch-v31
SESSION=/usr/local/bin/mechscope-session
MARKER=/var/lib/mechos/hotfix-0.3.0-34-applied

for f in "$SHELL" "$RUNTIME" "$SAFE" "$SESSION"; do
  [ -f "$f" ] || fail "required MechScope component missing: $f"
done

/usr/bin/python3 -m py_compile "$SHELL" "$RUNTIME" || fail 'MechScope Python validation failed'
bash -n "$SAFE" "$SESSION" || fail 'MechScope launcher/session validation failed'

grep -Fq 'MECHOS_MECHSCOPE_RESPONSIVE_UI_V34' "$SHELL" || fail 'responsive UI V34 marker missing'
grep -Fq 'MECHOS_QUICK_ACTION_SINGLE_LINE_V34' "$SHELL" || fail 'single-line Quick Actions marker missing'
grep -Fq 'class ElidedLabel' "$SHELL" || fail 'elided status label implementation missing'
grep -Fq 'QLabel[role="hero-title"]{color:#eef4ff}' "$SHELL" || fail 'explicit hero title color missing'
grep -Fq 'Qt.TextElideMode.ElideRight' "$SHELL" || fail 'GPU/status elision behavior missing'
grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33' "$RUNTIME" || fail 'HF33 source-owned runtime was regressed'
grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_ROUTE_V33' "$SAFE" || fail 'HF33 source-owned launcher route was regressed'
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V23_SOURCE_RUNTIME' "$SESSION" || fail 'HF33 hardware session route was regressed'

# Ensure stale bytecode cannot make the first post-update launch render the old
# shell if the Python cache timestamp happens to survive the cumulative update.
rm -rf /usr/local/share/mechos/mechscope/__pycache__ 2>/dev/null || true

# Keep the canonical MechScope hardware session unchanged. HF34 is intentionally
# visual-only and must not re-open the launcher/runtime architecture fixed by HF33.
mkdir -p /etc/sddm.conf.d /usr/share/wayland-sessions
cat >/etc/sddm.conf.d/99-mechos-final-user.conf <<'EOF'
[Autologin]
User=
Session=mechscope.desktop
Relogin=false
EOF
cat >/usr/share/wayland-sessions/mechscope.desktop <<'EOF'
[Desktop Entry]
Name=MechScope
Comment=MechOS Gamescope + Steam Gaming Mode
Exec=/usr/local/bin/mechscope-session
TryExec=/usr/local/bin/mechscope-session
Type=Application
DesktopNames=MechScope
EOF

touch "$MARKER"
log 'Hotfix 34 applied: MechScope responsive UI cleanup installed; HF33 source-owned runtime/session preserved.'
