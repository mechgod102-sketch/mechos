#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX30_HARDWARE_PYTHON_CRASH_LOOP_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="$ROOT/scripts/mechscope-session-v20.sh"
OVERLAY="$ROOT/overlay/rootfs/usr/local/bin/mechscope-session"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-30-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-30.sh"

bash -n "$SESSION" "$OVERLAY" "$APPLY" "$BUILD"
for f in "$SESSION" "$OVERLAY"; do
  grep -Fq 'MECHOS_MECHSCOPE_SESSION_V21' "$f"
  grep -Fq 'actual_mechscope' "$f"
  grep -Fq 'is_python_target' "$f"
  grep -Fq 'python_source_check' "$f"
  grep -Fq 'PERSISTENT_RUNTIME=/usr/local/libexec/mechos-mechscope-runtime-v23' "$f"
  grep -Fq 'RAW_MECHSCOPE=/usr/local/bin/mechscope.real' "$f"
  grep -Fq 'MECHSCOPE_COMMAND=(/usr/bin/python3 "$target")' "$f"
  if grep -Fq 'MECHOS_MECHSCOPE_SESSION_V22_SINGLE_OWNER' "$f"; then
    grep -Fq '/usr/bin/gamescope "$@" -- /usr/bin/flock -n "$LOCK_FILE" "${MECHSCOPE_COMMAND[@]}"' "$f"
    grep -Fq '/usr/bin/flock -n "$LOCK_FILE" "${MECHSCOPE_COMMAND[@]}"' "$f"
  else
    grep -Fq '/usr/bin/gamescope "$@" -- "${MECHSCOPE_COMMAND[@]}"' "$f"
    grep -Fq '"${MECHSCOPE_COMMAND[@]}" >>"$LOG_FILE"' "$f"
  fi
  grep -Fq 'crashes >= 3' "$f"
  grep -Fq 'safe_desktop_fallback' "$f"
  grep -Fq "printf 'desktop\\n' >\"\$MODE_FILE\"" "$f"
  if grep -Eq 'gamescope .*-- .*\$MECHSCOPE([[:space:]";]|$)' "$f"; then
    echo "raw MechScope executable is still passed directly to Gamescope: $f" >&2
    exit 1
  fi
done

grep -Fq 'MECHOS_HOTFIX30_HARDWARE_PYTHON_CRASH_LOOP_V1' "$APPLY"
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V21' "$APPLY"
grep -Fq 'MECHSCOPE_COMMAND=(/usr/bin/python3 "$target")' "$APPLY"
grep -Fq "printf '0.3.0-hotfix.30" "$APPLY"
grep -Fq 'touch "$MARKER"' "$APPLY"

grep -Fq 'MechOS-0.3.0-hotfix.29-update.tar.zst' "$BUILD"
grep -Fq 'MechOS-0.3.0-hotfix.30-update.tar.zst' "$BUILD"
grep -Fq 'mechscope-session-v20.sh' "$BUILD"
grep -Fq "'version':'0.3.0-hotfix.30'" "$BUILD"
grep -Fq 'requires_reboot' "$BUILD"

printf 'Hotfix 30 hardware Python/crash-loop regression validation passed.\n'
