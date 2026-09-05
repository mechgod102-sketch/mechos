#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_ROOT="${1:-/}"
GENERATOR="${MECHOS_STORE_GENERATOR:-/usr/local/libexec/mechos-reference-v5-store-layout.sh}"

[ -f "$GENERATOR" ] || { echo "[MechOS Unified Store v8] generator missing: $GENERATOR" >&2; exit 31; }
[ -d "$TARGET_ROOT" ] || { echo "[MechOS Unified Store v8] target root missing: $TARGET_ROOT" >&2; exit 32; }

FILE="$TARGET_ROOT/usr/local/bin/mechscope"
[ -f "$TARGET_ROOT/usr/local/bin/mechscope.real" ] && FILE="$TARGET_ROOT/usr/local/bin/mechscope.real"
[ -f "$FILE" ] || { echo "[MechOS Unified Store v8] MechScope owner missing: $FILE" >&2; exit 33; }

# The canonical generator is idempotent and normally exits when it sees its v5
# marker. For this final-authority pass we deliberately clear only that marker
# first so the whole UnifiedStore class is regenerated from the current source,
# rather than trusting a possibly partially modified installed copy.
python3 - "$FILE" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
text=p.read_text(encoding='utf-8')
text=text.replace('# MECHOS_REFERENCE_UNIFIED_STORE_V5', '# MECHOS_PREVIOUS_UNIFIED_STORE_V5')
p.write_text(text,encoding='utf-8')
PY

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
python3 - "$GENERATOR" "$TARGET_ROOT" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text(encoding='utf-8')
target=sys.argv[2].rstrip('/') or '/'
needle='ROOT="/workspace/archlive/airootfs"'
if needle not in src:
    raise SystemExit('[MechOS Unified Store v8] canonical v5 ROOT declaration not found')
root = target if target != '/' else ''
patched=src.replace(needle, f'ROOT="{root}"', 1)
Path(sys.argv[3]).write_text(patched,encoding='utf-8')
PY
chmod 0755 "$TMP"
bash "$TMP"

grep -Fq 'MECHOS_REFERENCE_UNIFIED_STORE_V5' "$FILE" || { echo "[MechOS Unified Store v8] v5 marker missing" >&2; exit 34; }
grep -Fq "('Lutris'" "$FILE" || grep -Fq '("Lutris"' "$FILE" || { echo "[MechOS Unified Store v8] Lutris source missing" >&2; exit 35; }
grep -Fq 'Return to MechScope' "$FILE" || { echo "[MechOS Unified Store v8] return control missing" >&2; exit 36; }

echo "[MechOS Unified Store v8] exact current v5 generator applied to ${TARGET_ROOT}"
