#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_UPDATE_INFRASTRUCTURE_FREEZE_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n   "$ROOT/scripts/mechos-strip-updater-from-stage-v1.sh"   "$ROOT/scripts/validate-payload-only-hotfix-v1.sh"

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
    ]
    for token in watched:
        if token in text:
            raise SystemExit(f'{p}: normal hotfix publisher must not watch updater source ({token})')
    if required_validate not in text:
        raise SystemExit(f'{p}: publisher must verify payload-only archive')

print(f'Update infrastructure freeze OK; checked {len(builders)} future builder(s), {len(publishers)} future publisher(s).')
PY
