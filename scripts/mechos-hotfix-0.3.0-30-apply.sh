#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX30_HARDWARE_PYTHON_CRASH_LOOP_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-30-applied"
LOG=/var/log/mechos-hotfix-0.3.0-30.log
SESSION=/usr/local/bin/mechscope-session
RUNTIME=/usr/local/libexec/mechos-mechscope-runtime-v23
OWNER=/usr/local/libexec/mechscope-owner-v23.py
PUBLIC=/usr/local/bin/mechscope

mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1
log(){ printf '[%s] [MechOS Hotfix 30] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }
fail(){ log "ERROR: $*"; exit 1; }
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to repair'; exit 0; }
is_live && { log 'Live ISO detected; installed-system apply skipped'; exit 0; }
[ ! -e "$MARKER" ] || { log 'Hotfix 30 already applied'; exit 0; }

[ -x "$SESSION" ] || fail "required session missing: $SESSION"
bash -n "$SESSION"
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V21' "$SESSION" || fail 'hardware MechScope session V21 is not installed'
grep -Fq 'actual_mechscope' "$SESSION" || fail 'hardware MechScope target resolver is missing'
grep -Fq 'is_python_target' "$SESSION" || fail 'hardware Python target detection is missing'
grep -Fq 'MECHSCOPE_COMMAND=(/usr/bin/python3 "$target")' "$SESSION" || fail 'hardware Python interpreter routing is missing'
grep -Fq '/usr/bin/gamescope "$@" -- "${MECHSCOPE_COMMAND[@]}"' "$SESSION" || fail 'Gamescope does not use resolved MechScope command array'
grep -Fq 'crashes >= 3' "$SESSION" || fail 'hardware crash-loop ceiling is missing'
grep -Fq 'safe_desktop_fallback' "$SESSION" || fail 'hardware safe Desktop fallback is missing'

# Keep the public command reconciled to the source-owned runtime where possible.
# The V21 session independently detects raw Python, so mixed-version systems are
# still protected even if this repair is not possible.
if [ -f "$RUNTIME" ] && [ -f "$OWNER" ]; then
  python3 -m py_compile "$RUNTIME" "$OWNER"
  install -m0755 "$RUNTIME" "$PUBLIC"
  log 'reconciled public MechScope entrypoint to persistent runtime'
fi

install -d -m0755 /etc/mechos
printf '0.3.0-hotfix.30\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.30/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.30\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 30\n' >/etc/system-release

touch "$MARKER"
log 'Hotfix 30 applied: hardware MechScope now resolves Python targets through python3 and repeated crashes fall back safely to Desktop Mode.'
