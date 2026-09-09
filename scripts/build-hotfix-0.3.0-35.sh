#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX35_UNIFIED_STORE_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.35-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H34="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.34-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H34" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-34.sh"
[ -s "$H34" ] || { echo 'Hotfix 34 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H34" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

install -m0755 "$ROOT/scripts/mechos-unified-store-v35.py" \
  "$STAGE/usr/local/bin/mechos-unified-store"
install -m0755 "$ROOT/scripts/mechos-launcher-bootstrap-v35.sh" \
  "$STAGE/usr/local/libexec/mechos-launcher-bootstrap-v35"
install -m0755 "$ROOT/scripts/mechos-hotfix35-store-route-patch.py" \
  "$STAGE/usr/local/libexec/mechos-hotfix35-store-route-patch"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-35-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-35-apply"

# Patch the cumulative HF33 source-owned runtime in the bundle itself so the
# first post-update MechScope launch already routes Store to the V35 app.
python3 "$STAGE/usr/local/libexec/mechos-hotfix35-store-route-patch" \
  "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"

cat >"$STAGE/usr/share/applications/mechos-unified-store.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Unified Store
Comment=Browse MechOS game stores and manage launchers
Exec=/usr/local/bin/mechos-unified-store
TryExec=/usr/local/bin/mechos-unified-store
Icon=applications-games
Categories=Game;Utility;
Terminal=false
EOF

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-35.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 35 source-owned Unified Store
After=local-fs.target mechos-hotfix-0.3.0-34.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-35-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-35-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-35.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-35.service"

python3 -m py_compile \
  "$STAGE/usr/local/bin/mechos-unified-store" \
  "$STAGE/usr/local/libexec/mechos-hotfix35-store-route-patch" \
  "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"
bash -n \
  "$STAGE/usr/local/libexec/mechos-launcher-bootstrap-v35" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-35-apply"

grep -Fq 'MECHOS_UNIFIED_STORE_V35' "$STAGE/usr/local/bin/mechos-unified-store"
grep -Fq 'MECHOS_LAUNCHER_BOOTSTRAP_V35' "$STAGE/usr/local/libexec/mechos-launcher-bootstrap-v35"
grep -Fq 'MECHOS_MECHSCOPE_UNIFIED_STORE_ROUTE_V35' "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"
grep -Fq 'MECHOS_HOTFIX35_UNIFIED_STORE_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-35-apply"
grep -Fq 'View in Unified Store' "$STAGE/usr/local/bin/mechos-unified-store"
grep -Fq 'Install Launcher' "$STAGE/usr/local/bin/mechos-unified-store"
grep -Fq 'Steam' "$STAGE/usr/local/bin/mechos-unified-store"
grep -Fq 'Epic Games' "$STAGE/usr/local/bin/mechos-unified-store"
grep -Fq 'GOG.com' "$STAGE/usr/local/bin/mechos-unified-store"
grep -Fq 'Amazon Games' "$STAGE/usr/local/bin/mechos-unified-store"
grep -Fq 'Lutris' "$STAGE/usr/local/bin/mechos-unified-store"

# HF35 depends on the existing fixed V15 provider/catalog layer and preserves
# the HF33/HF34 MechScope architecture.
for required in \
  "$STAGE/usr/local/libexec/mechos-provider-bootstrap-v15" \
  "$STAGE/usr/local/libexec/mechos-game-catalog-v15" \
  "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33" \
  "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31" \
  "$STAGE/usr/local/bin/mechscope-session" \
  "$STAGE/usr/local/share/mechos/mechscope/mechscope_shell.py" \
  "$STAGE/usr/local/bin/mechos-update-helper"; do
  [ -e "$required" ] || { echo "Cumulative component missing: $required" >&2; exit 1; }
done

grep -Fq 'MECHOS_PROVIDER_BOOTSTRAP_V15' "$STAGE/usr/local/libexec/mechos-provider-bootstrap-v15"
grep -Fq 'MechOS-Unified-Store/0.3.0-hotfix.15' "$STAGE/usr/local/libexec/mechos-game-catalog-v15"
grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33' "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"
grep -Fq 'MECHOS_MECHSCOPE_RESPONSIVE_UI_V34' "$STAGE/usr/local/share/mechos/mechscope/mechscope_shell.py"

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
  'version':'0.3.0-hotfix.35',
  'release_name':'MechOS v0.3.0 Hotfix 35',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative source-owned Unified Store release. Replaces the Store redirect behavior with a dedicated MechOS Unified Store page that displays Steam, Epic Games, GOG.com and Amazon Games sources in-app, keeps supported game search results inside MechOS, and adds installed/not-installed status plus Install/Launch controls for Steam, Heroic Games Launcher and Lutris. Launcher installation uses fixed MechOS launcher IDs only; Steam and Lutris use the system package path with PolicyKit approval and Heroic uses the existing user-scoped Flatpak bootstrap. Both the MechScope dashboard Store action and the legacy mechscope --store compatibility entry now prefer /usr/local/bin/mechos-unified-store before Discovery fallbacks. Includes all Hotfix 34 fixes.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.35-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 35 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
