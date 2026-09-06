#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in \
  scripts/mechos-pacman-health-v18.sh \
  scripts/mechos-update-helper-v18.sh \
  scripts/mechos-hotfix-0.3.0-18-apply.sh \
  scripts/build-hotfix-0.3.0-18.sh; do
  bash -n "$ROOT/$f"
done

grep -Fq 'MECHOS_PACMAN_HEALTH_V18' "$ROOT/scripts/mechos-pacman-health-v18.sh"
grep -Fq "download-*" "$ROOT/scripts/mechos-pacman-health-v18.sh"
grep -Fq 'DownloadUser' "$ROOT/scripts/mechos-pacman-health-v18.sh"
grep -Fq 'MECHOS_UPDATE_HELPER_V18' "$ROOT/scripts/mechos-update-helper-v18.sh"
grep -Fq 'MECHOS_UPDATE_HELPER_V14' "$ROOT/scripts/mechos-update-helper-v18.sh"
grep -Fq 'PACKAGE_UPDATE_FAILED=1' "$ROOT/scripts/mechos-update-helper-v18.sh"
grep -Fq 'MECHOS_CORE_UPDATE_STAGED=1' "$ROOT/scripts/mechos-update-helper-v18.sh"
grep -Fq 'transaction committed for ' "$ROOT/scripts/mechos-update-helper-v18.sh"
grep -Fq '0.3.0-hotfix.18' "$ROOT/scripts/mechos-hotfix-0.3.0-18-apply.sh"
grep -Fq 'Hotfix 18' "$ROOT/scripts/build-hotfix-0.3.0-18.sh"

# Regression gates: Hotfix 17 must remain rsync-free and Hotfix 18 must not
# permanently disable pacman's download sandbox as a workaround.
! grep -Eq '^[[:space:]]*rsync[[:space:]]' "$ROOT/scripts/mechos-update-transaction-v14.sh"
! grep -Eq 'sed .*DownloadUser|DisableSandbox' "$ROOT/scripts/mechos-pacman-health-v18.sh" "$ROOT/scripts/mechos-update-helper-v18.sh"

echo 'Hotfix 18 package-update reliability validation passed.'
