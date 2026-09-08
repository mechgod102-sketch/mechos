#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX31_PUBLIC_MECHSCOPE_PYTHON_WRAPPER_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFE="$ROOT/scripts/mechos-mechscope-safe-launch-v31.sh"
AUTOSTART="$ROOT/scripts/mechos-session-autostart-v31.sh"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-31-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-31.sh"
TUTORIAL_GUARD="$ROOT/scripts/mechos-tutorial-postinstall-guard.sh"

bash -n "$SAFE" "$AUTOSTART" "$APPLY" "$BUILD" "$TUTORIAL_GUARD"

grep -Fq 'MECHOS_MECHSCOPE_SAFE_LAUNCH_V31' "$SAFE"
grep -Fq 'is_python_target' "$SAFE"
grep -Fq 'python_source_check' "$SAFE"
grep -Fq 'exec /usr/bin/python3 "$target" "$@"' "$SAFE"
grep -Fq 'MECHOS_SESSION_AUTOSTART_V31' "$AUTOSTART"
grep -Fq 'mechos-mechscope-safe-launch-v31' "$AUTOSTART"
! grep -Fq 'nohup /usr/local/bin/mechscope ' "$AUTOSTART"
grep -Fq 'MECHOS_HOTFIX31_PUBLIC_MECHSCOPE_PYTHON_WRAPPER_V1' "$APPLY"
grep -Fq 'MECHOS_TUTORIAL_PYTHON_SAFE_V31' "$APPLY"
grep -Fq 't=t.replace(old,safe)' "$APPLY"
grep -Fq 'exec "$REAL" "$@"' "$APPLY"
grep -Fq 'MECHOS_TUTORIAL_PYTHON_SAFE_V31' "$TUTORIAL_GUARD"
grep -Fq 'mechos-mechscope-safe-launch-v31' "$TUTORIAL_GUARD"
grep -Fq 'MECHOS_BUILD_HOTFIX31_PUBLIC_MECHSCOPE_PYTHON_WRAPPER_V1' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.30-update.tar.zst' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.31'" "$BUILD"

# Reproduce the field condition exactly: raw Python source, no shebang and an
# executable bit that must not cause Bash to interpret its import statements.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"
cat >"$tmp/mechscope.real" <<'PY'
from pathlib import Path
print('HF31_RAW_PYTHON_OK')
PY
chmod 0755 "$tmp/mechscope.real"
out="$(HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" MECHOS_MECHSCOPE_TARGET="$tmp/mechscope.real" bash "$SAFE")"
[ "$out" = 'HF31_RAW_PYTHON_OK' ] || { echo "safe-launch raw Python test failed: $out" >&2; exit 1; }
grep -Fq 'interpreter=/usr/bin/python3' "$tmp/state/mechos/mechscope-safe-launch-v31.log"

printf 'Hotfix 31 public MechScope Python-wrapper regression validation passed.\n'
