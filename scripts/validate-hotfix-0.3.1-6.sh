#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX_0316_MECHSCOPE_PLASMA_FOREGROUND_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n   "$ROOT/scripts/mechscope-session-v20.sh"   "$ROOT/scripts/mechos-mechscope-plasma-fallback-v25.sh"   "$ROOT/scripts/build-hotfix-0.3.1-6.sh"
python3 -m py_compile "$ROOT/scripts/mechos-mechscope-source-runtime-v33.py"

grep -Fq 'MECHOS_MECHSCOPE_SESSION_V25_PLASMA_READY_HANDOFF'   "$ROOT/scripts/mechscope-session-v20.sh"
grep -Fq 'plasma-fallback-request-v25'   "$ROOT/scripts/mechscope-session-v20.sh"
grep -Fq 'Plasma autostart will own the visible launch'   "$ROOT/scripts/mechscope-session-v20.sh"
! grep -Fq 'plasma_mechscope_supervisor &'   "$ROOT/scripts/mechscope-session-v20.sh"

grep -Fq 'MECHOS_MECHSCOPE_PLASMA_FALLBACK_V25'   "$ROOT/scripts/mechos-mechscope-plasma-fallback-v25.sh"
grep -Fq 'MECHOS_FALLBACK_TEST_MODE'   "$ROOT/scripts/mechos-mechscope-plasma-fallback-v25.sh"
grep -Fq 'MECHOS_MECHSCOPE_FOREGROUND_PRESENT_V34'   "$ROOT/scripts/mechos-mechscope-source-runtime-v33.py"
grep -Fq 'handle.requestActivate()'   "$ROOT/scripts/mechos-mechscope-source-runtime-v33.py"
grep -Fq 'startup-5000ms' "$ROOT/scripts/mechos-mechscope-source-runtime-v33.py" ||   grep -Fq '(250, 750, 1500, 3000, 5000)' "$ROOT/scripts/mechos-mechscope-source-runtime-v33.py"

# Exercise the Plasma-side supervisor without a graphical CI session.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
state="$tmp/state"
mkdir -p "$state"
mode_file="$tmp/session-mode"
request="$state/request"
runtime="$tmp/runtime.py"
launched="$tmp/launched"
printf 'gaming\n' >"$mode_file"
printf 'requested\n' >"$request"

cat >"$runtime" <<'PY'
#!/usr/bin/env python3
import os
from pathlib import Path
Path(os.environ['MECHOS_FALLBACK_TEST_LAUNCHED']).write_text('1\n',encoding='utf-8')
Path(os.environ['MECHOS_FALLBACK_MODE_FILE']).write_text('desktop\n',encoding='utf-8')
PY
chmod 0755 "$runtime"

MECHOS_FALLBACK_TEST_MODE=1 MECHOS_FALLBACK_MODE_FILE="$mode_file" MECHOS_FALLBACK_STATE_DIR="$state" MECHOS_FALLBACK_REQUEST="$request" MECHOS_FALLBACK_LOG_FILE="$state/log" MECHOS_FALLBACK_CRASH_MARKER="$state/crash" MECHOS_FALLBACK_LOCK_FILE="$state/lock" MECHOS_FALLBACK_RUNTIME="$runtime" MECHOS_FALLBACK_TEST_LAUNCHED="$launched"   bash "$ROOT/scripts/mechos-mechscope-plasma-fallback-v25.sh"

test -s "$launched"
test "$(tr -d '\r\n' <"$mode_file")" = desktop
test ! -e "$request"
grep -Fq 'after intentional mode transition' "$state/log"

# Hotfix 6 builder is required to strip updater infrastructure and validate the
# finished payload-only archive.
grep -Fq 'mechos-strip-updater-from-stage-v1.sh'   "$ROOT/scripts/build-hotfix-0.3.1-6.sh"
grep -Fq 'validate-payload-only-hotfix-v1.sh'   "$ROOT/scripts/build-hotfix-0.3.1-6.sh"

echo 'MechOS 0.3.1 Hotfix 6 Plasma-ready foreground contracts validated.'
