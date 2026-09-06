#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX16_APPLY_V1
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-16-applied"
LOG=/var/log/mechos-hotfix-0.3.0-16.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 16 apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

# Hotfix 16 is cumulative. If a system jumps directly from Hotfix 14, apply the
# bundled Hotfix 15 Creator/Store repairs first before converting those surfaces
# into pages of the unified shell.
if [ ! -e "$STATE/hotfix-0.3.0-15-applied" ]; then
  [ -x /usr/local/libexec/mechos-hotfix-0.3.0-15-apply ] || { echo 'ERROR: cumulative Hotfix 15 apply helper missing'; exit 95; }
  /usr/local/libexec/mechos-hotfix-0.3.0-15-apply
fi

for f in \
  /usr/local/libexec/mechos-hotfix16-single-shell-patch \
  /usr/local/bin/mechos-shell-route \
  /usr/local/bin/mechos-mode-launch \
  /usr/local/libexec/mechos-mode-launch-base-v15; do
  [ -x "$f" ] || { echo "ERROR: Hotfix16 component missing: $f"; exit 96; }
done
bash -n /usr/local/bin/mechos-shell-route
bash -n /usr/local/bin/mechos-mode-launch
python3 -m py_compile /usr/local/libexec/mechos-hotfix16-single-shell-patch

grep -Fq 'MECHOS_SHELL_ROUTE_V16' /usr/local/bin/mechos-shell-route
grep -Fq 'MECHOS_MODE_LAUNCH_V16' /usr/local/bin/mechos-mode-launch

TARGET=/usr/local/bin/mechscope
[ -f /usr/local/bin/mechscope.real ] && TARGET=/usr/local/bin/mechscope.real
[ -f "$TARGET" ] || { echo 'ERROR: MechScope implementation missing'; exit 97; }
python3 /usr/local/libexec/mechos-hotfix16-single-shell-patch "$TARGET"
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
compile(t,str(p),'exec')
assert 'MECHOS_HOTFIX16_SINGLE_WINDOW_SHELL' in t
assert 'QStackedWidget' in t
assert '_mechos_shell_route_v16' in t
assert '_mechos_shell_dispatch_v16' in t
assert 'mechos-shell-route-v16' in t
assert "return self._mechos_shell_route_v16('store')" in t
assert "return self._mechos_shell_route_v16('creator')" in t
PY

# Creator/Gaming mode requests now target the running MechScope shell rather
# than creating another top-level Creator window.
! grep -Eq 'mechos-vm-mode-runtime[[:space:]]+creator|mechos-creator-mode([[:space:]]|$)' /usr/local/bin/mechos-mode-launch

grep -Fq 'exec "$ROUTER" "$MODE"' /usr/local/bin/mechos-mode-launch

mkdir -p /etc/mechos
printf '0.3.0-hotfix.16\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.16/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.16\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 16\n' >/etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix16 applied: Gaming, Unified Store, Creator Mode, Performance, Update Center and Recovery now route inside one MechScope QStackedWidget shell. External apps such as Steam and games remain external."
