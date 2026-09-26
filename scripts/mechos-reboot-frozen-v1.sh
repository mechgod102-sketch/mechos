#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_REBOOT_FROZEN_V1

POWERCTL=/usr/local/libexec/mechos-powerctl-v1
if [[ ! -x "$POWERCTL" ]]; then
  echo "MechOS frozen power authority is missing: $POWERCTL" >&2
  exit 73
fi
exec "$POWERCTL" reboot
