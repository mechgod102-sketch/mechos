#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_HELPER_V14
# MECHOS_HOTFIX14_STAGED_TRANSACTION_BOOTSTRAP_V1

MANIFEST_URL="https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json"
STATE=/var/lib/mechos
RELEASE=/etc/mechos/release
LOG=/var/log/mechos-update.log

is_root(){ [ "$(id -u)" -eq 0 ]; }
cache_dir(){
  if is_root; then printf '%s\n' /var/cache/mechos/update-center; else printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/mechos/update-center"; fi
}
CACHE="$(cache_dir)"
MANIFEST="$CACHE/stable.json"
mkdir -p "$CACHE" 2>/dev/null || true

log(){
  local line="[$(date -Is 2>/dev/null || date)] [update-helper-v14] $*"
  if is_root; then mkdir -p "$(dirname "$LOG")"; printf '%s\n' "$line" >>"$LOG"; else printf '%s\n' "$line" >&2; fi
}

current_version(){
  if [ -s "$RELEASE" ]; then tr -d '\r\n' <"$RELEASE"; else printf '%s\n' unknown; fi
}

fetch_manifest(){
  local tmp="$MANIFEST.tmp.$$"
  mkdir -p "$CACHE"
  if ! curl -fsSL --retry 2 --connect-timeout 8 -H 'Cache-Control: no-cache' \
      "${MANIFEST_URL}?t=$(date +%s)" -o "$tmp"; then
    rm -f "$tmp"
    [ -s "$MANIFEST" ] && return 0
    return 1
  fi
  python3 - "$tmp" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p,encoding='utf-8'))
for key in ('version','bundle_url','bundle_sha256'):
    if not isinstance(d.get(key),str) or not d[key].strip():
        raise SystemExit(f'invalid stable manifest: {key}')
sha=d['bundle_sha256'].strip().lower()
if len(sha)!=64 or any(c not in '0123456789abcdef' for c in sha):
    raise SystemExit('invalid stable manifest: bundle_sha256')
PY
  mv -f "$tmp" "$MANIFEST"
}

manifest_values(){
  python3 - "$MANIFEST" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
def clean(v): return str(v if v is not None else '').replace('\n',' ').replace('\r',' ')
print('LATEST='+clean(d.get('version','unknown')))
print('BUNDLE_URL='+clean(d.get('bundle_url','')))
print('BUNDLE_SHA='+clean(d.get('bundle_sha256','')).lower())
print('REQUIRES_REBOOT='+('1' if d.get('requires_reboot') else '0'))
print('NOTES='+clean(d.get('notes','')))
PY
}

package_counts(){
  local pac=0 flat=0
  if command -v checkupdates >/dev/null 2>&1; then
    pac="$(checkupdates 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ' || true)"
  fi
  if command -v flatpak >/dev/null 2>&1; then
    flat="$(flatpak remote-ls --updates --columns=application 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ' || true)"
  fi
  printf '%s %s\n' "${pac:-0}" "${flat:-0}"
}

emit_status(){
  fetch_manifest >/dev/null 2>&1 || true
  local current latest bundle_url bundle_sha reboot notes pac flat mechos total
  current="$(current_version)"
  latest="$current"; bundle_url=''; bundle_sha=''; reboot=0; notes=''
  if [ -s "$MANIFEST" ]; then
    while IFS='=' read -r k v; do
      case "$k" in
        LATEST) latest="$v";; BUNDLE_URL) bundle_url="$v";; BUNDLE_SHA) bundle_sha="$v";;
        REQUIRES_REBOOT) reboot="$v";; NOTES) notes="$v";;
      esac
    done < <(manifest_values)
  fi
  read -r pac flat < <(package_counts)
  mechos=0; [ "$latest" != "$current" ] && mechos=1
  total=$((mechos + ${pac:-0} + ${flat:-0}))
  [ -e "$STATE/reboot-required" ] && reboot=1
  printf 'CURRENT_MECHOS_VERSION=%s\n' "$current"
  printf 'LATEST_MECHOS_VERSION=%s\n' "$latest"
  printf 'MECHOS_UPDATE_AVAILABLE=%s\n' "$mechos"
  printf 'MECHOS_COUNT=%s\n' "$mechos"
  printf 'PACMAN_COUNT=%s\n' "${pac:-0}"
  printf 'ARCH_COUNT=%s\n' "${pac:-0}"
  printf 'FLATPAK_COUNT=%s\n' "${flat:-0}"
  printf 'TOTAL_COUNT=%s\n' "$total"
  printf 'REBOOT_REQUIRED=%s\n' "$reboot"
  printf 'ROLLBACK_PENDING=%s\n' "$( [ -s "$STATE/rollback-pending" ] && echo 1 || echo 0 )"
  printf 'MECHOS_RELEASE_NOTES=%s\n' "$notes"
  printf 'BUNDLE_URL=%s\n' "$bundle_url"
  printf 'BUNDLE_SHA256=%s\n' "$bundle_sha"
  printf 'MECHOS_UPDATE_CHECK_END=1\n'
}

