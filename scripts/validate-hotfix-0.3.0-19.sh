#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in \
  scripts/mechos-update-helper-v19.sh \
  scripts/mechos-update-rescue-v19.sh \
  scripts/mechos-mode-launch-v19.sh \
  scripts/mechos-shell-route-v19.sh \
  scripts/mechscope-session-v19.sh \
  scripts/mechos-hotfix-0.3.0-19-apply.sh \
  scripts/build-hotfix-0.3.0-19.sh; do
  bash -n "$ROOT/$f"
done

grep -Fq 'MECHOS_UPDATE_HELPER_V19' "$ROOT/scripts/mechos-update-helper-v19.sh"
grep -Fq 'MECHOS_UPDATE_RESCUE_V19' "$ROOT/scripts/mechos-update-rescue-v19.sh"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$ROOT/scripts/mechos-update-transaction-v14.sh"
grep -Fq 'stage/usr/local/libexec/mechos-update-transaction-v14' "$ROOT/scripts/mechos-update-helper-v19.sh"
grep -Fq 'STAGE/usr/local/libexec/mechos-update-transaction-v14' "$ROOT/scripts/mechos-update-rescue-v19.sh"
grep -Fq 'MECHOS_MODE_LAUNCH_V19' "$ROOT/scripts/mechos-mode-launch-v19.sh"
grep -Fq 'MECHOS_SHELL_ROUTE_V19' "$ROOT/scripts/mechos-shell-route-v19.sh"
grep -Fq 'exec "$CREATOR" creator' "$ROOT/scripts/mechos-mode-launch-v19.sh"
grep -Fq 'exec "$CREATOR" creator' "$ROOT/scripts/mechos-shell-route-v19.sh"
! grep -Fq 'nohup "$BASE" gaming' "$ROOT/scripts/mechos-mode-launch-v19.sh"

grep -Fq 'MECHOS_MECHSCOPE_SESSION_V19' "$ROOT/scripts/mechscope-session-v19.sh"
grep -Fq 'MECHOS_ENABLE_VRR' "$ROOT/scripts/mechscope-session-v19.sh"
grep -Fq 'starting MechScope inside Plasma fallback' "$ROOT/scripts/mechscope-session-v19.sh"
! grep -Fq 'MECHOS_DISABLE_VRR' "$ROOT/scripts/mechscope-session-v19.sh"

grep -Fq 'build-hotfix-0.3.0-18.sh' "$ROOT/scripts/build-hotfix-0.3.0-19.sh"
grep -Fq 'mechos-update-rescue' "$ROOT/scripts/build-hotfix-0.3.0-19.sh"
grep -Fq 'mechos-creator-launch-v19' "$ROOT/scripts/build-hotfix-0.3.0-19.sh"
grep -Fq 'mechscope-session-v19.sh' "$ROOT/scripts/build-hotfix-0.3.0-19.sh"
grep -Fq '0.3.0-hotfix.19' "$ROOT/scripts/mechos-hotfix-0.3.0-19-apply.sh"

# Regression gates: keep the public updater trio and the self-contained engine.
! grep -Eq '^[[:space:]]*rsync[[:space:]]' "$ROOT/scripts/mechos-update-transaction-v14.sh"
grep -Fq 'mechos-update-center' "$ROOT/scripts/build-hotfix-0.3.0-19.sh"
grep -Fq 'mechos-update-helper' "$ROOT/scripts/build-hotfix-0.3.0-19.sh"
grep -Fq 'mechos-reboot' "$ROOT/scripts/build-hotfix-0.3.0-19.sh"

echo 'Hotfix 19 validation passed: updater bootstrap recovery, Creator-first routing and hardware MechScope fallback are enforced.'
