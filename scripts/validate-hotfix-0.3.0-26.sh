#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX26_OOBE_LAUNCHER_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/scripts/mechos-oobe-start-v26.sh"
bash -n "$ROOT/scripts/mechos-hotfix-0.3.0-26-apply.sh"
bash -n "$ROOT/scripts/build-hotfix-0.3.0-26.sh"

grep -Fq 'MECHOS_OOBE_START_V26' "$ROOT/scripts/mechos-oobe-start-v26.sh"
grep -Fq 'systemctl --user show-environment' "$ROOT/scripts/mechos-oobe-start-v26.sh"
grep -Fq 'XDG_RUNTIME_DIR' "$ROOT/scripts/mechos-oobe-start-v26.sh"
grep -Fq 'QT_QPA_PLATFORM="$platform"' "$ROOT/scripts/mechos-oobe-start-v26.sh"
grep -Fq 'run_candidate wayland' "$ROOT/scripts/mechos-oobe-start-v26.sh"
grep -Fq 'run_candidate xcb' "$ROOT/scripts/mechos-oobe-start-v26.sh"
grep -Fq 'kdialog --error' "$ROOT/scripts/mechos-oobe-start-v26.sh"
grep -Fq 'notify-send -u critical' "$ROOT/scripts/mechos-oobe-start-v26.sh"
grep -Fq 'Exec=/usr/local/bin/mechos-oobe-start' "$ROOT/scripts/mechos-hotfix-0.3.0-26-apply.sh"
grep -Fq "'version':'0.3.0-hotfix.26'" "$ROOT/scripts/build-hotfix-0.3.0-26.sh"
grep -Fq 'MechOS-0.3.0-hotfix.25-update.tar.zst' "$ROOT/scripts/build-hotfix-0.3.0-26.sh"
grep -Fq 'requires_reboot' "$ROOT/scripts/build-hotfix-0.3.0-26.sh"

printf 'Hotfix 26 source validation passed.\n'
