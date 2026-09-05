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

# Creator Mode and Quick Actions are intentionally not Live applications.
grep -Fq 'Creator Mode and Quick Actions are intentionally post-install-only' "$STAGE" \
  || fail 'post-install staging contract is missing'
grep -Fq '[ ! -e "$ROOT/usr/local/bin/mechos-quick-actions" ]' "$FINAL" \
  || fail 'final payload no longer guards Quick Actions from leaking into Live'
grep -Fq '[ ! -e "$ROOT/usr/local/bin/mechos-creator-mode" ]' "$FINAL" \
  || fail 'final payload no longer guards Creator Mode from leaking into Live'

# The absolute-last Build 125/128 surface pass must respect that split. Build
# 127 failed because it ran the installed-only owner checks against Live.
grep -Fq '# MECHOS_BUILD128_POSTINSTALL_SCOPE_V1' "$BUILD" \
  || fail 'post-install scope marker missing from final surface pass'
grep -Fq 'patch_tree "$ROOT" live' "$BUILD" \
  || fail 'Live tree is not explicitly patched with Live scope'
grep -Fq 'patch_tree "$tmp" installed' "$BUILD" \
  || fail 'installed payload is not explicitly patched with installed scope'
grep -Fq 'if [ "$scope" = "installed" ]; then' "$BUILD" \
  || fail 'installed-only surface guard missing'
grep -Fq 'Quick Actions owner missing from installed payload' "$BUILD" \
  || fail 'Quick Actions owner is not constrained to the installed payload'
grep -Fq 'Creator owner missing from installed payload' "$BUILD" \
  || fail 'Creator owner is not constrained to the installed payload'
grep -Fq 'post-install-only Quick Actions leaked into Live tree' "$BUILD" \
  || fail 'Live Quick Actions leak guard missing'
grep -Fq 'post-install-only Creator Mode leaked into Live tree' "$BUILD" \
  || fail 'Live Creator Mode leak guard missing'

# Prevent the exact Build 127 regression from being reintroduced by an
# unconditional owner lookup in patch_tree before the installed-scope branch.
python3 - "$BUILD" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding='utf-8')
marker = '# MECHOS_BUILD128_POSTINSTALL_SCOPE_V1'
pos = text.find(marker)
if pos < 0:
    raise SystemExit('scope marker missing')
pre = text[:pos]
if 'quick="$(resolve_owner "$tree" mechos-quick-actions QuickActions)"' in pre:
    raise SystemExit('Quick Actions owner lookup became unconditional before installed scope')
if 'creator="$(resolve_owner "$tree" mechos-creator-mode Creator)"' in pre:
    raise SystemExit('Creator owner lookup became unconditional before installed scope')
PY

echo '[validate-build125-final-surface-scope] OK: Live excludes post-install-only Creator/Quick Actions while installed payload receives their exact final owners'
