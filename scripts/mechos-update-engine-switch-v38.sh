#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_ENGINE_SWITCH_V38

ROOT="${MECHOS_UPDATE_ENGINE_ROOT:-/usr/local/share/mechos/update-engine}"
SLOTS="$ROOT/slots"
CURRENT="$ROOT/current"
PREVIOUS="$ROOT/previous"

validate_slot(){
  local slot="$1"
  [[ -d "$slot" ]] || return 1
  [[ -f "$slot/mechos-update-helper-core" ]] || return 1
  [[ -f "$slot/mechos-update-center-backend.py" ]] || return 1
  [[ -f "$slot/mechos-update-transaction" ]] || return 1
  bash -n "$slot/mechos-update-helper-core" >/dev/null 2>&1 || return 1
  bash -n "$slot/mechos-update-transaction" >/dev/null 2>&1 || return 1
  grep -Fq 'MECHOS_UPDATE_HELPER_CORE_V38_AB_ENGINE' "$slot/mechos-update-helper-core" || return 1
  grep -Fq 'MECHOS_UPDATE_TRANSACTION_V15' "$slot/mechos-update-transaction" || return 1
  python3 - "$slot/mechos-update-center-backend.py" >/dev/null 2>&1 <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
}

atomic_link(){
  local target="$1" link="$2" tmp
  mkdir -p "$(dirname "$link")"
  tmp="$link.new.$$"
  rm -f "$tmp"
  ln -s "$target" "$tmp"
  mv -Tf "$tmp" "$link"
}

activate(){
  local name slot old=""
  name="$1"
  slot="$SLOTS/$name"
  [[ "$(id -u)" -eq 0 || -n "${MECHOS_UPDATE_ENGINE_TEST_MODE:-}" ]] || {
    echo 'Administrator privileges required.' >&2
    exit 77
  }
  validate_slot "$slot" || {
    echo "Refusing invalid MechOS Update Engine slot: $name" >&2
    exit 71
  }
  if [[ -L "$CURRENT" ]]; then
    old="$(readlink -f "$CURRENT" || true)"
  fi
  if [[ -n "$old" && "$old" != "$slot" && -d "$old" ]] && validate_slot "$old"; then
    atomic_link "$old" "$PREVIOUS"
  fi
  atomic_link "$slot" "$CURRENT"
  validate_slot "$(readlink -f "$CURRENT")" || {
    echo 'Activated Update Engine slot failed validation.' >&2
    if [[ -L "$PREVIOUS" ]] && validate_slot "$(readlink -f "$PREVIOUS")"; then
      atomic_link "$(readlink -f "$PREVIOUS")" "$CURRENT"
    fi
    exit 72
  }
  printf 'MECHOS_UPDATE_ENGINE_ACTIVE=%s\n' "$name"
}

recover(){
  [[ "$(id -u)" -eq 0 || -n "${MECHOS_UPDATE_ENGINE_TEST_MODE:-}" ]] || {
    echo 'Administrator privileges required.' >&2
    exit 77
  }
  if [[ -L "$CURRENT" ]] && validate_slot "$(readlink -f "$CURRENT")"; then
    printf 'MECHOS_UPDATE_ENGINE_RECOVERY=not-needed\n'
    return 0
  fi
  if [[ -L "$PREVIOUS" ]] && validate_slot "$(readlink -f "$PREVIOUS")"; then
    atomic_link "$(readlink -f "$PREVIOUS")" "$CURRENT"
    printf 'MECHOS_UPDATE_ENGINE_RECOVERY=previous\n'
    return 0
  fi
  local candidate
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if validate_slot "$candidate"; then
      atomic_link "$candidate" "$CURRENT"
      printf 'MECHOS_UPDATE_ENGINE_RECOVERY=slot\n'
      return 0
    fi
  done < <(find "$SLOTS" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -r)
  echo 'No valid MechOS Update Engine slot is available.' >&2
  exit 73
}

case "${1:---check}" in
  --check)
    if [[ -L "$CURRENT" ]] && validate_slot "$(readlink -f "$CURRENT")"; then
      printf 'MECHOS_UPDATE_ENGINE_STATE=ok\n'
      printf 'MECHOS_UPDATE_ENGINE_SLOT=%s\n' "$(basename "$(readlink -f "$CURRENT")")"
      exit 0
    fi
    printf 'MECHOS_UPDATE_ENGINE_STATE=invalid\n'
    exit 1
    ;;
  --activate)
    [[ -n "${2:-}" ]] || { echo 'slot name required' >&2; exit 2; }
    activate "$2"
    ;;
  --recover)
    recover
    ;;
  *)
    echo 'Usage: mechos-update-engine-switch {--check|--activate SLOT|--recover}' >&2
    exit 2
    ;;
esac
