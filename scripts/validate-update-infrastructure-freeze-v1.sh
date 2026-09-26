#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_UPDATE_INFRASTRUCTURE_FREEZE_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n   "$ROOT/scripts/mechos-strip-updater-from-stage-v1.sh"   "$ROOT/scripts/validate-payload-only-hotfix-v1.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

safe_stage="$tmp/safe-stage"
mkdir -p \
  "$safe_stage/usr/local/bin" \
  "$safe_stage/usr/local/share/mechos/update-engine/slots/test" \
  "$safe_stage/usr/local/share/mechos/features"
printf '#!/bin/sh\n' >"$safe_stage/usr/local/bin/mechos-update-helper"
printf 'engine\n' >"$safe_stage/usr/local/share/mechos/update-engine/slots/test/core"
printf 'payload\n' >"$safe_stage/usr/local/share/mechos/features/example"

bash "$ROOT/scripts/mechos-strip-updater-from-stage-v1.sh" "$safe_stage" >/dev/null
test ! -e "$safe_stage/usr/local/bin/mechos-update-helper"
test ! -e "$safe_stage/usr/local/share/mechos/update-engine"
test -f "$safe_stage/usr/local/share/mechos/features/example"

safe_bundle="$tmp/safe.tar.zst"
tar --zstd -cpf "$safe_bundle" -C "$safe_stage" .
bash "$ROOT/scripts/validate-payload-only-hotfix-v1.sh" "$safe_bundle" >/dev/null

bad_stage="$tmp/bad-stage"
mkdir -p "$bad_stage/usr/local/bin"
printf '#!/bin/sh\n' >"$bad_stage/usr/local/bin/mechos-update-helper"
bad_bundle="$tmp/bad.tar.zst"
tar --zstd -cpf "$bad_bundle" -C "$bad_stage" .
if bash "$ROOT/scripts/validate-payload-only-hotfix-v1.sh" "$bad_bundle" >/dev/null 2>&1; then
  echo 'payload-only validator accepted a protected updater file' >&2
  exit 1
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re,sys
root=Path(sys.argv[1])

builders=[]
for p in sorted((root/'scripts').glob('build-hotfix-0.3.1-*.sh')):
    m=re.fullmatch(r'build-hotfix-0\.3\.1-(\d+)\.sh',p.name)
    if m and int(m.group(1)) >= 6:
        builders.append(p)

required_strip='mechos-strip-updater-from-stage-v1.sh'
required_validate='validate-payload-only-hotfix-v1.sh'
for p in builders:
    text=p.read_text(encoding='utf-8')
    if required_strip not in text:
        raise SystemExit(f'{p}: future hotfix must strip updater infrastructure')
    if required_validate not in text:
        raise SystemExit(f'{p}: future hotfix must validate payload-only archive')

publishers=[]
for p in sorted((root/'.github/workflows').glob('publish-hotfix-0.3.1-*.yml')):
    m=re.fullmatch(r'publish-hotfix-0\.3\.1-(\d+)\.yml',p.name)
    if m and int(m.group(1)) >= 6:
        publishers.append(p)

for p in publishers:
    text=p.read_text(encoding='utf-8')
    watched=[
        'mechos-update-helper',
        'mechos-update-center-reference',
        'mechos-update-transaction',
        'mechos-update-engine-switch',
        'mechos-update-self-repair',
        'mechos-powerctl-v1',
        'mechos-reboot-frozen-v1',
    ]
    for token in watched:
        if token in text:
            raise SystemExit(f'{p}: normal hotfix publisher must not watch updater source ({token})')
    if required_validate not in text:
        raise SystemExit(f'{p}: publisher must verify payload-only archive')

print(f'Update infrastructure freeze OK; checked {len(builders)} future builder(s), {len(publishers)} future publisher(s).')
PY
