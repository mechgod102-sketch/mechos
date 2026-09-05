#!/usr/bin/env bash
set -Eeuo pipefail

BUILD=scripts/mechos-build125-final-surfaces.sh
STAGE=scripts/mechos-reference-v5-postinstall-stage.sh
FINAL=scripts/mechos-finalize-install-payload.sh

fail(){ printf '[validate-build125-final-surface-scope] ERROR: %s\n' "$*" >&2; exit 1; }

for f in "$BUILD" "$STAGE" "$FINAL"; do
  [ -f "$f" ] || fail "missing $f"
  bash -n "$f"
done

grep -Fq 'Creator Mode and Quick Actions are intentionally post-install-only' "$STAGE" || fail 'post-install staging contract is missing'
grep -Fq '[ ! -e "$ROOT/usr/local/bin/mechos-quick-actions" ]' "$FINAL" || fail 'final payload no longer guards Quick Actions from leaking into Live'
grep -Fq '[ ! -e "$ROOT/usr/local/bin/mechos-creator-mode" ]' "$FINAL" || fail 'final payload no longer guards Creator Mode from leaking into Live'

grep -Fq 'patch_tree "$ROOT" live' "$BUILD" || fail 'Live tree is not explicitly patched with Live scope'
grep -Fq 'patch_tree "$tmp" installed' "$BUILD" || fail 'installed payload is not explicitly patched with installed scope'
grep -Fq 'if [ "$scope" = "installed" ]; then' "$BUILD" || fail 'installed-only surface guard missing'
grep -Fq 'Quick Actions owner missing from installed payload' "$BUILD" || fail 'Quick Actions owner is not constrained to installed payload'
grep -Fq 'Creator owner missing from installed payload' "$BUILD" || fail 'Creator owner is not constrained to installed payload'
grep -Fq 'post-install-only Quick Actions leaked into Live tree' "$BUILD" || fail 'Live Quick Actions leak guard missing'
grep -Fq 'post-install-only Creator Mode leaked into Live tree' "$BUILD" || fail 'Live Creator Mode leak guard missing'
grep -Fq 'MECHOS_VISUAL_SURFACES_V9_UNIFIED_STORE' "$BUILD" || fail 'v9 Unified Store final authority missing'
grep -Fq 'MECHOS_QUICK_ACTIONS_VISUAL_V9' "$BUILD" || fail 'v9 Quick Actions final authority missing'

python3 - "$BUILD" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
branch=text.find('if [ "$scope" = "installed" ]; then')
if branch < 0:
    raise SystemExit('installed scope branch missing')
pre=text[:branch]
for needle in ('mechos-quick-actions QuickActions','mechos-creator-mode Creator'):
    if needle in pre:
        raise SystemExit(f'post-install owner lookup became unconditional: {needle}')
PY

echo '[validate-build125-final-surface-scope] OK: Live excludes post-install-only Creator/Quick Actions while installed payload receives v9 visual owners'
