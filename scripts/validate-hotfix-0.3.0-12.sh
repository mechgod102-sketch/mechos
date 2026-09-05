#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.12-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash -n "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh"
bash -n "$ROOT/scripts/mechos-mode-launch-hotfix10.sh"
bash -n "$ROOT/scripts/mechos-hotfix-0.3.0-12-apply.sh"

grep -Fq 'MECHOS_VM_MECHSCOPE_NO_PYCACHE_HEALTHCHECK_V4' "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh"
grep -Fq 'MECHOS_HOTFIX12_NO_PYCACHE_HEALTHCHECK_V1' "$ROOT/scripts/mechos-mode-launch-hotfix10.sh"
grep -Fq "compile(source, str(p), 'exec')" "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh"
grep -Fq "compile(source, str(p), 'exec')" "$ROOT/scripts/mechos-mode-launch-hotfix10.sh"
! grep -Fq 'python3 -m py_compile "$target"' "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh"
! grep -Fq 'python3 -m py_compile "$target"' "$ROOT/scripts/mechos-mode-launch-hotfix10.sh"

[ -s "$BUNDLE" ]
[ -s "$SUM" ]
(cd "$(dirname "$BUNDLE")" && sha256sum -c "$(basename "$SUM")")
tar --zstd -xpf "$BUNDLE" -C "$TMP"

for f in \
  "$TMP/usr/local/bin/mechos-vm-mode-runtime" \
  "$TMP/usr/local/bin/mechos-mode-launch" \
  "$TMP/usr/local/libexec/mechos-hotfix-0.3.0-12-apply" \
  "$TMP/usr/lib/systemd/system/mechos-hotfix-0.3.0-12.service"; do
  [ -f "$f" ]
done
[ -L "$TMP/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-12.service" ]

grep -Fq 'MECHOS_VM_MECHSCOPE_NO_PYCACHE_HEALTHCHECK_V4' "$TMP/usr/local/bin/mechos-vm-mode-runtime"
grep -Fq 'MECHOS_HOTFIX12_NO_PYCACHE_HEALTHCHECK_V1' "$TMP/usr/local/bin/mechos-mode-launch"
! grep -Fq 'python3 -m py_compile "$target"' "$TMP/usr/local/bin/mechos-vm-mode-runtime"
! grep -Fq 'python3 -m py_compile "$target"' "$TMP/usr/local/bin/mechos-mode-launch"

python3 - "$MANIFEST" <<'PY'
import json,sys
p=sys.argv[1]
data=json.load(open(p,encoding='utf-8'))
assert data['version']=='0.3.0-hotfix.12', data
assert data['release_name']=='MechOS v0.3.0 Hotfix 12', data
assert data['requires_reboot'] is True, data
assert data['bundle_url'].endswith('MechOS-0.3.0-hotfix.12-update.tar.zst'), data
PY

echo 'Hotfix 12 validation passed.'
