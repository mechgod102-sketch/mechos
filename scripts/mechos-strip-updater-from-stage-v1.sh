#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_STRIP_UPDATER_FROM_HOTFIX_STAGE_V1

STAGE="${1:?usage: mechos-strip-updater-from-stage-v1.sh STAGE_DIR}"
[[ -d "$STAGE" ]] || { echo "hotfix stage missing: $STAGE" >&2; exit 2; }

# Normal MechOS feature/hardware hotfixes are payload-only. The update
# infrastructure is an independent system component and must not be changed as
# a side effect of a cumulative OS bundle.
rm -rf   "$STAGE/usr/local/share/mechos/update-engine"   "$STAGE/usr/local/share/mechos/update-recovery"

rm -f   "$STAGE/usr/local/bin/mechos-update-helper"   "$STAGE/usr/local/bin/mechos-update-center"   "$STAGE/usr/local/bin/mechos-reboot"   "$STAGE/usr/local/libexec/mechos-powerctl-v1"   "$STAGE/etc/mechos/update-signing-public.pem"

if [[ -d "$STAGE/usr/local/libexec" ]]; then
  find "$STAGE/usr/local/libexec" -maxdepth 1 -type f -name 'mechos-update-*' -delete
fi

for unit in   mechos-update-self-repair.service   mechos-hotfix-0.3.1-2.service   mechos-hotfix-0.3.1-3.service; do
  rm -f     "$STAGE/usr/lib/systemd/system/$unit"     "$STAGE/etc/systemd/system/multi-user.target.wants/$unit"
done

printf 'MECHOS_PAYLOAD_ONLY_UPDATER_STRIPPED=1\n'
