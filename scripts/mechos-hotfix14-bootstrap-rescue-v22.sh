#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX14_BOOTSTRAP_RESCUE_V22

MANIFEST_URL="https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json"
STATE=/var/lib/mechos
RELEASE=/etc/mechos/release
LOG=/var/log/mechos-hotfix14-bootstrap-rescue.log

if [ "$(id -u)" -ne 0 ]; then
  echo 'Administrator privileges are required.' >&2
  if command -v pkexec >/dev/null 2>&1; then
    exec pkexec env PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin bash "$0" "$@"
  fi
  exit 77
fi

mkdir -p "$STATE" /var/log /var/cache/mechos/update-center

log(){
  local line="[$(date -Is 2>/dev/null || date)] [hotfix14-bootstrap-v22] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >>"$LOG"
}

current="unknown"
[ -s "$RELEASE" ] && current="$(tr -d '\r\n' <"$RELEASE")"
log "current installed version: $current"

work="$(mktemp -d /var/cache/mechos/update-center/h14-bootstrap.XXXXXX)"
bundle="$work/update.tar.zst"
stage="$work/stage"
manifest="$work/stable.json"
mkdir -p "$stage"

ROOT_MODE="$(stat -c '%a' /)"
ROOT_UID="$(stat -c '%u' /)"
ROOT_GID="$(stat -c '%g' /)"
restore_root(){
  chown "$ROOT_UID:$ROOT_GID" / 2>/dev/null || true
  chmod "$ROOT_MODE" / 2>/dev/null || true
}
cleanup(){
  restore_root
  rm -rf "$work"
}
trap cleanup EXIT

log 'downloading current stable manifest'
curl -fsSL --retry 3 --connect-timeout 10 -H 'Cache-Control: no-cache' \
  "${MANIFEST_URL}?t=$(date +%s)" -o "$manifest"

readarray -t meta < <(python3 - "$manifest" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p,encoding='utf-8'))
for key in ('version','bundle_url','bundle_sha256'):
    v=d.get(key)
    if not isinstance(v,str) or not v.strip():
        raise SystemExit(f'invalid stable manifest: {key}')
sha=d['bundle_sha256'].strip().lower()
if len(sha)!=64 or any(c not in '0123456789abcdef' for c in sha):
    raise SystemExit('invalid stable manifest: bundle_sha256')
print(d['version'].strip())
print(d['bundle_url'].strip())
print(sha)
PY
)
latest="${meta[0]}"
url="${meta[1]}"
sha="${meta[2]}"
log "stable version: $latest"

case "$latest" in
  0.3.0-hotfix.22.1|0.3.0-hotfix.22.*|0.3.0-hotfix.2[3-9]*|0.3.[1-9]*|0.[4-9]*|[1-9]*) ;;
  *)
    log "ERROR: stable release $latest does not contain the Hotfix 22 recovery baseline"
    exit 20
    ;;
esac

log "downloading verified MechOS bundle for $latest"
curl -fL --retry 3 --connect-timeout 10 -H 'Cache-Control: no-cache' "$url" -o "$bundle"
printf '%s  %s\n' "$sha" "$bundle" | sha256sum -c -

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
    count += 1
if not count:
    raise SystemExit('empty update bundle')
PY

tar --warning=no-timestamp --zstd -xpf "$bundle" -C "$stage"

CORE="$stage/usr/local/libexec/mechos-update-transaction-core-v20"
if [ ! -x "$CORE" ]; then
  candidate="$stage/usr/local/libexec/mechos-update-transaction-v14"
  if [ -x "$candidate" ] && grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$candidate" 2>/dev/null && ! grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' "$candidate" 2>/dev/null; then
    CORE="$candidate"
  else
    log 'ERROR: verified rsync-free staged transaction core is missing'
    exit 21
  fi
fi

bash -n "$CORE"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$CORE"
! grep -Eq '^[[:space:]]*rsync[[:space:]]' "$CORE"

# The v20 wrapper normally performs this normalization before calling the v14
# core. We do it here because a Hotfix 14 system does not have the v20 core path
# installed yet. This prevents the temporary stage directory mode from ever
# changing the installed root directory mode.
chmod "$ROOT_MODE" "$stage"
chown "$ROOT_UID:$ROOT_GID" "$stage"

log "bootstrapping $latest with staged rsync-free transaction core"
set +e
"$CORE" "$stage" "$latest"
rc=$?
set -e
restore_root
[ "$rc" -eq 0 ] || { log "ERROR: bootstrap transaction failed with code $rc"; exit "$rc"; }

systemctl daemon-reload >/dev/null 2>&1 || true

# The cumulative Hotfix 22 service must be present after the transaction. Its
# apply helper activates every missing layer 15-21 before finalizing 22.1.
[ -x /usr/local/libexec/mechos-hotfix-0.3.0-22-apply ] || {
  log 'ERROR: cumulative Hotfix 22 apply helper was not installed'
  exit 22
}
[ -f /usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service ] || {
  log 'ERROR: cumulative Hotfix 22 boot service was not installed'
  exit 23
}

mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service \
  /etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-22.service

touch "$STATE/reboot-required"
log "$latest staged successfully; restart MechOS once to activate Hotfixes 15-22.1"
printf '\nMechOS %s is staged. Restart MechOS once; the cumulative boot service will activate Hotfixes 15 through 22.1.\n' "$latest"
