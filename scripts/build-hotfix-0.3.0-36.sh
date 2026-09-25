#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX36_INTEL_UMA_INTEGRATION_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.36-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H35="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.35-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H35" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-35.sh"
[ -s "$H35" ] || { echo 'Hotfix 35 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H35" -C "$STAGE"

mkdir -p "$STAGE/usr/local/libexec" "$STAGE/usr/lib/systemd/system" "$STAGE/etc/systemd/system/multi-user.target.wants"
install -m0755 "$ROOT/scripts/mechos-intel-uma-session-patch-v36.py" "$STAGE/usr/local/libexec/mechos-intel-uma-session-patch-v36"
install -m0755 "$ROOT/scripts/mechos-intel-uma-preflight-v36.sh" "$STAGE/usr/local/libexec/mechos-intel-uma-preflight-v36"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-36-apply.sh" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-36-apply"

python3 "$STAGE/usr/local/libexec/mechos-intel-uma-session-patch-v36" "$STAGE/usr/local/bin/mechscope-session"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-36.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 36 Intel UMA MechScope integration
After=local-fs.target mechos-hotfix-0.3.0-35.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-36-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-36-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-36.service "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-36.service"

bash -n "$STAGE/usr/local/bin/mechscope-session" "$STAGE/usr/local/libexec/mechos-intel-uma-preflight-v36" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-36-apply"
python3 -m py_compile "$STAGE/usr/local/libexec/mechos-intel-uma-session-patch-v36"
grep -Fq 'MECHOS_INTEL_UMA_INTEGRATION_V36' "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'GBM_BACKEND=nvidia-drm' "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'run_gamescope primary' "$STAGE/usr/local/bin/mechscope-session"

DAY="$(date -u +%F)"
EPOCH="$(date -u -d "$DAY 00:00:00" +%s)"
rm -f "$BUNDLE" "$SUM"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,'channel':'stable','version':'0.3.0-hotfix.36',
  'release_name':'MechOS v0.3.0 Hotfix 36',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative Intel UMA MechScope integration. Preserves the existing MechScope runtime, AMD/NVIDIA behavior and hybrid-GPU paths. Adds Intel-only UMA detection, Intel DRM/Vulkan preflight, conservative Gamescope arguments, and automatic use of the existing supervised Plasma fallback when Intel Gamescope prerequisites are unavailable. Includes all Hotfix 35 fixes.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.36-update.tar.zst',
  'bundle_sha256':sha,'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 36 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
