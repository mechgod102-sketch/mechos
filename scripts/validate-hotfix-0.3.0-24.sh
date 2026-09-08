#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX24_MECHSCOPE_AUTOLAUNCH_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh"
bash -n "$ROOT/scripts/build-hotfix-0.3.0-24.sh"

grep -Fq 'MECHOS_HOTFIX24_MECHSCOPE_AUTOLAUNCH_V1' "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh"
grep -Fq 'Session=mechscope.desktop' "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh"
grep -Fq 's/^Session=mechos-gaming\.desktop$/Session=mechscope.desktop/' "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh"
grep -Fq 'MECHOS_VM_MODE_RUNTIME_V24' "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh"
grep -Fq 'QT_QPA_PLATFORM=wayland' "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh"
grep -Fq 'QT_QPA_PLATFORM=xcb' "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh"
grep -Fq 'systemctl --user show-environment' "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh"
grep -Fq 'MECHOS_SESSION_AUTOSTART_V24' "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh"
grep -Fq 'OnlyShowIn=KDE;' "$ROOT/scripts/mechos-hotfix-0.3.0-24-apply.sh"
grep -Fq "'version':'0.3.0-hotfix.24'" "$ROOT/scripts/build-hotfix-0.3.0-24.sh"
grep -Fq 'MechOS-0.3.0-hotfix.23-update.tar.zst' "$ROOT/scripts/build-hotfix-0.3.0-24.sh"
grep -Fq 'MechOS-0.3.0-hotfix.24-update.tar.zst' "$ROOT/scripts/build-hotfix-0.3.0-24.sh"
grep -Fq 'requires_reboot' "$ROOT/scripts/build-hotfix-0.3.0-24.sh"

printf 'Hotfix 24 source validation passed.\n'
