#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX_0311_LEGACY_GPU_UPDATE_RELIABILITY_V1

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.1-1-applied"
LOG=/var/log/mechos-hotfix-0.3.1-1.log

mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1
log(){ printf '[%s] [MechOS 0.3.1-hotfix.1] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }
fail(){ log "ERROR: $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f "$STATE/installed" ] || { log 'installed-system marker absent; nothing to apply'; exit 0; }
[ ! -e /run/archiso/bootmnt ] || { log 'Live ISO detected; installed-system apply skipped'; exit 0; }
[ ! -e "$MARKER" ] || { log 'Hotfix already applied'; exit 0; }

for f in \
  /usr/local/bin/mechos-update-helper \
  /usr/local/bin/mechscope-session \
  /usr/local/bin/mechos-legacy-gpu-setup; do
  [ -e "$f" ] || fail "required hotfix component missing: $f"
done

bash -n /usr/local/bin/mechos-update-helper
bash -n /usr/local/bin/mechscope-session
bash -n /usr/local/bin/mechos-legacy-gpu-setup

/usr/local/bin/mechos-update-helper selftest >/dev/null
/usr/local/bin/mechos-legacy-gpu-setup --report || true

install -d -m0755 /etc/mechos
printf '0.3.1-hotfix.1\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.1-hotfix.1/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.1-hotfix.1\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.1 Hotfix 1\n' >/etc/system-release

touch "$MARKER"
log 'Hotfix applied: updater reliability and legacy GPU compatibility integration are active.'
