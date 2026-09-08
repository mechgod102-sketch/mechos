#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX28_VM_MECHSCOPE_LAUNCH_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-28-applied"
RUNTIME=/usr/local/bin/mechos-vm-mode-runtime
LAUNCHER=/usr/local/bin/mechos-mode-launch
REAL=/usr/local/bin/mechscope.real
PERSISTENT=/usr/local/libexec/mechos-mechscope-runtime-v23
OWNER=/usr/local/libexec/mechscope-owner-v23.py

log(){ printf '[MechOS Hotfix 28] %s\n' "$*"; }
fail(){ printf '[MechOS Hotfix 28] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to repair'; exit 0; }
[ -x "$RUNTIME" ] || fail "VM runtime missing: $RUNTIME"
[ -x "$LAUNCHER" ] || fail "mode launcher missing: $LAUNCHER"

grep -Fq 'MECHOS_VM_MECHSCOPE_PERSISTENT_RUNTIME_V5' "$RUNTIME" || fail 'new VM MechScope runtime is not installed'
grep -Fq 'MECHOS_MODE_LAUNCH_VM_DIRECT_V28' "$LAUNCHER" || fail 'v19 VM direct mode router is not installed'
bash -n "$RUNTIME"
bash -n "$LAUNCHER"

# Some HF21/HF27 upgrade paths preserve the generated MechScope owner as
# /usr/local/bin/mechscope.real without a Python shebang. Historical VM launchers
# then ask /bin/sh to interpret Python source, producing "from: command not found".
# The new runtime always invokes Python source through /usr/bin/python3, but add
# a shebang to the legacy owner as a compatibility guard for stale direct paths.
if [ -f "$REAL" ]; then
  first="$(head -n1 "$REAL" 2>/dev/null || true)"
  if ! printf '%s\n' "$first" | grep -qi python && \
     grep -Eq '^[[:space:]]*(from|import)[[:space:]]+[A-Za-z0-9_\.]+' "$REAL"; then
    python3 - "$REAL" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
text=p.read_text(encoding='utf-8')
compile(text,str(p),'exec')
if not text.startswith('#!'):
    p.write_text('#!/usr/bin/env python3\n'+text,encoding='utf-8')
PY
    chmod 0755 "$REAL"
    log 'added Python shebang compatibility guard to legacy mechscope.real'
  fi
fi

# Verify every Python target the VM resolver may use without writing pycache.
for target in "$PERSISTENT" "$OWNER" "$REAL"; do
  [ -f "$target" ] || continue
  if head -n1 "$target" | grep -qi python || grep -Eq '^[[:space:]]*(from|import)[[:space:]]+[A-Za-z0-9_\.]+' "$target"; then
    /usr/bin/python3 - "$target" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
  fi
done

# Restore the public VM-safe desktop launcher in case an older update removed it.
install -d -m0755 /usr/share/applications
cat >/usr/share/applications/mechos-return-gaming.desktop <<'EOF'
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

grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' /usr/share/applications/mechos-return-gaming.desktop

mkdir -p "$STATE"
touch "$MARKER"
log 'Hotfix 28 applied: VMware/VM MechScope now uses the persistent runtime or explicit Python interpreter fallback instead of executing raw Python as shell code.'
