#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX_0312_UPDATE_SELF_REPAIR_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n   "$ROOT/scripts/mechos-update-self-repair-v0312.sh"   "$ROOT/scripts/mechos-update-center-rescue-launcher-v0312.sh"   "$ROOT/scripts/mechos-hotfix-0.3.1-2-apply.sh"   "$ROOT/scripts/build-hotfix-0.3.1-2.sh"   "$ROOT/scripts/mechos-update-transaction-v14.sh"
python3 -m py_compile "$ROOT/scripts/mechos-update-center-reference-v8.py"

grep -Fq 'MECHOS_UPDATE_SELF_REPAIR_V0312' "$ROOT/scripts/mechos-update-self-repair-v0312.sh"
grep -Fq 'attempt_self_repair' "$ROOT/scripts/mechos-update-center-reference-v8.py"
grep -Fq 'pkexec", REPAIR, "--repair"' "$ROOT/scripts/mechos-update-center-reference-v8.py"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14_0312_SELF_REPAIR_V1' "$ROOT/scripts/mechos-update-transaction-v14.sh"
grep -Fq 'update self-repair failed' "$ROOT/scripts/mechos-update-transaction-v14.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
recovery="$tmp/recovery"
mkdir -p "$recovery" "$tmp/bin" "$tmp/libexec" "$tmp/etc" "$tmp/log"
cp "$ROOT/scripts/mechos-update-helper-v37.sh" "$recovery/mechos-update-helper-v37.sh"
cp "$ROOT/scripts/mechos-update-center-rescue-launcher-v0312.sh" "$recovery/mechos-update-center"
cp "$ROOT/scripts/mechos-update-center-reference-v8.py" "$recovery/mechos-update-center-v8.py"
cp "$ROOT/scripts/mechos-reboot-v14.sh" "$recovery/mechos-reboot"
cp "$ROOT/updates/mechos-update-signing-public.pem" "$recovery/mechos-update-signing-public.pem"
chmod 0755 "$recovery/mechos-update-helper-v37.sh" "$recovery/mechos-update-center" "$recovery/mechos-update-center-v8.py" "$recovery/mechos-reboot"
chmod 0644 "$recovery/mechos-update-signing-public.pem"

export MECHOS_REPAIR_TEST_MODE=1
export MECHOS_REPAIR_RECOVERY="$recovery"
export MECHOS_REPAIR_HELPER="$tmp/bin/mechos-update-helper"
export MECHOS_REPAIR_CENTER="$tmp/bin/mechos-update-center"
export MECHOS_REPAIR_BACKEND="$tmp/libexec/mechos-update-center-v8.py"
export MECHOS_REPAIR_REBOOT="$tmp/bin/mechos-reboot"
export MECHOS_REPAIR_KEY="$tmp/etc/update-signing-public.pem"
export MECHOS_REPAIR_LOG="$tmp/log/self-repair.log"

# Missing critical files must be detected, then restored from trusted local copies.
if "$ROOT/scripts/mechos-update-self-repair-v0312.sh" --check; then
  echo 'self-repair check unexpectedly passed with missing files' >&2
  exit 1
fi
"$ROOT/scripts/mechos-update-self-repair-v0312.sh" --repair | grep -Fq 'UPDATE_SELF_REPAIR_OK=1'
"$ROOT/scripts/mechos-update-self-repair-v0312.sh" --check | grep -Fq 'UPDATE_SELF_REPAIR_NEEDED=0'

# Lost executable permission must be repaired.
chmod 0644 "$MECHOS_REPAIR_HELPER"
if "$ROOT/scripts/mechos-update-self-repair-v0312.sh" --check; then
  echo 'self-repair check unexpectedly passed with non-executable helper' >&2
  exit 1
fi
"$ROOT/scripts/mechos-update-self-repair-v0312.sh" --repair >/dev/null
test -x "$MECHOS_REPAIR_HELPER"

# Missing pinned public key must be restored.
rm -f "$MECHOS_REPAIR_KEY"
"$ROOT/scripts/mechos-update-self-repair-v0312.sh" --repair >/dev/null
cmp -s "$MECHOS_REPAIR_KEY" "$recovery/mechos-update-signing-public.pem"

# A different valid public key is suspicious and must never be silently replaced.
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$tmp/other-private.pem" >/dev/null 2>&1
openssl pkey -in "$tmp/other-private.pem" -pubout -out "$MECHOS_REPAIR_KEY" >/dev/null 2>&1
cp "$MECHOS_REPAIR_KEY" "$tmp/mismatch-before.pem"
if "$ROOT/scripts/mechos-update-self-repair-v0312.sh" --repair >/dev/null 2>&1; then
  echo 'self-repair incorrectly accepted a mismatched signing key' >&2
  exit 1
fi
cmp -s "$MECHOS_REPAIR_KEY" "$tmp/mismatch-before.pem"

echo 'MechOS 0.3.1 Hotfix 2 Update Center self-repair contracts validated.'
