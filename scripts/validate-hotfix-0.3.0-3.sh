#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-3-apply.sh"
REFRESH="$ROOT/scripts/mechos-update-manifest-refresh-runtime.sh"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.3-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
fail(){ echo "[validate-hotfix-0.3.0-3] ERROR: $*" >&2; exit 1; }

[ -f "$APPLY" ] || fail "Hotfix 3 apply helper missing"
bash -n "$APPLY" || fail "Hotfix 3 apply helper shell syntax failed"
[ -f "$REFRESH" ] || fail "Update Center manifest refresh helper missing"
bash -n "$REFRESH" || fail "Update Center manifest refresh helper shell syntax failed"
grep -Fq 'passwd -d mechos-setup' "$APPLY" || fail "temporary firstboot account is not unlocked"
grep -Fq 'gpasswd -d mechos-setup wheel' "$APPLY" || fail "temporary setup account is not removed from wheel"
grep -Fq 'mechos-oobe-autostart.service' "$APPLY" || fail "systemd-user OOBE fallback missing"
grep -Fq 'Exec=/usr/local/bin/mechos-oobe-start' "$APPLY" || fail "KDE/XDG OOBE launch path missing"
grep -Fq 'Engine=none' "$APPLY" || fail "KDE/Plasma splash suppression missing"
grep -Fq 'User=mechos-setup' "$APPLY" || fail "SDDM firstboot handoff missing"
grep -Fq 'Relogin=false' "$APPLY" || fail "firstboot SDDM relogin loop guard missing"
grep -Fq "printf '0.3.0-hotfix.3" "$APPLY" || fail "Hotfix 3 release metadata missing"
grep -Fq 'MECHOS_MANIFEST_REFRESH_V1' "$REFRESH" || fail "manifest cache-busting patch marker missing"
grep -Fq '_mechos_refresh=' "$REFRESH" || fail "manifest cache-busting query missing"
grep -Fq 'Cache-Control: no-cache' "$REFRESH" || fail "manifest no-cache header missing"

[ -s "$BUNDLE" ] || fail "Hotfix 3 bundle missing"
[ -s "$SUM" ] || fail "Hotfix 3 checksum missing"
(
  cd "$(dirname "$BUNDLE")"
  sha256sum -c "$(basename "$SUM")"
) >/dev/null || fail "Hotfix 3 checksum file does not verify"
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"

python3 - "$BUNDLE" <<'PY'
from pathlib import PurePosixPath
import subprocess,sys
bundle=sys.argv[1]
p=subprocess.run(['tar','--zstd','-tf',bundle],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if p.returncode: raise SystemExit('unable to list Hotfix 3 bundle')
allowed=(
 'usr/local/', 'usr/share/mechos/', 'usr/share/applications/',
 'usr/share/wayland-sessions/', 'usr/lib/systemd/', 'etc/mechos/',
 'etc/systemd/', 'etc/xdg/'
)
allowed_parents=set()
for prefix in allowed:
    parts=prefix.rstrip('/').split('/')
    for i in range(1,len(parts)): allowed_parents.add('/'.join(parts[:i]))
required={
 'usr/local/bin/mechos-oobe',
 'usr/local/libexec/mechos-oobe-apply',
 'usr/local/libexec/mechos-oobe-cleanup',
 'usr/local/libexec/mechos-hotfix-0.3.0-3-apply',
 'usr/local/libexec/mechos-update-manifest-refresh-runtime',
 'usr/lib/systemd/system/mechos-hotfix-0.3.0-3.service',
 'etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-3.service',
}
seen=set()
for raw in p.stdout.splitlines():
    name=raw.strip()
    while name.startswith('./'): name=name[2:]
    if not name or name=='.': continue
    path=PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts: raise SystemExit(f'unsafe bundle path: {name}')
    normalized=name.rstrip('/'); is_dir=name.endswith('/')
    if is_dir and normalized in allowed_parents:
        seen.add(normalized); continue
    if not any(normalized==x.rstrip('/') or normalized.startswith(x) for x in allowed):
        raise SystemExit(f'path outside Update Center allowlist: {name}')
    seen.add(normalized)
missing=sorted(required-seen)
if missing: raise SystemExit('bundle missing required files: '+', '.join(missing))
PY

python3 - "$MANIFEST" "$SHA" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: data=json.load(f)
if data.get('version') != '0.3.0-hotfix.3': raise SystemExit('stable manifest is not Hotfix 3')
if data.get('release_name') != 'MechOS v0.3.0 Hotfix 3': raise SystemExit('Hotfix 3 release name is wrong')
if data.get('bundle_sha256') != sys.argv[2]: raise SystemExit('manifest SHA does not match bundle')
if data.get('bundle_url') != 'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.3-update.tar.zst': raise SystemExit('Hotfix 3 URL is wrong')
if data.get('requires_reboot') is not True: raise SystemExit('Hotfix 3 must require reboot')
PY

echo '[validate-hotfix-0.3.0-3] OK: firstboot repair, KDE splash suppression, fresh Update Center manifest discovery, bundle and stable manifest verify'
