#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_031_PHASE1_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BUNDLE="$ROOT/updates/bundles/MechOS-0.3.1-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
BASE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.35-update.tar.zst"

mkdir -p "$(dirname "$BUNDLE")"
[ -s "$BASE" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-35.sh"
[ -s "$BASE" ] || { echo 'Hotfix 35 cumulative base bundle missing' >&2; exit 1; }

tar --warning=no-timestamp --zstd -xpf "$BASE" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/share/mechos/wallpapers/0.3.1" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

for i in $(seq -w 1 16); do
  src="$ROOT/overlay/rootfs/usr/share/backgrounds/mechos/mechos-wallpaper-$i.jpg"
  dst="$STAGE/usr/share/mechos/wallpapers/0.3.1/mechos-wallpaper-$i.jpg"
  [ -s "$src" ] || { echo "Missing 0.3.1 wallpaper source: $src" >&2; exit 1; }
  install -m0644 "$src" "$dst"
done

install -m0755 "$ROOT/scripts/mechos-0.3.1-phase1-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-0.3.1-phase1-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-0.3.1-phase1.service" <<'EOF'
[Unit]
Description=Apply MechOS 0.3.1 Phase 1 wallpaper collection
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/0.3.1-phase1-wallpapers-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-0.3.1-phase1-apply

[Install]
WantedBy=multi-user.target
EOF

ln -sfn /usr/lib/systemd/system/mechos-0.3.1-phase1.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-0.3.1-phase1.service"

bash -n "$STAGE/usr/local/libexec/mechos-0.3.1-phase1-apply"
grep -Fq 'MECHOS_031_PHASE1_WALLPAPERS_V1' "$STAGE/usr/local/libexec/mechos-0.3.1-phase1-apply"

# Keep the proven Hotfix 35 cumulative runtime/update machinery in the release.
for required in \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechscope" \
  "$STAGE/usr/local/bin/mechos-unified-store" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v25"; do
  [ -e "$required" ] || { echo "Cumulative component missing: $required" >&2; exit 1; }
done

DAY="$(date -u +%F)"
EPOCH="$(date -u -d "$DAY 00:00:00" +%s)"
rm -f "$BUNDLE" "$SUM"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
  --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.1',
  'release_name':'MechOS v0.3.1 — Phase 1',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'MechOS 0.3.1 rollout begins with the cumulative Hotfix 35 base plus the official 16-wallpaper desktop collection and versioned branding payload. KDE Plasma receives all 16 selectable wallpapers after reboot, the approved first wallpaper updates the packaged MechOS default asset, and existing user wallpaper selections are preserved. This is Phase 1 of the 0.3.1 roadmap; additional 0.3.1 roadmap features will continue through reviewed cumulative updates.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.1-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'MechOS 0.3.1 Phase 1 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
