#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_BOOTSTRAP_REPAIR_V0312

BASE_URL="https://raw.githubusercontent.com/mechgod102-sketch/mechos/main"
EXPECTED_KEY_FP="03ae056eb65a505b8239b8b123b6437eec3afc906b517ff2a3d8e08607fe4391"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 2; }; }
need curl
need openssl
need sha256sum
need bash
need python3

if [[ "$(id -u)" -ne 0 ]]; then
  if command -v pkexec >/dev/null 2>&1; then
    exec pkexec /usr/bin/bash "$0" "$@"
  elif command -v sudo >/dev/null 2>&1; then
    exec sudo /usr/bin/bash "$0" "$@"
  else
    echo "Administrator privileges are required." >&2
    exit 77
  fi
fi

fetch(){
  local src="$1" dst="$2"
  curl -fL --retry 3 --connect-timeout 10 -H 'Cache-Control: no-cache'     "$BASE_URL/$src" -o "$dst"
}

echo "Restoring MechOS Update Center critical files..."

fetch "scripts/mechos-update-helper-v37.sh" "$TMP/mechos-update-helper"
fetch "scripts/mechos-update-center-reference-v8.py" "$TMP/mechos-update-center-v8.py"
fetch "scripts/mechos-update-center-rescue-launcher-v0312.sh" "$TMP/mechos-update-center"
fetch "scripts/mechos-reboot-v14.sh" "$TMP/mechos-reboot"
fetch "scripts/mechos-update-self-repair-v0312.sh" "$TMP/mechos-update-self-repair-v0312"
fetch "updates/mechos-update-signing-public.pem" "$TMP/mechos-update-signing-public.pem"

bash -n "$TMP/mechos-update-helper"
bash -n "$TMP/mechos-update-center"
bash -n "$TMP/mechos-reboot"
bash -n "$TMP/mechos-update-self-repair-v0312"
python3 - "$TMP/mechos-update-center-v8.py" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY

grep -Fq 'MECHOS_UPDATE_HELPER_V37_SIGNED_MANIFEST_V1' "$TMP/mechos-update-helper"
grep -Fq 'MECHOS_UPDATE_SELF_REPAIR_V0312' "$TMP/mechos-update-self-repair-v0312"

openssl pkey -pubin -in "$TMP/mechos-update-signing-public.pem" -outform DER   | sha256sum | awk '{print $1}' >"$TMP/key.fp"
actual="$(cat "$TMP/key.fp")"
[[ "$actual" == "$EXPECTED_KEY_FP" ]] || {
  echo "Pinned MechOS signing-key fingerprint mismatch." >&2
  echo "Expected: $EXPECTED_KEY_FP" >&2
  echo "Actual:   $actual" >&2
  exit 78
}

install -D -m0755 "$TMP/mechos-update-helper" /usr/local/bin/mechos-update-helper
install -D -m0755 "$TMP/mechos-update-center" /usr/local/bin/mechos-update-center
install -D -m0755 "$TMP/mechos-update-center-v8.py" /usr/local/libexec/mechos-update-center-v8.py
install -D -m0755 "$TMP/mechos-reboot" /usr/local/bin/mechos-reboot
install -D -m0755 "$TMP/mechos-update-self-repair-v0312" /usr/local/libexec/mechos-update-self-repair-v0312
install -D -m0644 "$TMP/mechos-update-signing-public.pem" /etc/mechos/update-signing-public.pem

/usr/local/bin/mechos-update-helper selftest
/usr/local/bin/mechos-update-helper status

echo
echo "MECHOS_UPDATE_BOOTSTRAP_REPAIR_OK=1"
echo "Update Center helper restored. Reopen Update Center and install the offered hotfix."
