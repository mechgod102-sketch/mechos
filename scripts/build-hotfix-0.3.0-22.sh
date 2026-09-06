#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.22-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H21="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.21-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H21" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-21.sh"
[ -s "$H21" ] || { echo 'Hotfix 21 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H21" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

install -m0644 "$ROOT/src/mechos_ui/creator_real_icons_v22.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_real_icons_v22.py"
install -m0755 "$ROOT/scripts/mechos-creator-real-icons-owner-v22-patch.py" \
  "$STAGE/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-22-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-22-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 22 Creator real application icons
After=local-fs.target mechos-hotfix-0.3.0-21.service
Requires=mechos-hotfix-0.3.0-21.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-22-applied

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
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-22-apply"

grep -Fq 'MECHOS_CREATOR_REAL_ICONS_V22' "$STAGE/usr/local/share/mechos/ui/creator_real_icons_v22.py"
grep -Fq 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' "$STAGE/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch"
grep -Fq 'After=local-fs.target mechos-hotfix-0.3.0-21.service' "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-22.service"

# Preserve the stable native Unified Store and root-safe updater chain.
for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix21-unified-store-patch" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-21-apply" \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/bin/mechos-reboot" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14"; do
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
  'version':'0.3.0-hotfix.22',
  'release_name':'MechOS v0.3.0 Hotfix 22',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Creator icon fidelity repair. Creator Mode and Creator Store now prefer application-owned icons discovered from installed desktop entries, icon themes, Flatpak exports and Flatpak AppStream caches. MechOS no longer replaces creator application icons with generated monogram badges when a real application icon is available; generated badges remain the offline fallback for missing/vendor-only tools and MechOS navigation controls. Hotfix 22 is cumulative with Hotfix 21 native Unified Store and Hotfix 20 root-safe updater protections.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.22-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 22 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
