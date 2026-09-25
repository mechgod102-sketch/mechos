#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_HELPER_AB_LAUNCHER_V38
ENGINE=/usr/local/share/mechos/update-engine
RECOVERY=/usr/local/share/mechos/update-recovery/mechos-update-helper-v37.sh

for candidate in   "$ENGINE/current/mechos-update-helper-core"   "$ENGINE/previous/mechos-update-helper-core"   "$RECOVERY"; do
  [[ -f "$candidate" ]] || continue
  bash -n "$candidate" >/dev/null 2>&1 || continue
  exec /usr/bin/bash "$candidate" "$@"
done

echo 'MechOS Update Engine is unavailable. Run the Update Center self-repair tool.' >&2
exit 73
