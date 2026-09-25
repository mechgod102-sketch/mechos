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
  /usr/local/bin/mechos-legacy-gpu-setup \
  /usr/local/libexec/mechos-gpu-setup-integration-v0311 \
  /usr/local/libexec/mechos-legacy-gpu-session-patch-v0311 \
  /usr/local/libexec/mechos-legacy-gpu-control-patch-v0311; do
  [ -e "$f" ] || fail "required hotfix component missing: $f"
done

# Add legacy support into the already-installed GPU/session/UI components.
# Do not replace their modern implementations.
if [ -f /usr/local/bin/mechos-gpu-setup ]; then
  python3 /usr/local/libexec/mechos-gpu-setup-integration-v0311 /usr/local/bin/mechos-gpu-setup
  bash -n /usr/local/bin/mechos-gpu-setup
else
  log 'WARNING: existing mechos-gpu-setup was not found; legacy report remains available independently'
fi

python3 /usr/local/libexec/mechos-legacy-gpu-session-patch-v0311 /usr/local/bin/mechscope-session
bash -n /usr/local/bin/mechscope-session

if [ -f /usr/local/libexec/mechos-031-control-suite ]; then
  python3 /usr/local/libexec/mechos-legacy-gpu-control-patch-v0311 /usr/local/libexec/mechos-031-control-suite
  python3 -m py_compile /usr/local/libexec/mechos-031-control-suite
fi

bash -n /usr/local/bin/mechos-update-helper
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
