#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-4-apply.sh"
BUILD="$ROOT/scripts/build-hotfix-0.3.0-4.sh"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.4-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
FIXED="$ROOT/src/mechos_ui/fixed_canvas.py"
INSTALLER="$ROOT/src/mechos_ui/installer_shell.py"
CREATOR="$ROOT/src/mechos_ui/creator_shell.py"
fail(){ echo "[validate-hotfix-0.3.0-4] ERROR: $*" >&2; exit 1; }

[ -f "$APPLY" ] || fail "Hotfix 4 apply helper missing"
[ -f "$BUILD" ] || fail "Hotfix 4 builder missing"
bash -n "$APPLY" || fail "Hotfix 4 apply helper shell syntax failed"
bash -n "$BUILD" || fail "Hotfix 4 builder shell syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$FIXED" "$INSTALLER" "$CREATOR" \
  || fail "responsive source UI Python validation failed"

# Issue 1 + 6: one scale must govern geometry, text and padding at VM sizes.
grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V2' "$FIXED" || fail "responsive VM geometry marker missing"
grep -Fq 'vpad = max(2, int(round(6 * s)))' "$FIXED" || fail "button vertical padding does not scale"
grep -Fq 'hpad = max(4, int(round(10 * s)))' "$FIXED" || fail "button horizontal padding does not scale"
grep -Fq 'max(5, int(round(base * s)))' "$FIXED" || fail "VM typography still has the old oversized floor"
grep -Fq 'class InstallerShell(FixedCanvas)' "$INSTALLER" || fail "Live installer does not use responsive canvas"
grep -Fq 'class LiveCreatorHome(FixedCanvas)' "$CREATOR" || fail "Creator dashboard does not use responsive canvas"

# Issue 2 + 3: OOBE must run only as mechos-setup, with deterministic SDDM
# authority and no direct OOBE launch from an already-exposed normal user.
grep -Fq 'passwd -d mechos-setup' "$APPLY" || fail "setup account is not made usable"
grep -Fq 'gpasswd -d mechos-setup wheel' "$APPLY" || fail "setup account still receives broad admin membership"
grep -Fq 'strip_competing_sddm_autologin' "$APPLY" || fail "competing SDDM autologin configs are not repaired"
grep -Fq 'User=mechos-setup' "$APPLY" || fail "SDDM does not hand first boot to setup account"
grep -Fq 'Session=plasma.desktop' "$APPLY" || fail "first-run setup is not pinned to Plasma"
grep -Fq '20-mechos-oobe-gate.conf' "$APPLY" || fail "SDDM is not ordered after firstboot authority"
grep -Fq 'MECHOS_TUTORIAL_WRAPPER_V2' "$APPLY" || fail "mode wrapper OOBE routing repair missing"
grep -Fq 'exec /usr/local/bin/mechos-oobe-start' "$APPLY" || fail "setup user does not use guarded OOBE launcher"
grep -Fq 'Account creation is still pending' "$APPLY" || fail "wrong-user OOBE launch is not blocked"
grep -Fq 'mechos-first-run-tutorial-start' "$APPLY" || fail "post-OOBE tutorial fallback missing"

# Issue 4: restart action receives a real helper with logind + PolicyKit fallback.
grep -Fq 'install_reboot_helper' "$APPLY" || fail "reboot helper installation missing"
grep -Fq 'loginctl reboot' "$APPLY" || fail "logind reboot path missing"
grep -Fq 'pkexec /usr/bin/systemctl reboot' "$APPLY" || fail "PolicyKit reboot fallback missing"
grep -Fq 'MECHOS_HOTFIX4_REBOOT_V1' "$APPLY" || fail "Update Center reboot backend patch missing"
grep -Fq '/usr/local/bin/mechos-reboot' "$APPLY" || fail "Update Center does not route to reboot helper"

# Issue 5: repair the wrapper path and provide a direct Plasma fallback when
# the VM systemd-user service fails, while still respecting OOBE gating.
grep -Fq 'MECHOS_HOTFIX4_DIRECT_MECHSCOPE_FALLBACK' "$APPLY" || fail "MechScope direct VM fallback missing"
grep -Fq 'nohup /usr/local/bin/mechscope' "$APPLY" || fail "MechScope fallback does not launch guarded runtime"
grep -Fq 'runtime_python_audit' "$APPLY" || fail "post-install Python runtime audit missing"

