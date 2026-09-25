#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_HELPER_V37_SIGNED_MANIFEST_V1

STABLE_URL="${MECHOS_STABLE_URL:-https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json}"
PUB=/etc/mechos/update-signing-public.pem
STATE=/var/lib/mechos
RELEASE=/etc/mechos/release

die(){ echo "$*" >&2; exit 1; }

validate_bundle_paths(){
  local bundle="$1"
  python3 - "$bundle" <<'PY'
from pathlib import PurePosixPath
import subprocess,sys
p=subprocess.run(['tar','--zstd','-tf',sys.argv[1]],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if p.returncode: raise SystemExit('unable to list update bundle')
allowed=('usr/local/','usr/share/mechos/','usr/share/applications/','usr/share/wayland-sessions/',
         'usr/lib/systemd/','etc/mechos/','etc/systemd/','etc/xdg/')
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
    if not any(n==x.rstrip('/') or n.startswith(x) for x in allowed):
        raise SystemExit(f'path outside update allowlist: {name}')
    count+=1
if not count: raise SystemExit('empty update bundle')
PY
}

signed_manifest(){
  local dir manifest sig sig_url
  dir="$1"
  manifest="$dir/stable.json"
  sig="$dir/stable.json.sig"
  [ -s "$PUB" ] || die "MechOS update signing public key is missing: $PUB"
  command -v openssl >/dev/null 2>&1 || die 'openssl is required for signed MechOS updates'
  curl -fL --retry 3 --connect-timeout 10 -H 'Cache-Control: no-cache' "$STABLE_URL" -o "$manifest"
  sig_url="$(python3 - "$manifest" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
u=d.get('signature_url')
if not isinstance(u,str) or not u.startswith('https://'):
    raise SystemExit('manifest signature_url missing or invalid')
print(u)
PY
)"
  curl -fL --retry 3 --connect-timeout 10 -H 'Cache-Control: no-cache' "$sig_url" -o "$sig"
  openssl dgst -sha256 -verify "$PUB" -signature "$sig" "$manifest" >/dev/null
  python3 - "$manifest" <<'PY'
import json,re,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
v=d.get('version',''); u=d.get('bundle_url',''); s=d.get('bundle_sha256','')
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-hotfix\.[0-9]+(?:\.[0-9]+)*)?',v):
    raise SystemExit('invalid signed version')
if not isinstance(u,str) or not u.startswith('https://'):
    raise SystemExit('invalid signed bundle URL')
if not re.fullmatch(r'[0-9a-fA-F]{64}',str(s)):
    raise SystemExit('invalid signed bundle SHA256')
print('VERSION='+v)
print('BUNDLE_URL='+u)
print('BUNDLE_SHA256='+s.lower())
print('REBOOT_REQUIRED='+('1' if d.get('requires_reboot') else '0'))
print('RELEASE_NAME='+str(d.get('release_name',v)).replace('\n',' '))
PY
}

current_release(){
  if [ -r "$RELEASE" ]; then tr -d '\r\n[:space:]' <"$RELEASE"; else printf '0.0.0'; fi
}

is_newer_version(){
  python3 - "$1" "$2" <<'PY'
import re,sys
def key(v):
    m=re.fullmatch(r'(\d+)\.(\d+)\.(\d+)(?:-hotfix\.([0-9]+(?:\.[0-9]+)*))?',v)
    if not m:
        raise SystemExit(2)
    base=tuple(int(x) for x in m.group(1,2,3))
    suffix=m.group(4)
    return base + ((1,)+tuple(int(x) for x in suffix.split('.')) if suffix else (0,))
current=key(sys.argv[1]); candidate=key(sys.argv[2])
raise SystemExit(0 if candidate > current else 1)
PY
}

commit_release_version(){
  local version="$1" tmp actual
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-hotfix\.[0-9]+(\.[0-9]+)*)?$ ]] || die "Refusing invalid MechOS release version: $version"
  mkdir -p "$(dirname "$RELEASE")"
  tmp="$(mktemp "${RELEASE}.tmp.XXXXXX")"
  printf '%s\n' "$version" >"$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$RELEASE"
  actual="$(current_release)"
  [ "$actual" = "$version" ] || die "MechOS release commit verification failed: expected=$version actual=$actual"
}

selftest_local(){
  [ -x /usr/local/bin/mechos-update-center ] || die 'Update Center is missing'
  [ -x /usr/local/bin/mechos-reboot ] || die 'reboot helper is missing'
  [ -s "$PUB" ] || die "MechOS update signing public key is missing: $PUB"
  command -v openssl >/dev/null 2>&1 || die 'openssl is required for signed MechOS updates'
  bash -n /usr/local/bin/mechos-reboot
  printf 'MECHOS_UPDATE_HELPER_SELFTEST=1\nCURRENT_MECHOS_VERSION=%s\n' "$(current_release)"
}

