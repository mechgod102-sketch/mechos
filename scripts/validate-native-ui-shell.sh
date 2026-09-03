#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_SRC="$ROOT/src/mechscope/mechscope_shell.py"
INTEGRATION="$ROOT/scripts/mechos-native-ui-shell-integration.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"

fail(){ echo "[validate-native-ui-shell] ERROR: $*" >&2; exit 1; }

[ -f "$SHELL_SRC" ] || fail "source-owned MechScope shell missing"
[ -f "$INTEGRATION" ] || fail "native UI integration missing"
[ -f "$PATCHER" ] || fail "reference-v5 patcher missing"

python3 -m py_compile "$SHELL_SRC" || fail "MechScope shell Python syntax failed"
bash -n "$INTEGRATION" || fail "native UI integration shell syntax failed"

grep -Fq 'BASE_W = 1920' "$SHELL_SRC" || fail "authored 1920px design canvas missing"
grep -Fq 'BASE_H = 1080' "$SHELL_SRC" || fail "authored 1080px design canvas missing"
grep -Fq 'setGeometry' "$SHELL_SRC" || fail "explicit geometry scaling missing"
# Reject actual nested layout construction/imports. Documentation may mention
# the old layout classes while explaining why they were removed.
if grep -Eq '(^|[^A-Za-z0-9_])Q(HBox|VBox|Grid)Layout[[:space:]]*\(' "$SHELL_SRC"; then
  fail "source-owned MechScope shell regressed to nested Qt layout construction"
fi
if grep -Eq '^from PyQt6\.QtWidgets import .*Q(HBox|VBox|Grid)Layout' "$SHELL_SRC"; then
  fail "source-owned MechScope shell imports nested Qt layouts"
fi

grep -Fq 'MECHOS_SOURCE_OWNED_SHELL_V1' "$INTEGRATION" || fail "runtime source-shell marker missing"
grep -Fq 'MechScopeShell' "$INTEGRATION" || fail "runtime does not install MechScopeShell"

grep -Fq 'mechos-native-ui-shell-integration.sh' "$PATCHER" || fail "source-owned shell is not wired as final Reference v5 authority"

echo '[validate-native-ui-shell] OK: source-owned fixed-composition MechScope shell is wired and validated'
