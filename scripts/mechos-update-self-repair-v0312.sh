#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_SELF_REPAIR_V0312

RECOVERY="${MECHOS_REPAIR_RECOVERY:-/usr/local/share/mechos/update-recovery}"
HELPER_SRC="$RECOVERY/mechos-update-helper-v37.sh"
CENTER_SRC="$RECOVERY/mechos-update-center"
BACKEND_SRC="$RECOVERY/mechos-update-center-v8.py"
REBOOT_SRC="$RECOVERY/mechos-reboot"
KEY_SRC="$RECOVERY/mechos-update-signing-public.pem"

HELPER="${MECHOS_REPAIR_HELPER:-/usr/local/bin/mechos-update-helper}"
CENTER="${MECHOS_REPAIR_CENTER:-/usr/local/bin/mechos-update-center}"
BACKEND="${MECHOS_REPAIR_BACKEND:-/usr/local/libexec/mechos-update-center-v8.py}"
REBOOT="${MECHOS_REPAIR_REBOOT:-/usr/local/bin/mechos-reboot}"
KEY="${MECHOS_REPAIR_KEY:-/etc/mechos/update-signing-public.pem}"
LOG="${MECHOS_REPAIR_LOG:-/var/log/mechos-update-self-repair.log}"

mode="${1:---check}"
case "$mode" in
  --check|--repair) ;;
  *) echo 'Usage: mechos-update-self-repair {--check|--repair}' >&2; exit 2 ;;
esac

log(){
  if [[ "$(id -u)" -eq 0 || -n "${MECHOS_REPAIR_TEST_MODE:-}" ]]; then
    mkdir -p "$(dirname "$LOG")"
    printf '[%s] [update-self-repair] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"
  fi
}

helper_valid(){
  [[ -f "$1" ]] || return 1
  bash -n "$1" >/dev/null 2>&1 || return 1
  grep -Fq 'MECHOS_UPDATE_HELPER_V37_SIGNED_MANIFEST_V1' "$1" 2>/dev/null
}

center_valid(){
  [[ -f "$1" ]] || return 1
  bash -n "$1" >/dev/null 2>&1
}

backend_valid(){
  [[ -f "$1" ]] || return 1
  python3 - "$1" >/dev/null 2>&1 <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
}

reboot_valid(){
  [[ -f "$1" ]] || return 1
  bash -n "$1" >/dev/null 2>&1
}

key_valid(){
  [[ -s "$1" ]] || return 1
  openssl pkey -pubin -in "$1" -noout >/dev/null 2>&1
}

same_key(){
  local a="$1" b="$2" da db rc=0
  da="$(mktemp)"; db="$(mktemp)"
  openssl pkey -pubin -in "$a" -outform DER -out "$da" >/dev/null 2>&1 || rc=1
  if [[ "$rc" -eq 0 ]]; then
    openssl pkey -pubin -in "$b" -outform DER -out "$db" >/dev/null 2>&1 || rc=1
  fi
  if [[ "$rc" -eq 0 ]]; then cmp -s "$da" "$db" || rc=1; fi
  rm -f "$da" "$db"
  return "$rc"
}

state=0
emit_state(){
  local name="$1" value="$2"
  printf '%s=%s\n' "$name" "$value"
  [[ "$value" == ok ]] || state=1
}

if helper_valid "$HELPER" && [[ -x "$HELPER" ]]; then emit_state UPDATE_HELPER_STATE ok
elif [[ ! -e "$HELPER" ]]; then emit_state UPDATE_HELPER_STATE missing
elif ! helper_valid "$HELPER"; then emit_state UPDATE_HELPER_STATE invalid
else emit_state UPDATE_HELPER_STATE nonexecutable
fi

if center_valid "$CENTER" && [[ -x "$CENTER" ]]; then emit_state UPDATE_CENTER_STATE ok
elif [[ ! -e "$CENTER" ]]; then emit_state UPDATE_CENTER_STATE missing
elif ! center_valid "$CENTER"; then emit_state UPDATE_CENTER_STATE invalid
else emit_state UPDATE_CENTER_STATE nonexecutable
fi

if backend_valid "$BACKEND"; then emit_state UPDATE_BACKEND_STATE ok
elif [[ ! -e "$BACKEND" ]]; then emit_state UPDATE_BACKEND_STATE missing
else emit_state UPDATE_BACKEND_STATE invalid
fi

