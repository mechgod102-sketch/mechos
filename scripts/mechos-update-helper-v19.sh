#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_HELPER_V14
# MECHOS_UPDATE_HELPER_V18
# MECHOS_UPDATE_HELPER_V19
# MECHOS_HOTFIX17_HELPER_WARNING_FIX
# Hotfix 19 bootstrap repair: when an update bundle contains a newer validated
# transaction engine, use that staged engine instead of blindly preferring the
# older installed transaction that may be the reason updates are failing.

CORE=/usr/local/libexec/mechos-update-helper-core-v18
HEALTH=/usr/local/libexec/mechos-pacman-health-v18
STATE=/var/lib/mechos

[ -x "$CORE" ] || { echo 'MechOS update helper core is missing.' >&2; exit 73; }

status_value(){
  local key="$1"
  printf '%s\n' "$STATUS" | sed -n "s/^${key}=//p" | tail -n1
}

choose_transaction(){
  local stage="$1"
  local candidate
  for candidate in \
    "$stage/usr/local/libexec/mechos-update-transaction-v14" \
    "$stage/usr/local/libexec/mechos-update-transaction-v13" \
    /usr/local/libexec/mechos-update-transaction-v14 \
    /usr/local/libexec/mechos-update-transaction-v13; do
    [ -x "$candidate" ] || continue
    if grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

validate_bundle_paths(){
  local bundle="$1"
  python3 - "$bundle" <<'PY'
from pathlib import PurePosixPath
import subprocess,sys
bundle=sys.argv[1]
p=subprocess.run(['tar','--zstd','-tf',bundle],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if p.returncode:
    raise SystemExit('unable to list update bundle')
allowed=('usr/local/','usr/share/mechos/','usr/share/applications/','usr/share/wayland-sessions/','usr/lib/systemd/','etc/mechos/','etc/systemd/','etc/xdg/')
parents=set()
for prefix in allowed:
    parts=prefix.rstrip('/').split('/')
    for i in range(1,len(parts)):
        parents.add('/'.join(parts[:i]))
count=0
for raw in p.stdout.splitlines():
    name=raw.strip()
    while name.startswith('./'):
        name=name[2:]
    if not name or name=='.':
        continue
    path=PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts:
        raise SystemExit(f'unsafe bundle path: {name}')
    n=name.rstrip('/')
    if name.endswith('/') and n in parents:
        continue
    if not any(n==x.rstrip('/') or n.startswith(x) for x in allowed):
        raise SystemExit(f'path outside update allowlist: {name}')
    count+=1
if not count:
    raise SystemExit('empty update bundle')
PY
}

apply_mechos_v19(){
  local work bundle stage tx latest current url sha reboot rc=0
  STATUS="$($CORE check)"
  latest="$(status_value LATEST_MECHOS_VERSION)"
  current="$(status_value CURRENT_MECHOS_VERSION)"
  url="$(status_value BUNDLE_URL)"
  sha="$(status_value BUNDLE_SHA256)"
  reboot="$(status_value REBOOT_REQUIRED)"

  [ -n "$latest" ] && [ -n "$current" ] || { echo 'Update status is incomplete.' >&2; return 11; }
  [ "$latest" != "$current" ] || return 0
  [ -n "$url" ] && [ -n "$sha" ] || { echo 'Stable manifest is incomplete.' >&2; return 11; }

  work="$(mktemp -d /tmp/mechos-update-v19.XXXXXX)"
  bundle="$work/update.tar.zst"
  stage="$work/stage"
  mkdir -p "$stage"

  echo "Downloading MechOS $latest..."
  if ! curl -fL --retry 3 --connect-timeout 10 -H 'Cache-Control: no-cache' "$url" -o "$bundle"; then
    rm -rf "$work"; return 13
  fi
  if ! printf '%s  %s\n' "$sha" "$bundle" | sha256sum -c -; then
    rm -rf "$work"; return 14
  fi
  if ! validate_bundle_paths "$bundle"; then
    rm -rf "$work"; return 15
  fi
  if ! tar --warning=no-timestamp --zstd -xpf "$bundle" -C "$stage"; then
    rm -rf "$work"; return 16
  fi

  tx="$(choose_transaction "$stage")" || {
    echo 'No validated rsync-free transaction engine is available.' >&2
    rm -rf "$work"
    return 12
  }
  echo "Using transaction engine: $tx"
  "$tx" "$stage" "$latest" || rc=$?
  rm -rf "$work"
  [ "$rc" -eq 0 ] || return "$rc"

  mkdir -p "$STATE"
  [ "$reboot" = 1 ] && touch "$STATE/reboot-required"
  echo 'MECHOS_CORE_UPDATE_STAGED=1'
  return 0
}

apply_packages_v19(){
  local rc=0
  if [ -x "$HEALTH" ]; then "$HEALTH" || true; fi
  if command -v pacman >/dev/null 2>&1; then
    if ! pacman -Syu --noconfirm; then rc=1; fi
  fi
  if command -v flatpak >/dev/null 2>&1; then
    if ! flatpak update --system -y; then rc=1; fi
  fi
  return "$rc"
}

cmd="${1:-status}"
case "$cmd" in
  status|check)
    exec "$CORE" "$cmd"
    ;;
  apply)
    [ "$(id -u)" -eq 0 ] || { echo 'Administrator privileges required. Run through pkexec.' >&2; exit 77; }
    apply_mechos_v19
    mech_rc=$?
    [ "$mech_rc" -eq 0 ] || exit "$mech_rc"

    set +e
    apply_packages_v19
    pkg_rc=$?
    set -e
    if [ "$pkg_rc" -ne 0 ]; then
      echo 'PACKAGE_UPDATE_FAILED=1'
      echo 'MechOS update staged successfully. Arch/Flatpak updates can be retried after restart.' >&2
    fi
    "$CORE" status || true
    exit 0
    ;;
  *)
    echo 'Usage: mechos-update-helper {status|check|apply}' >&2
    exit 2
    ;;
esac
