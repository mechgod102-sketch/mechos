#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOTFIX="$ROOT/scripts/mechos-installed-mechscope-launch-hotfix.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
SESSION="$ROOT/overlay/rootfs/usr/share/wayland-sessions/mechscope.desktop"
WRAPPER="$ROOT/overlay/rootfs/usr/local/bin/mechscope-session"
OOBE="$ROOT/scripts/mechos-oobe-integration.sh"

fail(){ echo "[validate-installed-mechscope-launch] ERROR: $*" >&2; exit 1; }

[ -f "$HOTFIX" ] || fail "installed MechScope launch hotfix missing"
[ -f "$SESSION" ] || fail "mechscope.desktop session missing"
[ -f "$WRAPPER" ] || fail "base mechscope-session missing"
[ -f "$OOBE" ] || fail "OOBE integration missing"

bash -n "$HOTFIX" || fail "installed MechScope launch hotfix syntax failed"
python3 -m py_compile "$PATCHER" || fail "reference-v5 patcher syntax failed"

grep -Fq 'Exec=/usr/local/bin/mechscope-session' "$SESSION" || fail "MechScope session does not call mechscope-session"

# The generated OOBE has historically used more than one gaming-session name.
# The final authority must normalize any Session=<name>.desktop assignment to
# the only shipped MechScope session instead of depending on one legacy string.
grep -Fq 're.subn(' "$HOTFIX" || fail "robust OOBE SDDM normalization missing"
grep -Fq "r'Session=[A-Za-z0-9_.-]+\\.desktop'" "$HOTFIX" || fail "generic SDDM session matcher missing"
grep -Fq "'Session=mechscope.desktop'" "$HOTFIX" || fail "MechScope SDDM target missing"
grep -Fq 'OOBE SDDM Session assignment missing' "$HOTFIX" || fail "missing-session diagnostic guard missing"

grep -Fq 'MECHOS_FORCE_INITIAL_GAMING_MODE_V1' "$HOTFIX" || fail "initial Gaming Mode ownership missing"
grep -Fq 'systemd-detect-virt' "$HOTFIX" || fail "VM detection missing from installed session wrapper"
grep -Fq 'bypassing Gamescope and starting MechScope through Plasma' "$HOTFIX" || fail "VM Gamescope bypass missing"
grep -Fq 'Gamescope exited with %s; retrying MechScope through Plasma' "$HOTFIX" || fail "Gamescope failure fallback missing"
grep -Fq 'start_plasma_mechscope' "$HOTFIX" || fail "direct MechScope Plasma fallback missing"
grep -Fq 'QT_OPENGL=software' "$HOTFIX" || fail "VM software Qt path missing"
grep -Fq 'mechscope-session.log' "$HOTFIX" || fail "installed session logging missing"

grep -Fq 'mechos-installed-mechscope-launch-hotfix.sh' "$PATCHER" || fail "installed MechScope hotfix not wired into final build"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
items=[
    'mechos-source-owned-system-ui.sh',
    'mechos-installed-mechscope-launch-hotfix.sh',
    'mechos-reference-splash-integration.sh',
    'mechos-reference-v5-postinstall-stage.sh commit',
    'mechos-finalize-install-payload.sh final',
]
pos=[text.find(x) for x in items]
if any(p < 0 for p in pos):
    raise SystemExit('[validate-installed-mechscope-launch] final launch build stages incomplete')
if pos != sorted(pos):
    raise SystemExit('[validate-installed-mechscope-launch] installed launch hotfix is in the wrong final build order')
PY

echo '[validate-installed-mechscope-launch] OK: installed SDDM normalization, Gaming Mode state, VM bypass and Gamescope failure fallback are enforced'
