#!/usr/bin/env bash
set -euo pipefail

INTEGRATION="scripts/mechos-radarai-performance-integration.sh"
PATCHER="scripts/patch-mechos-current.py"

fail() {
  printf '[RadarAI Performance validation] ERROR: %s\n' "$*" >&2
  exit 1
}

[ -f "$INTEGRATION" ] || fail "missing $INTEGRATION"
[ -f "$PATCHER" ] || fail "missing $PATCHER"

bash -n "$INTEGRATION"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$PATCHER"

grep -Fq 'io.mechgod.RadarAI' "$INTEGRATION"   || fail "RadarAI Flatpak app ID is missing"
grep -Fq 'flatpak", "info", scope, app_id' "$INTEGRATION"   || fail "user/system Flatpak detection is missing"
grep -Fq 'flatpak", "run", RADARAI_APP_ID' "$INTEGRATION"   || fail "Flatpak launch command is missing"
grep -Fq 'self.radarai_timer.start(3000)' "$INTEGRATION"   || fail "automatic installed-state refresh is missing"
grep -Fq 'patch_performance_center "$ROOT"' "$INTEGRATION"   || fail "Live Performance Center patch is missing"
grep -Fq 'tar --zstd -xf "$ARCHIVE"' "$INTEGRATION"   || fail "installed-system payload patch is missing"
grep -Fq 'mechos-radarai-performance-integration.sh final' "$PATCHER"   || fail "cumulative patcher does not call RadarAI integration"

printf '[RadarAI Performance validation] passed\n'
