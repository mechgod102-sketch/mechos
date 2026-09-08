#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX31_PUBLIC_MECHSCOPE_PYTHON_WRAPPER_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-31-applied"
LOG=/var/log/mechos-hotfix-0.3.0-31.log
PUBLIC=/usr/local/bin/mechscope
REAL=/usr/local/bin/mechscope.real
SAFE=/usr/local/libexec/mechos-mechscope-safe-launch-v31
AUTOSTART=/usr/local/bin/mechos-session-autostart-v24
AUTOSTART_SOURCE=/usr/local/libexec/mechos-session-autostart-v31

mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1
log(){ printf '[%s] [MechOS Hotfix 31] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }
fail(){ log "ERROR: $*"; exit 1; }
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to repair'; exit 0; }
is_live && { log 'Live ISO detected; installed-system apply skipped'; exit 0; }
[ ! -e "$MARKER" ] || { log 'Hotfix 31 already applied'; exit 0; }

[ -x "$SAFE" ] || fail "safe launcher missing: $SAFE"
[ -x "$AUTOSTART_SOURCE" ] || fail "safe KDE autostart source missing: $AUTOSTART_SOURCE"
bash -n "$SAFE" "$AUTOSTART_SOURCE"
grep -Fq 'MECHOS_MECHSCOPE_SAFE_LAUNCH_V31' "$SAFE" || fail 'safe launcher marker missing'
grep -Fq '/usr/bin/python3 "$target" "$@"' "$SAFE" || fail 'safe launcher Python interpreter route missing'

# Repair the field-installed tutorial wrapper without removing tutorial/OOBE
# behavior. Every direct exec of mechscope.real is replaced with the safe
# interpreter-aware launcher while REAL remains the intended underlying target.
[ -f "$PUBLIC" ] || fail "public MechScope wrapper missing: $PUBLIC"
if grep -Eq 'MECHOS_TUTORIAL_WRAPPER_V[12]' "$PUBLIC"; then
  python3 - "$PUBLIC" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
marker='# MECHOS_TUTORIAL_PYTHON_SAFE_V31'
safe='MECHOS_MECHSCOPE_TARGET="$REAL" exec /usr/local/libexec/mechos-mechscope-safe-launch-v31 "$@"'
old='exec "$REAL" "$@"'
if marker not in t:
    if old not in t:
        raise SystemExit('tutorial wrapper contains no direct REAL exec to repair')
    t=t.replace(old,safe)
    lines=t.splitlines()
    for i,line in enumerate(lines):
        if 'MECHOS_TUTORIAL_WRAPPER_V' in line:
            lines.insert(i+1,marker)
            break
    t='\n'.join(lines)+'\n'
p.write_text(t,encoding='utf-8')
PY
  chmod 0755 "$PUBLIC"
  bash -n "$PUBLIC"
  grep -Fq 'MECHOS_TUTORIAL_PYTHON_SAFE_V31' "$PUBLIC" || fail 'tutorial wrapper repair marker missing'
  grep -Fq 'mechos-mechscope-safe-launch-v31' "$PUBLIC" || fail 'tutorial wrapper does not use safe launcher'
  if grep -Fq 'exec "$REAL" "$@"' "$PUBLIC"; then
    fail 'tutorial wrapper still directly executes mechscope.real'
  fi
  log 'repaired tutorial wrapper to invoke raw MechScope through Python-safe launcher'
else
  log 'public MechScope is not a tutorial wrapper; leaving its semantics unchanged'
fi

# The preserved .real target is known to be raw Python on affected hardware.
# Validate it now so a syntax failure is recorded before graphical login.
if [ -f "$REAL" ] && grep -Eq '^[[:space:]]*(from|import)[[:space:]]+' "$REAL"; then
  /usr/bin/python3 - "$REAL" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
  log 'validated raw Python mechscope.real target'
fi

# Replace the HF24 physical-hardware KDE fallback. It previously bypassed the
# repaired hardware session and called /usr/local/bin/mechscope directly.
install -m0755 "$AUTOSTART_SOURCE" "$AUTOSTART"
bash -n "$AUTOSTART"
grep -Fq 'MECHOS_SESSION_AUTOSTART_V31' "$AUTOSTART" || fail 'KDE fallback V31 marker missing'
grep -Fq 'mechos-mechscope-safe-launch-v31' "$AUTOSTART" || fail 'KDE fallback does not use safe launcher'
if grep -Fq 'nohup /usr/local/bin/mechscope ' "$AUTOSTART"; then
  fail 'KDE fallback still directly launches public MechScope wrapper'
fi

install -d -m0755 /etc/mechos
printf '0.3.0-hotfix.31\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.31/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.31\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 31\n' >/etc/system-release

touch "$MARKER"
log 'Hotfix 31 applied: tutorial wrapper and KDE fallback now use the Python-safe MechScope launcher.'
