#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-6-apply.sh"
REBOOT="$ROOT/scripts/mechos-reboot-hotfix6.sh"
CANVAS="$ROOT/src/mechos_ui/fixed_canvas.py"
BUILDER="$ROOT/scripts/build-hotfix-0.3.0-6.sh"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.6-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
fail(){ echo "[validate-hotfix-0.3.0-6] ERROR: $*" >&2; exit 1; }

for f in "$APPLY" "$REBOOT" "$BUILDER"; do
  [ -f "$f" ] || fail "missing source: $f"
  bash -n "$f" || fail "shell syntax failed: $f"
done
[ -f "$CANVAS" ] || fail 'fixed_canvas.py missing'
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$CANVAS" || fail 'fixed canvas Python syntax failed'

grep -Fq 'org.kde.Shutdown.logoutAndReboot' "$REBOOT" || fail 'KDE reboot authority missing'
grep -Fq 'org.freedesktop.login1.Manager Reboot b true' "$REBOOT" || fail 'systemd-logind reboot fallback missing'
grep -Fq 'pkexec /usr/bin/systemctl reboot' "$REBOOT" || fail 'visible PolicyKit fallback missing'
if grep -Fq 'loginctl reboot' "$REBOOT"; then
  fail 'invalid loginctl reboot command returned'
fi

grep -Fq 'MECHOS_HOTFIX6_REBOOT_V2' "$APPLY" || fail 'Update Center reboot V2 patch missing'
grep -Fq 'subprocess.run(' "$APPLY" || fail 'Update Center does not inspect reboot helper result'
grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V3' "$CANVAS" || fail 'VM geometry V3 marker missing'
grep -Fq "compact = bool(subtitle)" "$CANVAS" || fail 'short-button compacting missing'
grep -Fq 'compact_label = s < 0.72' "$CANVAS" || fail 'narrow-label wrapping guard missing'

[ -s "$BUNDLE" ] || fail 'Hotfix 6 bundle missing; run builder first'
[ -s "$SUM" ] || fail 'Hotfix 6 checksum missing'
(
  cd "$(dirname "$BUNDLE")"
  sha256sum -c "$(basename "$SUM")"
) >/dev/null || fail 'Hotfix 6 checksum does not verify'
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar --zstd -xpf "$BUNDLE" -C "$TMP"
required=(
  usr/local/bin/mechos-reboot
  usr/local/libexec/mechos-hotfix-0.3.0-6-apply
  usr/local/share/mechos/ui/fixed_canvas.py
  usr/lib/systemd/system/mechos-hotfix-0.3.0-6.service
)
for f in "${required[@]}"; do [ -e "$TMP/$f" ] || fail "bundle missing required file: $f"; done
[ -L "$TMP/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-6.service" ] || fail 'Hotfix 6 service enable symlink missing'
bash -n "$TMP/usr/local/bin/mechos-reboot" || fail 'bundled reboot helper syntax failed'
bash -n "$TMP/usr/local/libexec/mechos-hotfix-0.3.0-6-apply" || fail 'bundled apply helper syntax failed'
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TMP/usr/local/share/mechos/ui/fixed_canvas.py" || fail 'bundled fixed canvas syntax failed'
grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V3' "$TMP/usr/local/share/mechos/ui/fixed_canvas.py" || fail 'bundle carries old VM canvas'
if grep -Fq 'loginctl reboot' "$TMP/usr/local/bin/mechos-reboot"; then fail 'bundle carries invalid reboot command'; fi

python3 - "$MANIFEST" "$SHA" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: data=json.load(f)
if data.get('version') != '0.3.0-hotfix.6': raise SystemExit('stable manifest is not Hotfix 6')
if data.get('release_name') != 'MechOS v0.3.0 Hotfix 6': raise SystemExit('Hotfix 6 release name is wrong')
if data.get('bundle_sha256') != sys.argv[2]: raise SystemExit('manifest SHA does not match bundle')
if data.get('bundle_url') != 'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.6-update.tar.zst': raise SystemExit('Hotfix 6 URL is wrong')
if data.get('requires_reboot') is not True: raise SystemExit('Hotfix 6 must require reboot')
PY

echo '[validate-hotfix-0.3.0-6] OK: reboot authority, Update Center result handling, VM compact controls, bundle checksum and manifest verify'
