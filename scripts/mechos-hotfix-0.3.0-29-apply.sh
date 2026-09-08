#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX29_MECHSCOPE_LIFETIME_CREATOR_ICONS_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-29-applied"
LOG=/var/log/mechos-hotfix-0.3.0-29.log
SESSION=/usr/local/bin/mechscope-session
RUNTIME=/usr/local/libexec/mechos-mechscope-runtime-v23
OWNER=/usr/local/libexec/mechscope-owner-v23.py
PUBLIC=/usr/local/bin/mechscope
VM=/usr/local/bin/mechos-vm-mode-runtime
VM_CORE=/usr/local/libexec/mechos-vm-mode-runtime-v5
WATCHDOG=/usr/local/libexec/mechos-vm-mechscope-watchdog-v29
CANVAS=/usr/local/share/mechos/ui/fixed_canvas.py
ICON_MODULE=/usr/local/share/mechos/ui/creator_real_icons_v22.py
ICON_PATCH=/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch
WAYLAND_SESSION=/usr/share/wayland-sessions/mechscope.desktop

mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1
log(){ printf '[%s] [MechOS Hotfix 29] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }
fail(){ log "ERROR: $*"; exit 1; }
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to repair'; exit 0; }
is_live && { log 'Live ISO detected; installed-system apply skipped'; exit 0; }
[ ! -e "$MARKER" ] || { log 'Hotfix 29 already applied'; exit 0; }

for f in "$SESSION" "$RUNTIME" "$VM" "$VM_CORE" "$WATCHDOG" "$ICON_PATCH"; do
  [ -x "$f" ] || fail "required executable missing: $f"
done
for f in "$OWNER" "$CANVAS" "$ICON_MODULE"; do
  [ -f "$f" ] || fail "required runtime file missing: $f"
done

bash -n "$SESSION"
bash -n "$VM"
bash -n "$VM_CORE"
bash -n "$WATCHDOG"
python3 -m py_compile "$RUNTIME" "$CANVAS" "$ICON_MODULE" "$ICON_PATCH" "$OWNER"

grep -Fq 'MECHOS_MECHSCOPE_SESSION_V20' "$SESSION" || fail 'supervised hardware MechScope session V20 is not installed'
grep -Fq 'MECHOS_SESSION_SUPERVISED=1' "$SESSION" || fail 'hardware MechScope session is not lifetime-supervised'
grep -Fq 'return 90' "$SESSION" || fail 'hardware Gamescope clean-exit recovery is missing'
grep -Fq 'MECHOS_MECHSCOPE_LIFETIME_V29' "$RUNTIME" || fail 'MechScope lifetime runtime V29 is not installed'
grep -Fq 'app.setQuitOnLastWindowClosed(False)' "$RUNTIME" || fail 'MechScope last-window guard is missing'
grep -Fq 'MECHOS_VM_MECHSCOPE_SUSTAINED_HEALTH_V6' "$VM" || fail 'VM sustained-health runtime V6 is not installed'
grep -Fq 'MECHOS_VM_MECHSCOPE_PERSISTENT_RUNTIME_V5' "$VM_CORE" || fail 'VM Hotfix 28 core runtime is missing'
grep -Fq 'MECHOS_VM_MECHSCOPE_WATCHDOG_V29' "$WATCHDOG" || fail 'VM watchdog V29 is missing'
grep -Fq 'MECHOS_CREATOR_BUTTON_ICONS_V1' "$CANVAS" || fail 'source-owned Creator button icons are missing'
grep -Fq 'MECHOS_CREATOR_REAL_ICONS_V22' "$ICON_MODULE" || fail 'Creator real-icon resolver is missing'
grep -Fq 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' "$ICON_PATCH" || fail 'Creator real-icon owner patch is missing'

# Ensure the public MechScope command is the persistent runtime. Mixed-version
# upgrades may still point it at an old generated owner or wrapper even though
# the current persistent runtime and preserved owner are present.
if [ ! -f "$PUBLIC" ] || ! grep -Fq 'MECHOS_MECHSCOPE_LIFETIME_V29' "$PUBLIC" 2>/dev/null; then
  install -m0755 "$RUNTIME" "$PUBLIC"
  log 'repaired public /usr/local/bin/mechscope entrypoint to lifetime runtime V29'
fi
grep -Fq 'MECHOS_MECHSCOPE_LIFETIME_V29' "$PUBLIC" || fail 'public MechScope entrypoint did not reconcile to V29'

# Re-apply the real-icon activation to the generated Creator owner. The patcher
# is idempotent, so systems that already have the marker are simply verified.
CREATOR=/usr/local/bin/mechos-creator-mode
[ -f /usr/local/bin/mechos-creator-mode.real ] && CREATOR=/usr/local/bin/mechos-creator-mode.real
[ -f "$CREATOR" ] || fail 'Creator Mode implementation missing'
grep -Fq 'MECHOS_HOTFIX10_CREATOR_VISUAL_OWNER_V1' "$CREATOR" || fail 'Creator visual owner v10 is not active'
python3 "$ICON_PATCH" "$CREATOR"
python3 - "$CREATOR" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
compile(t,str(p),'exec')
assert 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' in t
assert 'creator_real_icons_v22.py' in t
assert 'icons.install(shell)' in t
PY
log "Creator real-icon activation verified target=$CREATOR"

# Keep the canonical installed Gaming Mode session name. Do not revive the old
# mechos-gaming.desktop identifier that caused prior post-OOBE handoff failures.
install -d -m0755 /usr/share/wayland-sessions
cat >"$WAYLAND_SESSION" <<'EOF'
[Desktop Entry]
Name=MechScope
Comment=MechOS Gamescope + Steam Gaming Mode
Exec=/usr/local/bin/mechscope-session
TryExec=/usr/local/bin/mechscope-session
Type=Application
DesktopNames=MechScope
EOF
chmod 0644 "$WAYLAND_SESSION"
grep -Fq 'Exec=/usr/local/bin/mechscope-session' "$WAYLAND_SESSION" || fail 'canonical MechScope Wayland session is invalid'

# Reconcile historical SDDM files at runtime. Sensitive display-manager config
# is intentionally not shipped directly in the update bundle.
if [ -d /etc/sddm.conf.d ]; then
  while IFS= read -r -d '' f; do
    if grep -Fq 'Session=mechos-gaming.desktop' "$f" 2>/dev/null; then
      sed -i 's/Session=mechos-gaming\.desktop/Session=mechscope.desktop/g' "$f"
      log "reconciled stale SDDM MechScope session in $f"
    fi
  done < <(find /etc/sddm.conf.d -maxdepth 1 -type f -print0)
fi

# Version is committed only after every repair/validation above succeeds.
install -d -m0755 /etc/mechos
printf '0.3.0-hotfix.29\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.29/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.29\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 29\n' >/etc/system-release

touch "$MARKER"
log 'Hotfix 29 applied: Creator real icons reconciled, VM MechScope sustained-health supervision enabled, and hardware Gamescope/Plasma Gaming Mode now recovers early MechScope exits.'
