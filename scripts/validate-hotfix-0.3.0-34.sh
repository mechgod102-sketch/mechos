#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX34_MECHSCOPE_RESPONSIVE_UI_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL="$ROOT/src/mechscope/mechscope_shell.py"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-34-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-34.sh"
RUNTIME="$ROOT/scripts/mechos-mechscope-source-runtime-v33.py"
SAFE="$ROOT/scripts/mechos-mechscope-safe-launch-v31.sh"
SESSION="$ROOT/scripts/mechscope-session-v20.sh"

python3 -m py_compile "$SHELL" "$RUNTIME"
bash -n "$APPLY" "$BUILD" "$SAFE" "$SESSION"

grep -Fq 'MECHOS_MECHSCOPE_RESPONSIVE_UI_V34' "$SHELL"
grep -Fq 'QLabel[role="normal"]{color:#f4f7ff}' "$SHELL"
grep -Fq 'QLabel[role="brand"]{color:#dce7f7}' "$SHELL"
grep -Fq 'QLabel[role="hero-title"]{color:#eef4ff}' "$SHELL"
grep -Fq 'QLabel[role="hero-copy"]{color:#a9b8cc}' "$SHELL"
grep -Fq 'class ElidedLabel' "$SHELL"
grep -Fq 'Qt.TextElideMode.ElideRight' "$SHELL"
grep -Fq 'QRect(1104,255,500,27)' "$SHELL"
grep -Fq 'QRect(1104,286,500,25)' "$SHELL"
grep -Fq 'MECHOS_QUICK_ACTION_SINGLE_LINE_V34' "$SHELL"
grep -Fq "self._quick_action(key,title,QRect(1110,y,500,41),11)" "$SHELL"
grep -Fq "self._label('›', arrow_rect" "$SHELL"
if grep -Fq "self._button(key,title,'›'" "$SHELL"; then
  echo 'Quick Actions regressed to two-line subtitle layout' >&2
  exit 1
fi
grep -Fq 'MECHOS_RESPONSIVE_RECENT_GAMES_V2' "$SHELL"
grep -Fq 'int(round(154 * sy))' "$SHELL"

# Verify the authored row geometry stays usable at the supported 16:9 sizes.
python3 - <<'PY'
BASE_W=1672
BASE_H=941
for width,height in ((1280,720),(1600,900),(1920,1080)):
    scale=min(width/BASE_W,height/BASE_H)
    action_h=41*scale
    action_w=500*scale
    gpu_w=500*scale
    font=11*scale
    assert action_h >= 30, (width,height,action_h)
    assert action_w >= 380, (width,height,action_w)
    assert gpu_w >= 380, (width,height,gpu_w)
    assert font >= 8, (width,height,font)
PY

# HF34 must remain visual-only on top of HF33's runtime/session ownership.
grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33' "$RUNTIME"
grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_ROUTE_V33' "$SAFE"
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V23_SOURCE_RUNTIME' "$SESSION"
grep -Fq 'MECHOS_HOTFIX34_MECHSCOPE_RESPONSIVE_UI_V1' "$APPLY"
grep -Fq 'MECHOS_BUILD_HOTFIX34_MECHSCOPE_RESPONSIVE_UI_V1' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.33-update.tar.zst' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.34-update.tar.zst' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.34'" "$BUILD"

printf 'Hotfix 34 MechScope responsive UI regression validation passed.\n'
