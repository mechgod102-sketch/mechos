#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_031_PHASE1_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n \
  "$ROOT/scripts/mechos-0.3.1-phase1-apply.sh" \
  "$ROOT/scripts/build-mechos-0.3.1.sh"

grep -Fq 'MECHOS_031_PHASE1_WALLPAPERS_V1' "$ROOT/scripts/mechos-0.3.1-phase1-apply.sh"
grep -Fq 'MechOS-0.3.0-hotfix.35-update.tar.zst' "$ROOT/scripts/build-mechos-0.3.1.sh"
grep -Fq "'version':'0.3.1'" "$ROOT/scripts/build-mechos-0.3.1.sh"
grep -Fq 'MechOS v0.3.1 — Phase 1' "$ROOT/scripts/build-mechos-0.3.1.sh"

for i in $(seq -w 1 16); do
  img="$ROOT/overlay/rootfs/usr/share/backgrounds/mechos/mechos-wallpaper-$i.jpg"
  [ -s "$img" ] || { echo "Missing wallpaper source: $img" >&2; exit 1; }
done

# The OTA bundle stores artwork under the existing Update Center allowlist.
grep -Fq '/usr/share/mechos/wallpapers/0.3.1' "$ROOT/scripts/mechos-0.3.1-phase1-apply.sh"
grep -Fq '/usr/share/wallpapers' "$ROOT/scripts/mechos-0.3.1-phase1-apply.sh"
grep -Fq 'ConditionPathExists=/var/lib/mechos/installed' "$ROOT/scripts/build-mechos-0.3.1.sh"
grep -Fq 'ConditionPathExists=!/var/lib/mechos/0.3.1-phase1-wallpapers-applied' "$ROOT/scripts/build-mechos-0.3.1.sh"

echo 'MechOS 0.3.1 Phase 1 source contracts validated.'
