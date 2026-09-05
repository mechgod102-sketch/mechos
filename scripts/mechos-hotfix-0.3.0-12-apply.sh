#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-12-applied"
LOG=/var/log/mechos-hotfix-0.3.0-12.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 12 apply start"
[ -e "$MARKER" ] && exit 0

is_live(){ [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system Hotfix 12 apply skipped.'; exit 0; }

MODE_LAUNCH=/usr/local/bin/mechos-mode-launch
VM_RUNTIME=/usr/local/bin/mechos-vm-mode-runtime
for f in "$MODE_LAUNCH" "$VM_RUNTIME"; do
  [ -f "$f" ] || { echo "ERROR: Hotfix 12 component missing: $f"; exit 61; }
  chmod 0755 "$f"
  bash -n "$f"
done

grep -Fq 'MECHOS_VM_MECHSCOPE_NO_PYCACHE_HEALTHCHECK_V4' "$VM_RUNTIME"
grep -Fq 'MECHOS_HOTFIX12_NO_PYCACHE_HEALTHCHECK_V1' "$MODE_LAUNCH"
grep -Fq "compile(source, str(p), 'exec')" "$VM_RUNTIME"
grep -Fq "compile(source, str(p), 'exec')" "$MODE_LAUNCH"

if grep -Fq 'python3 -m py_compile "$target"' "$VM_RUNTIME"; then
  echo 'ERROR: VM runtime still compiles root-owned MechScope to __pycache__.' >&2
  exit 62
fi
if grep -Fq 'python3 -m py_compile "$target"' "$MODE_LAUNCH"; then
  echo 'ERROR: mode launcher still compiles root-owned MechScope to __pycache__.' >&2
  exit 63
fi

mkdir -p /etc/mechos
printf '0.3.0-hotfix.12\n' > /etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.12/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.12\n' >> /etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 12\n' > /etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix 12 applied: MechScope runtime source validation is now read-only and no longer writes __pycache__ under /usr/local/bin."