if reboot_valid "$REBOOT" && [[ -x "$REBOOT" ]]; then emit_state REBOOT_HELPER_STATE ok
elif [[ ! -e "$REBOOT" ]]; then emit_state REBOOT_HELPER_STATE missing
elif ! reboot_valid "$REBOOT"; then emit_state REBOOT_HELPER_STATE invalid
else emit_state REBOOT_HELPER_STATE nonexecutable
fi

if [[ ! -e "$KEY" || ! -s "$KEY" ]]; then
  emit_state SIGNING_KEY_STATE missing
elif ! key_valid "$KEY"; then
  emit_state SIGNING_KEY_STATE invalid
elif key_valid "$KEY_SRC" && same_key "$KEY" "$KEY_SRC"; then
  emit_state SIGNING_KEY_STATE ok
else
  emit_state SIGNING_KEY_STATE mismatch
fi

if [[ "$mode" == --check ]]; then
  printf 'UPDATE_SELF_REPAIR_NEEDED=%s\n' "$state"
  exit "$state"
fi

[[ "$(id -u)" -eq 0 || -n "${MECHOS_REPAIR_TEST_MODE:-}" ]] || { echo 'Administrator privileges required.' >&2; exit 77; }
command -v openssl >/dev/null 2>&1 || { echo 'openssl is required for updater repair.' >&2; exit 70; }

helper_valid "$HELPER_SRC" || { echo 'Trusted rescue update helper is invalid.' >&2; exit 71; }
center_valid "$CENTER_SRC" || { echo 'Trusted rescue Update Center launcher is invalid.' >&2; exit 71; }
backend_valid "$BACKEND_SRC" || { echo 'Trusted rescue Update Center backend is invalid.' >&2; exit 71; }
reboot_valid "$REBOOT_SRC" || { echo 'Trusted rescue reboot helper is invalid.' >&2; exit 71; }
key_valid "$KEY_SRC" || { echo 'Trusted rescue signing key is invalid.' >&2; exit 71; }

if [[ -e "$KEY" && -s "$KEY" ]]; then
  key_valid "$KEY" || { echo 'Installed signing key is invalid; refusing silent replacement.' >&2; log 'refused invalid installed signing key'; exit 72; }
  same_key "$KEY" "$KEY_SRC" || { echo 'Installed signing key does not match the pinned MechOS key; refusing silent replacement.' >&2; log 'refused signing-key mismatch'; exit 72; }
else
  install -D -m0644 "$KEY_SRC" "$KEY"
  log 'restored missing update signing public key'
fi

if ! helper_valid "$HELPER" || [[ ! -x "$HELPER" ]]; then
  install -D -m0755 "$HELPER_SRC" "$HELPER"
  log 'restored update helper'
fi
if ! center_valid "$CENTER" || [[ ! -x "$CENTER" ]]; then
  install -D -m0755 "$CENTER_SRC" "$CENTER"
  log 'restored Update Center launcher'
fi
if ! backend_valid "$BACKEND"; then
  install -D -m0755 "$BACKEND_SRC" "$BACKEND"
  log 'restored Update Center backend'
fi
if ! reboot_valid "$REBOOT" || [[ ! -x "$REBOOT" ]]; then
  install -D -m0755 "$REBOOT_SRC" "$REBOOT"
  log 'restored reboot helper'
fi

helper_valid "$HELPER" && [[ -x "$HELPER" ]] || { echo 'Update helper repair verification failed.' >&2; exit 73; }
center_valid "$CENTER" && [[ -x "$CENTER" ]] || { echo 'Update Center repair verification failed.' >&2; exit 73; }
backend_valid "$BACKEND" || { echo 'Update Center backend repair verification failed.' >&2; exit 73; }
reboot_valid "$REBOOT" && [[ -x "$REBOOT" ]] || { echo 'Reboot helper repair verification failed.' >&2; exit 73; }
key_valid "$KEY" && same_key "$KEY" "$KEY_SRC" || { echo 'Signing key repair verification failed.' >&2; exit 73; }

printf 'UPDATE_SELF_REPAIR_OK=1\n'
log 'updater self-repair verified'