status_signed(){
  local work values latest url sha reboot name current
  work="$(mktemp -d /tmp/mechos-signed-status.XXXXXX)"
  trap 'rm -rf "$work"' RETURN
  values="$(signed_manifest "$work")"
  latest="$(printf '%s\n' "$values" | sed -n 's/^VERSION=//p')"
  url="$(printf '%s\n' "$values" | sed -n 's/^BUNDLE_URL=//p')"
  sha="$(printf '%s\n' "$values" | sed -n 's/^BUNDLE_SHA256=//p')"
  reboot="$(printf '%s\n' "$values" | sed -n 's/^REBOOT_REQUIRED=//p')"
  name="$(printf '%s\n' "$values" | sed -n 's/^RELEASE_NAME=//p')"
  current="$(current_release)"
  local available=0
  if is_newer_version "$current" "$latest"; then available=1; fi
  printf 'CURRENT_MECHOS_VERSION=%s\n' "$current"
  printf 'LATEST_MECHOS_VERSION=%s\n' "$latest"
  printf 'MECHOS_UPDATE_AVAILABLE=%s\n' "$available"
  printf 'MECHOS_COUNT=%s\n' "$available"
  printf 'BUNDLE_URL=%s\n' "$url"
  printf 'BUNDLE_SHA256=%s\n' "$sha"
  printf 'REBOOT_REQUIRED=%s\n' "$([ -e "$STATE/reboot-required" ] && echo 1 || echo "$reboot")"
  printf 'RELEASE_NAME=%s\n' "$name"
  printf 'SIGNATURE_VALID=1\n'
  printf 'ARCH_COUNT=—\nFLATPAK_COUNT=—\n'
}

choose_transaction(){
  local stage="$1" c
  for c in "$stage/usr/local/libexec/mechos-update-transaction-v14"            "$stage/usr/local/libexec/mechos-update-transaction-v13"            /usr/local/libexec/mechos-update-transaction-v14            /usr/local/libexec/mechos-update-transaction-v13; do
    [ -x "$c" ] || continue
    grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$c" 2>/dev/null || continue
    printf '%s\n' "$c"; return 0
  done
  return 1
}

apply_signed(){
  [ "$(id -u)" -eq 0 ] || die 'Administrator privileges required. Run through pkexec.'
  local work values latest url sha reboot current bundle stage tx rc=0
  work="$(mktemp -d /tmp/mechos-signed-apply.XXXXXX)"
  trap 'rm -rf "$work"' RETURN
  values="$(signed_manifest "$work")"
  latest="$(printf '%s\n' "$values" | sed -n 's/^VERSION=//p')"
  url="$(printf '%s\n' "$values" | sed -n 's/^BUNDLE_URL=//p')"
  sha="$(printf '%s\n' "$values" | sed -n 's/^BUNDLE_SHA256=//p')"
  reboot="$(printf '%s\n' "$values" | sed -n 's/^REBOOT_REQUIRED=//p')"
  current="$(current_release)"
  [ "$latest" != "$current" ] || return 0
  is_newer_version "$current" "$latest" || die "Refusing MechOS downgrade: installed $current is newer than Stable feed $latest"
  bundle="$work/update.tar.zst"; stage="$work/stage"; mkdir -p "$stage"
  echo "Downloading signed MechOS $latest..."
  curl -fL --retry 3 --connect-timeout 10 -H 'Cache-Control: no-cache' "$url" -o "$bundle"
  printf '%s  %s\n' "$sha" "$bundle" | sha256sum -c -
  validate_bundle_paths "$bundle"
  tar --warning=no-timestamp --zstd -xpf "$bundle" -C "$stage"
  tx="$(choose_transaction "$stage")" || die 'No validated MechOS transaction engine is available.'
  "$tx" "$stage" "$latest" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  commit_release_version "$latest"
  mkdir -p "$STATE"
  [ "$reboot" = 1 ] && touch "$STATE/reboot-required"
  if command -v pacman >/dev/null 2>&1; then pacman -Syu --noconfirm || true; fi
  if command -v flatpak >/dev/null 2>&1; then flatpak update --system -y || true; fi
  printf 'MECHOS_CORE_UPDATE_STAGED=1\nSIGNATURE_VALID=1\n'
}

case "${1:-status}" in
  status|check) status_signed ;;
  apply) apply_signed ;;
  selftest) selftest_local ;;
  *) echo 'Usage: mechos-update-helper {status|check|apply|selftest}' >&2; exit 2 ;;
esac
