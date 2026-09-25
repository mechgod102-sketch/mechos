#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_CENTER_AB_LAUNCHER_V38
ENGINE=/usr/local/share/mechos/update-engine
RECOVERY=/usr/local/share/mechos/update-recovery/mechos-update-center-v8.py

for candidate in   "$ENGINE/current/mechos-update-center-backend.py"   "$ENGINE/previous/mechos-update-center-backend.py"   "$RECOVERY"; do
  [[ -f "$candidate" ]] || continue
  if /usr/bin/python3 - "$candidate" >/dev/null 2>&1 <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
  then
    exec /usr/bin/python3 "$candidate" "$@"
  fi
done

echo 'MechOS Update Center backend is unavailable. Run the updater self-repair tool.' >&2
exit 73
