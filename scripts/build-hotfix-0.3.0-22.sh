#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.22.2-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H21="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.21-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

# Start from the published cumulative Hotfix 21 payload, then refresh the
# activation helpers/launchers used by the recovery chain. Hotfix 22.2 carries
# a Hotfix15 activation helper that tolerates newer UnifiedStore class shapes
# and defers full Store replacement to Hotfix21 instead of aborting at layer 15.
[ -s "$H21" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-21.sh"
[ -s "$H21" ] || { echo 'Hotfix 21 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H21" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

install -m0755 "$ROOT/scripts/mechos-mode-launch-v19.sh" \
  "$STAGE/usr/local/bin/mechos-mode-launch"
install -m0755 "$ROOT/scripts/mechos-shell-route-v19.sh" \
  "$STAGE/usr/local/bin/mechos-shell-route"
install -m0755 "$ROOT/scripts/mechos-update-helper-v19.sh" \
  "$STAGE/usr/local/bin/mechos-update-helper"
install -m0755 "$ROOT/scripts/mechos-update-helper-v19.sh" \
  "$STAGE/usr/local/libexec/mechos-update-helper-v19"

# Always carry current activation helpers for every cumulative layer.
for n in 15 16 17 18 19 20 21; do
  install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-${n}-apply.sh" \
    "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-${n}-apply"
done

install -m0644 "$ROOT/src/mechos_ui/creator_real_icons_v22.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_real_icons_v22.py"
install -m0755 "$ROOT/scripts/mechos-creator-real-icons-owner-v22-patch.py" \
  "$STAGE/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-22-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-22-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service" <<'EOF'
[Unit]
Description=Apply cumulative MechOS v0.3.0 Hotfix 22.2 (15-22)
After=local-fs.target mechos-hotfix-0.3.0-21.service
Before=sddm.service display-manager.service
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-22.2-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-22-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sf /usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-22.service"

python3 -m py_compile \
  "$STAGE/usr/local/share/mechos/ui/creator_real_icons_v22.py" \
  "$STAGE/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch"
bash -n \
  "$STAGE/usr/local/bin/mechos-mode-launch" \
  "$STAGE/usr/local/bin/mechos-shell-route" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-15-apply" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-22-apply"

grep -Fq 'MECHOS_CREATOR_REAL_ICONS_V22' "$STAGE/usr/local/share/mechos/ui/creator_real_icons_v22.py"
grep -Fq 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' "$STAGE/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch"
grep -Fq 'MECHOS_HOTFIX15_CUMULATIVE_STORE_DEFER_V22' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-15-apply"
grep -Fq 'MECHOS_MODE_LAUNCH_V15' "$STAGE/usr/local/bin/mechos-mode-launch"
grep -Fq 'MECHOS_MODE_LAUNCH_V16' "$STAGE/usr/local/bin/mechos-mode-launch"
grep -Fq 'MECHOS_MODE_LAUNCH_V19' "$STAGE/usr/local/bin/mechos-mode-launch"
grep -Fq 'MECHOS_SHELL_ROUTE_V16' "$STAGE/usr/local/bin/mechos-shell-route"
grep -Fq 'MECHOS_SHELL_ROUTE_V19' "$STAGE/usr/local/bin/mechos-shell-route"
grep -Fq 'MECHOS_HOTFIX17_HELPER_WARNING_FIX' "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'After=local-fs.target mechos-hotfix-0.3.0-21.service' "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service"
grep -Fq 'ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-22.2-applied' "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service"
! grep -Fq 'Requires=mechos-hotfix-0.3.0-21.service' "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service"
! grep -Fq 'ConditionPathExists=/var/lib/mechos/installed' "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service"

for n in 15 16 17 18 19 20 21; do
  required="$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-${n}-apply"
  [ -x "$required" ] || { echo "Cumulative apply helper missing: $required" >&2; exit 1; }
  bash -n "$required"
done
for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix15-runtime-patch" \
  "$STAGE/usr/local/libexec/mechos-hotfix15-game-browser-patch" \
  "$STAGE/usr/local/libexec/mechos-hotfix16-single-shell-patch" \
  "$STAGE/usr/local/libexec/mechos-hotfix17-updater-patch" \
  "$STAGE/usr/local/libexec/mechos-pacman-health-v18" \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/bin/mechos-reboot" \
  "$STAGE/usr/local/bin/mechos-update-rescue" \
  "$STAGE/usr/local/bin/mechscope-session" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-core-v20" \
  "$STAGE/usr/local/libexec/mechos-hotfix21-unified-store-patch"; do
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
  'version':'0.3.0-hotfix.22.2',
  'release_name':'MechOS v0.3.0 Hotfix 22 Cumulative Revision 2',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Hotfix 22 cumulative revision 2. Fixes the direct Hotfix 14 recovery chain discovered in testing: Hotfix 15 no longer aborts when the installed Unified Store uses a newer class shape without the legacy browse_selected API. Creator and launcher checks still activate at Hotfix 15, while Store replacement safely defers to Hotfix 21. The bundle remains cumulative with Hotfixes 15-21, updater recovery, package reliability, hardware MechScope fallback, root-safe transactions, the native Unified Store and Hotfix 22 application-owned Creator icons.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.22.2-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 22.2 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
