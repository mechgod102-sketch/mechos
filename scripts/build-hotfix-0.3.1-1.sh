#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX_0311_LEGACY_GPU_UPDATE_RELIABILITY_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BASE="$ROOT/updates/bundles/MechOS-0.3.1-update.tar.zst"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.1-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p "$(dirname "$BUNDLE")"
[ -s "$BASE" ] || bash "$ROOT/scripts/build-mechos-0.3.1.sh"
[ -s "$BASE" ] || { echo 'MechOS 0.3.1 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$BASE" -C "$STAGE"

mkdir -p   "$STAGE/usr/local/bin"   "$STAGE/usr/local/libexec"   "$STAGE/usr/share/applications"   "$STAGE/usr/lib/systemd/system"   "$STAGE/etc/systemd/system/multi-user.target.wants"

# Preserve the complete existing 0.3.1 GPU/session/UI stack and patch it
# additively. These files must exist in the cumulative base or the build fails.
for required in   "$STAGE/usr/local/bin/mechos-gpu-setup"   "$STAGE/usr/local/bin/mechscope-session"   "$STAGE/usr/local/libexec/mechos-031-control-suite"; do
  [ -e "$required" ] || { echo "Existing 0.3.1 component missing: $required" >&2; exit 1; }
done

# Reassert the repaired updater surfaces so installed 0.3.1 systems receive
# the nounset, timeout and downgrade-protection fixes through this hotfix.
install -m0755 "$ROOT/scripts/mechos-update-helper-v37.sh"   "$STAGE/usr/local/bin/mechos-update-helper"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py"   "$STAGE/usr/local/libexec/mechos-update-center-v8-rescue.py"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v14.sh"   "$STAGE/usr/local/libexec/mechos-update-transaction-v14"

# Add the legacy compatibility layer, then integrate it into the existing GPU
# setup, MechScope session and GPU Compatibility UI.
install -m0755 "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"   "$STAGE/usr/local/bin/mechos-legacy-gpu-setup"
install -m0755 "$ROOT/scripts/mechos-legacy-gpu-session-patch-v0311.py"   "$STAGE/usr/local/libexec/mechos-legacy-gpu-session-patch-v0311"
install -m0755 "$ROOT/scripts/mechos-legacy-gpu-control-patch-v0311.py"   "$STAGE/usr/local/libexec/mechos-legacy-gpu-control-patch-v0311"
install -m0755 "$ROOT/scripts/mechos-gpu-setup-integration-v0311.py"   "$STAGE/usr/local/libexec/mechos-gpu-setup-integration-v0311"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.1-1-apply.sh"   "$STAGE/usr/local/libexec/mechos-hotfix-0.3.1-1-apply"

python3 "$ROOT/scripts/mechos-gpu-setup-integration-v0311.py"   "$STAGE/usr/local/bin/mechos-gpu-setup"
python3 "$ROOT/scripts/mechos-legacy-gpu-session-patch-v0311.py"   "$STAGE/usr/local/bin/mechscope-session"
python3 "$ROOT/scripts/mechos-legacy-gpu-control-patch-v0311.py"   "$STAGE/usr/local/libexec/mechos-031-control-suite"

cat >"$STAGE/usr/share/applications/mechos-legacy-gpu.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Legacy GPU Compatibility
Comment=Compatibility diagnostics for older NVIDIA and AMD graphics
Exec=/usr/local/bin/mechos-legacy-gpu-setup --report
Icon=video-display
Categories=System;Settings;
Terminal=true
EOF

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.1-1.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.1 Hotfix 1 legacy GPU and updater reliability integration
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.1-1-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.1-1-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.1-1.service   "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.1-1.service"

bash -n   "$STAGE/usr/local/bin/mechos-gpu-setup"   "$STAGE/usr/local/bin/mechos-legacy-gpu-setup"   "$STAGE/usr/local/bin/mechscope-session"   "$STAGE/usr/local/bin/mechos-update-helper"   "$STAGE/usr/local/libexec/mechos-hotfix-0.3.1-1-apply"
python3 -m py_compile   "$STAGE/usr/local/libexec/mechos-031-control-suite"   "$STAGE/usr/local/libexec/mechos-update-center-v8.py"   "$STAGE/usr/local/libexec/mechos-legacy-gpu-session-patch-v0311"   "$STAGE/usr/local/libexec/mechos-legacy-gpu-control-patch-v0311"   "$STAGE/usr/local/libexec/mechos-gpu-setup-integration-v0311"

grep -Fq 'MECHOS_GPU_SETUP_INTEGRATION_V0311' "$STAGE/usr/local/libexec/mechos-gpu-setup-integration-v0311"
grep -Fq 'MECHOS_LEGACY_GPU_SESSION_PATCH_V0311' "$STAGE/usr/local/libexec/mechos-legacy-gpu-session-patch-v0311"
grep -Fq 'MECHOS_LEGACY_GPU_CONTROL_PATCH_V0311' "$STAGE/usr/local/libexec/mechos-legacy-gpu-control-patch-v0311"
grep -Fq 'mechos-gpu-setup-integration-v0311 /usr/local/bin/mechos-gpu-setup' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.1-1-apply"
grep -Fq 'PACKAGES+=(nvidia-open nvidia-utils lib32-nvidia-utils nvidia-prime)' "$ROOT/scripts/mechos-gpu-setup-integration-v0311.py"
grep -Fq 'PACKAGES+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver)' "$ROOT/scripts/mechos-gpu-setup-integration-v0311.py"
grep -Fq 'MECHOS_UPDATE_HELPER_V37_SIGNED_MANIFEST_V1' "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'Refusing MechOS downgrade' "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'timeout=30' "$STAGE/usr/local/libexec/mechos-update-center-v8.py"

DAY="$(date -u +%F)"
EPOCH="$(date -u -d "$DAY 00:00:00" +%s)"
rm -f "$BUNDLE" "$SUM"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner   --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.1-hotfix.1',
  'release_name':'MechOS v0.3.1 Hotfix 1',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Additive legacy GPU compatibility and Update Center reliability hotfix. Preserves the existing 0.3.1 modern AMD/NVIDIA/Intel GPU paths while adding legacy NVIDIA branch detection, safe Nouveau/Mesa fallback, legacy Radeon handling, driver-aware NVIDIA environment selection, Vulkan-gated Gamescope fallback, and integrated legacy GPU diagnostics. Also ships the repaired v37 signed updater, 30-second Update Center status timeout, and downgrade protection so an older 0.3.0 hotfix can never be offered as an upgrade over 0.3.1.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.1-hotfix.1-update.tar.zst',
  'bundle_sha256':sha,
  'signature_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json.sig',
  'signing_key_id':'mechos-stable-2026-01',
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'MechOS 0.3.1 Hotfix 1 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