[ -s "$BUNDLE" ] || fail "Hotfix 4 bundle missing"
[ -s "$SUM" ] || fail "Hotfix 4 checksum missing"
(
  cd "$(dirname "$BUNDLE")"
  sha256sum -c "$(basename "$SUM")"
) >/dev/null || fail "Hotfix 4 checksum file does not verify"
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
tar --zstd -xpf "$BUNDLE" -C "$STAGE"

required=(
  usr/local/libexec/mechos-hotfix-0.3.0-4-apply
  usr/local/libexec/mechos-update-manifest-refresh-runtime
  usr/local/libexec/mechos-preoobe-update-auth-runtime
  usr/local/bin/mechos-oobe
  usr/local/libexec/mechos-oobe-apply
  usr/local/libexec/mechos-oobe-cleanup
  usr/local/bin/mechos-tutorial
  usr/local/bin/mechos-reboot
  usr/local/share/mechos/ui/fixed_canvas.py
  usr/local/share/mechos/ui/creator_shell.py
  usr/local/share/mechos/ui/mechscope_shell.py
  usr/lib/systemd/system/mechos-hotfix-0.3.0-4.service
  etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-4.service
)
for item in "${required[@]}"; do
  [ -e "$STAGE/$item" ] || [ -L "$STAGE/$item" ] || fail "bundle missing $item"
done

bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-4-apply" || fail "bundled apply helper syntax failed"
bash -n "$STAGE/usr/local/bin/mechos-reboot" || fail "bundled reboot helper syntax failed"
bash -n "$STAGE/usr/local/libexec/mechos-oobe-cleanup" || fail "bundled OOBE cleanup syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$STAGE/usr/local/bin/mechos-oobe" \
  "$STAGE/usr/local/libexec/mechos-oobe-apply" \
  "$STAGE/usr/local/bin/mechos-tutorial" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/mechscope_shell.py" \
  || fail "bundled Python runtime syntax failed"

grep -Fq 'Session=mechscope.desktop' "$STAGE/usr/local/libexec/mechos-oobe-apply" \
  || fail "bundled OOBE still hands permanent user to obsolete gaming session"
grep -Fq 'MECHOS_HOTFIX4_OOBE_GAMING_MODE_V1' "$STAGE/usr/local/libexec/mechos-oobe-apply" \
  || fail "bundled OOBE does not seed permanent gaming mode"
grep -Fq '/usr/local/bin/mechos-reboot' "$STAGE/usr/local/bin/mechos-oobe" \
  || fail "bundled OOBE still uses silent reboot path"

python3 - "$BUNDLE" <<'PY'
from pathlib import PurePosixPath
import subprocess,sys
bundle=sys.argv[1]
p=subprocess.run(['tar','--zstd','-tf',bundle],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if p.returncode: raise SystemExit('unable to list Hotfix 4 bundle')
allowed=(
 'usr/local/', 'usr/share/mechos/', 'usr/share/applications/',
 'usr/share/wayland-sessions/', 'usr/lib/systemd/', 'etc/mechos/',
 'etc/systemd/', 'etc/xdg/'
)
parents=set()
for prefix in allowed:
    parts=prefix.rstrip('/').split('/')
    for i in range(1,len(parts)): parents.add('/'.join(parts[:i]))
for raw in p.stdout.splitlines():
    name=raw.strip()
    while name.startswith('./'): name=name[2:]
    if not name or name=='.': continue
    path=PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts: raise SystemExit(f'unsafe bundle path: {name}')
    n=name.rstrip('/')
    if name.endswith('/') and n in parents: continue
    if not any(n==x.rstrip('/') or n.startswith(x) for x in allowed):
        raise SystemExit(f'path outside Update Center allowlist: {name}')
PY

python3 - "$MANIFEST" "$SHA" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: data=json.load(f)
if data.get('version') != '0.3.0-hotfix.4': raise SystemExit('stable manifest is not Hotfix 4')
if data.get('release_name') != 'MechOS v0.3.0 Hotfix 4': raise SystemExit('Hotfix 4 release name is wrong')
if data.get('bundle_sha256') != sys.argv[2]: raise SystemExit('manifest SHA does not match Hotfix 4 bundle')
if data.get('bundle_url') != 'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.4-update.tar.zst': raise SystemExit('Hotfix 4 URL is wrong')
if data.get('requires_reboot') is not True: raise SystemExit('Hotfix 4 must require reboot')
PY

rm -rf "$STAGE"; trap - EXIT
echo '[validate-hotfix-0.3.0-4] OK: six reported regressions are guarded; bundle, Python/shell runtimes, OOBE handoff, VM MechScope fallback, reboot path and manifest verify'
