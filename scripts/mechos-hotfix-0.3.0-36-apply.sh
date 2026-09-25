#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX36_INTEL_UMA_INTEGRATION_V1

LOG=/var/log/mechos-hotfix-0.3.0-36.log
SESSION=/usr/local/bin/mechscope-session
PATCH=/usr/local/libexec/mechos-intel-uma-session-patch-v36
PREFLIGHT=/usr/local/libexec/mechos-intel-uma-preflight-v36
MARKER=/var/lib/mechos/hotfix-0.3.0-36-applied

log(){ printf '[%s] [MechOS Hotfix 36] %s\n' "$(date -Is 2>/dev/null || date)" "$*" | tee -a "$LOG"; }
fail(){ log "ERROR: $*"; exit 1; }

[[ "$(id -u)" -eq 0 ]] || fail 'must run as root'
[[ -f /var/lib/mechos/installed ]] || fail 'not an installed MechOS system'
[[ ! -e /run/archiso/bootmnt ]] || fail 'refusing live ISO'
[[ -f "$SESSION" ]] || fail "MechScope session missing: $SESSION"
[[ -x "$PATCH" ]] || fail "Intel UMA patcher missing: $PATCH"
[[ -x "$PREFLIGHT" ]] || fail "Intel UMA preflight missing: $PREFLIGHT"

python3 "$PATCH" "$SESSION" || fail 'could not integrate Intel UMA support'
bash -n "$SESSION" "$PREFLIGHT" || fail 'Intel UMA integration validation failed'
grep -Fq 'MECHOS_INTEL_UMA_INTEGRATION_V36' "$SESSION" || fail 'Intel UMA marker missing'
grep -Fq 'GBM_BACKEND=nvidia-drm' "$SESSION" || fail 'existing NVIDIA path changed unexpectedly'
grep -Fq 'run_gamescope primary' "$SESSION" || fail 'existing Gamescope path changed unexpectedly'
grep -Fq 'start_plasma_mechscope' "$SESSION" || fail 'existing fallback path changed unexpectedly'

mkdir -p /var/lib/mechos
touch "$MARKER"
log 'Hotfix 36 applied: Intel UMA support integrated into the existing MechScope session.'
