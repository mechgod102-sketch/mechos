#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_PAYLOAD_ONLY_HOTFIX_V1

BUNDLE="${1:?usage: validate-payload-only-hotfix-v1.sh BUNDLE.tar.zst}"
[[ -s "$BUNDLE" ]] || { echo "bundle missing: $BUNDLE" >&2; exit 2; }

contents="$(tar --zstd -tf "$BUNDLE")"

blocked_exact=(
  './usr/local/bin/mechos-update-helper'
  './usr/local/bin/mechos-update-center'
  './usr/local/bin/mechos-reboot'
  './etc/mechos/update-signing-public.pem'
  './usr/lib/systemd/system/mechos-update-self-repair.service'
  './etc/systemd/system/multi-user.target.wants/mechos-update-self-repair.service'
)

for path in "${blocked_exact[@]}"; do
  if grep -Fxq "$path" <<<"$contents"; then
    echo "PAYLOAD-ONLY POLICY VIOLATION: normal hotfix contains protected updater file: $path" >&2
    exit 80
  fi
done

blocked_prefix=(
  './usr/local/share/mechos/update-engine/'
  './usr/local/share/mechos/update-recovery/'
)

for prefix in "${blocked_prefix[@]}"; do
  if grep -Fq "$prefix" <<<"$contents"; then
    echo "PAYLOAD-ONLY POLICY VIOLATION: normal hotfix contains protected updater tree: $prefix" >&2
    exit 80
  fi
done

if grep -E '^\./usr/local/libexec/mechos-update-[^/]+$' <<<"$contents" >/dev/null; then
  echo 'PAYLOAD-ONLY POLICY VIOLATION: normal hotfix contains protected updater libexec file.' >&2
  grep -E '^\./usr/local/libexec/mechos-update-[^/]+$' <<<"$contents" >&2 || true
  exit 80
fi

printf 'MECHOS_PAYLOAD_ONLY_POLICY_OK=1\n'