validate_bundle(){
  local bundle="$1"
  python3 - "$bundle" <<'PY'
from pathlib import PurePosixPath
import subprocess,sys
bundle=sys.argv[1]
p=subprocess.run(['tar','--zstd','-tf',bundle],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if p.returncode: raise SystemExit('unable to list update bundle')
allowed=('usr/local/','usr/share/mechos/','usr/share/applications/','usr/share/wayland-sessions/','usr/lib/systemd/','etc/mechos/','etc/systemd/','etc/xdg/')
parents=set()
for prefix in allowed:
    parts=prefix.rstrip('/').split('/')
    for i in range(1,len(parts)): parents.add('/'.join(parts[:i]))
count=0
for raw in p.stdout.splitlines():
    name=raw.strip()
    while name.startswith('./'): name=name[2:]
    if not name or name=='.': continue
    path=PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts: raise SystemExit(f'unsafe bundle path: {name}')
    n=name.rstrip('/')
    if name.endswith('/') and n in parents: continue
    if not any(n==x.rstrip('/') or n.startswith(x) for x in allowed): raise SystemExit(f'path outside update allowlist: {name}')
    count+=1
if count==0: raise SystemExit('empty update bundle')
PY
}

run_transaction(){
  local stage="$1" latest="$2" tx rc=0 root_mode root_uid root_gid

  # Hotfix 20+ bundles carry the proven rsync-free v14 engine as a staged core.
  # Use that core directly on an old Hotfix 14 system so the installed v13
  # engine cannot block the update before it repairs itself.
  tx="$stage/usr/local/libexec/mechos-update-transaction-core-v20"
  if [ -x "$tx" ] && grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$tx" 2>/dev/null; then
    root_mode="$(stat -c '%a' /)"
    root_uid="$(stat -c '%u' /)"
    root_gid="$(stat -c '%g' /)"
    chmod "$root_mode" "$stage"
    chown "$root_uid:$root_gid" "$stage"
    "$tx" "$stage" "$latest" || rc=$?
    chown "$root_uid:$root_gid" / 2>/dev/null || true
    chmod "$root_mode" / 2>/dev/null || true
    return "$rc"
  fi

  # Hotfix 17-19 bundles contain a standalone rsync-free v14 transaction.
  for tx in \
    "$stage/usr/local/libexec/mechos-update-transaction-v14" \
    "$stage/usr/local/libexec/mechos-update-transaction-v13"; do
    [ -x "$tx" ] || continue
    grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$tx" 2>/dev/null || continue
    grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' "$tx" 2>/dev/null && continue
    "$tx" "$stage" "$latest"
    return $?
  done

  # Only fall back to installed transactions when the bundle has no newer
  # staged engine. Prefer v14 over the legacy rsync-dependent v13 engine.
  for tx in /usr/local/libexec/mechos-update-transaction-v14 /usr/local/libexec/mechos-update-transaction-v13; do
    [ -x "$tx" ] || continue
    "$tx" "$stage" "$latest"
    return $?
  done

  echo 'Transactional update engine is missing; update was not applied.' >&2
  return 12
}

apply_mechos(){
  fetch_manifest || { echo 'Unable to retrieve stable MechOS manifest.' >&2; return 10; }
  local latest='' url='' sha='' reboot=0 notes=''
  while IFS='=' read -r k v; do
    case "$k" in
      LATEST) latest="$v";; BUNDLE_URL) url="$v";; BUNDLE_SHA) sha="$v";; REQUIRES_REBOOT) reboot="$v";; NOTES) notes="$v";;
    esac
  done < <(manifest_values)
  local current; current="$(current_version)"
  [ -n "$latest" ] && [ -n "$url" ] && [ -n "$sha" ] || { echo 'Stable manifest is incomplete.' >&2; return 11; }
  if [ "$latest" = "$current" ]; then log "MechOS already current: $current"; return 0; fi

  local work bundle stage rc=0
  work="$(mktemp -d /tmp/mechos-update-v14.XXXXXX)"; bundle="$work/update.tar.zst"; stage="$work/stage"
  mkdir -p "$stage"
  log "downloading MechOS $latest"
  if ! curl -fL --retry 3 --connect-timeout 10 -H 'Cache-Control: no-cache' "$url" -o "$bundle"; then
    rm -rf "$work"; return 13
  fi
  if ! printf '%s  %s\n' "$sha" "$bundle" | sha256sum -c -; then rm -rf "$work"; return 14; fi
  if ! validate_bundle "$bundle"; then rm -rf "$work"; return 15; fi
  if ! tar --warning=no-timestamp --zstd -xpf "$bundle" -C "$stage"; then rm -rf "$work"; return 16; fi

  run_transaction "$stage" "$latest" || rc=$?
  if [ "$rc" -ne 0 ]; then rm -rf "$work"; return "$rc"; fi
  rm -rf "$work"
  mkdir -p "$STATE"
  [ "$reboot" = 1 ] && touch "$STATE/reboot-required"
  log "MechOS updated from $current to $latest; restart is user-controlled"
}

apply_packages(){
  if command -v pacman >/dev/null 2>&1; then pacman -Syu --noconfirm; fi
  if command -v flatpak >/dev/null 2>&1; then flatpak update --system -y || true; fi
}

cmd="${1:-status}"
case "$cmd" in
  status) emit_status ;;
  check) rm -f "$MANIFEST"; emit_status ;;
  apply)
    is_root || { echo 'Administrator privileges required. Run through pkexec.' >&2; exit 77; }
    apply_mechos
    apply_packages
    emit_status
    ;;
  *) echo 'Usage: mechos-update-helper {status|check|apply}' >&2; exit 2 ;;
esac
