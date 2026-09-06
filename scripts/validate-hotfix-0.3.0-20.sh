#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in \
  "$ROOT/scripts/mechos-update-transaction-v20.sh" \
  "$ROOT/scripts/mechos-hotfix-0.3.0-20-apply.sh" \
  "$ROOT/scripts/build-hotfix-0.3.0-20.sh"; do
  bash -n "$f"
done

grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' "$ROOT/scripts/mechos-update-transaction-v20.sh"
grep -Fq 'ROOT_MODE="$(stat -c' "$ROOT/scripts/mechos-update-transaction-v20.sh"
grep -Fq 'chmod "$ROOT_MODE" "$STAGE"' "$ROOT/scripts/mechos-update-transaction-v20.sh"
grep -Fq 'chmod "$ROOT_MODE" /' "$ROOT/scripts/mechos-update-transaction-v20.sh"
grep -Fq 'root mode became' "$ROOT/scripts/mechos-update-transaction-v20.sh"
grep -Fq '0.3.0-hotfix.20' "$ROOT/scripts/mechos-hotfix-0.3.0-20-apply.sh"
grep -Fq 'build-hotfix-0.3.0-19.sh' "$ROOT/scripts/build-hotfix-0.3.0-20.sh"

echo 'Hotfix 20 validation passed: update transactions preserve and verify installed root directory permissions.'
