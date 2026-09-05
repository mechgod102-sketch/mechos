#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-5-apply.sh"
RUNTIME="$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh"
LAUNCHER="$ROOT/scripts/mechos-mode-launch-hotfix5.sh"
BUILDER="$ROOT/scripts/build-hotfix-0.3.0-5.sh"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.5-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
fail(){ echo "[validate-hotfix-0.3.0-5] ERROR: $*" >&2; exit 1; }

for f in "$APPLY" "$RUNTIME" "$LAUNCHER" "$BUILDER"; do
  [ -f "$f" ] || fail "missing source: $f"
  bash -n "$f" || fail "shell syntax failed: $f"
done

grep -Fq 'MECHOS_HOTFIX5_VM_DIRECT_ROUTER_V1' "$LAUNCHER" || fail 'VM direct-router marker missing'
grep -Fq '/usr/local/bin/mechos-vm-mode-runtime "$MODE"' "$LAUNCHER" || fail 'VM launcher does not directly call VM runtime'
grep -Fq 'CONTROL=/usr/local/bin/mechos-gaming-layer-control' "$LAUNCHER" || fail 'hardware controller fallback missing'
grep -Fq 'systemd-detect-virt' "$LAUNCHER" || fail 'VM detection missing from launcher'

grep -Fq 'actual_mechscope' "$RUNTIME" || fail 'real MechScope resolver missing'
grep -Fq '/usr/local/bin/mechscope.real' "$RUNTIME" || fail 'wrapped MechScope real-backend fallback missing'
grep -Fq 'python3 -m py_compile' "$RUNTIME" || fail 'MechScope Python health check missing'
grep -Fq 'MECHOS_DISABLE_GAMESCOPE=1' "$RUNTIME" || fail 'VM Gamescope bypass missing'
grep -Fq 'oobe-complete' "$RUNTIME" || fail 'OOBE completion gate missing'
grep -Fq 'mechos-setup' "$RUNTIME" || fail 'setup-account OOBE routing missing'
grep -Fq 'nohup "$target"' "$RUNTIME" || fail 'direct MechScope Plasma launch missing'
grep -Fq 'vm-mechscope-launch.log' "$RUNTIME" || fail 'dedicated VM MechScope log missing'

# Hotfix 4's gap was validating a patch concept without shipping a complete VM
# routing chain. Hotfix 5 must carry both executable endpoints in the bundle.
[ -s "$BUNDLE" ] || fail 'Hotfix 5 bundle missing; run builder first'
[ -s "$SUM" ] || fail 'Hotfix 5 checksum missing'
(
  cd "$(dirname "$BUNDLE")"
  sha256sum -c "$(basename "$SUM")"
) >/dev/null || fail 'Hotfix 5 checksum file does not verify'
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
tar --zstd -xpf "$BUNDLE" -C "$TMP"
required=(
  usr/local/bin/mechos-vm-mode-runtime
  usr/local/bin/mechos-mode-launch
  usr/local/libexec/mechos-hotfix-0.3.0-5-apply
  usr/lib/systemd/system/mechos-hotfix-0.3.0-5.service
  etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-5.service
  etc/xdg/autostart/mechos-vm-mode-runtime.desktop
  usr/share/applications/mechos-return-gaming.desktop
  usr/share/wayland-sessions/mechscope.desktop
)
for f in "${required[@]}"; do
  [ -e "$TMP/$f" ] || [ -L "$TMP/$f" ] || fail "bundle missing required file: $f"
done
bash -n "$TMP/usr/local/bin/mechos-vm-mode-runtime" || fail 'bundled VM runtime syntax failed'
bash -n "$TMP/usr/local/bin/mechos-mode-launch" || fail 'bundled mode launcher syntax failed'
bash -n "$TMP/usr/local/libexec/mechos-hotfix-0.3.0-5-apply" || fail 'bundled apply helper syntax failed'
grep -Fq 'MECHOS_HOTFIX5_VM_DIRECT_ROUTER_V1' "$TMP/usr/local/bin/mechos-mode-launch" || fail 'bundled launcher is not Hotfix 5 direct router'
grep -Fq '/usr/local/bin/mechscope.real' "$TMP/usr/local/bin/mechos-vm-mode-runtime" || fail 'bundled runtime cannot resolve real MechScope backend'
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$TMP/usr/share/applications/mechos-return-gaming.desktop" || fail 'bundled desktop shortcut bypasses repaired launcher'
grep -Fq 'Exec=/usr/local/bin/mechos-vm-mode-runtime boot' "$TMP/etc/xdg/autostart/mechos-vm-mode-runtime.desktop" || fail 'bundled VM boot autostart missing'

python3 - "$MANIFEST" "$SHA" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: data=json.load(f)
if data.get('version') != '0.3.0-hotfix.5': raise SystemExit('stable manifest is not Hotfix 5')
if data.get('release_name') != 'MechOS v0.3.0 Hotfix 5': raise SystemExit('Hotfix 5 release name is wrong')
if data.get('bundle_sha256') != sys.argv[2]: raise SystemExit('manifest SHA does not match bundle')
if data.get('bundle_url') != 'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.5-update.tar.zst': raise SystemExit('Hotfix 5 URL is wrong')
if data.get('requires_reboot') is not True: raise SystemExit('Hotfix 5 must require reboot')
PY

echo '[validate-hotfix-0.3.0-5] OK: VM launcher/runtime are self-contained, OOBE-safe, direct-Plasma MechScope routing is present, bundle checksum and stable manifest verify'
