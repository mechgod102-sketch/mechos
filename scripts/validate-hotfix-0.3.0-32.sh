#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX32_SINGLE_MECHSCOPE_OWNER_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="$ROOT/scripts/mechscope-session-v20.sh"
SAFE="$ROOT/scripts/mechos-mechscope-safe-launch-v31.sh"
AUTOSTART="$ROOT/scripts/mechos-session-autostart-v31.sh"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-32-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-32.sh"

bash -n "$SESSION" "$SAFE" "$AUTOSTART" "$APPLY" "$BUILD"
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V22_SINGLE_OWNER' "$SESSION"
grep -Fq 'LOCK_FILE="$STATE_DIR/mechscope-owner-v32.lock"' "$SESSION"
grep -Fq '/usr/bin/flock -n "$LOCK_FILE"' "$SESSION"
grep -Fq 'MECHOS_MECHSCOPE_SINGLE_OWNER_V32' "$SAFE"
grep -Fq 'duplicate launch suppressed' "$SAFE"
grep -Fq 'MECHOS_SESSION_SINGLE_OWNER_V32' "$AUTOSTART"
grep -Fq 'MECHOS_SESSION_SUPERVISED' "$AUTOSTART"
grep -Fq 'KDE fallback skipped' "$AUTOSTART"
grep -Fq 'MECHOS_HOTFIX32_SINGLE_MECHSCOPE_OWNER_V1' "$APPLY"
grep -Fq 'disabled duplicate graphical autostart' "$APPLY"
grep -Fq 'MECHOS_BUILD_HOTFIX32_SINGLE_MECHSCOPE_OWNER_V1' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.31-update.tar.zst' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.32'" "$BUILD"

# Prove the safe launcher serializes concurrent starts against the same raw
# Python target. The first launch holds the lock while sleeping; the second
# must be suppressed instead of starting another copy.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/state"
cat >"$tmp/mechscope.real" <<'PY'
from pathlib import Path
import os,time
p=Path(os.environ['HF32_COUNT'])
p.write_text(p.read_text() + 'start\n' if p.exists() else 'start\n')
time.sleep(2)
PY
chmod 0755 "$tmp/mechscope.real"
COUNT="$tmp/count"
HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" HF32_COUNT="$COUNT" MECHOS_MECHSCOPE_TARGET="$tmp/mechscope.real" bash "$SAFE" &
pid=$!
sleep 0.3
HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" HF32_COUNT="$COUNT" MECHOS_MECHSCOPE_TARGET="$tmp/mechscope.real" bash "$SAFE"
wait "$pid"
[ "$(grep -c '^start$' "$COUNT")" -eq 1 ] || { echo 'HF32 duplicate suppression failed' >&2; exit 1; }
grep -Fq 'duplicate launch suppressed' "$tmp/state/mechos/mechscope-safe-launch-v31.log"

printf 'Hotfix 32 single-owner MechScope regression validation passed.\n'
