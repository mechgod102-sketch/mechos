#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_031_FULL_V1

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

mkdir -p   "$STAGE/usr/share/mechos/wallpapers/0.3.1"   "$STAGE/usr/share/mechos/0.3.1"   "$STAGE/usr/local/bin"   "$STAGE/usr/local/libexec"   "$STAGE/usr/share/applications"   "$STAGE/usr/lib/systemd/system"   "$STAGE/usr/lib/systemd/user"   "$STAGE/etc/systemd/system/multi-user.target.wants"

# Official 0.3.1 wallpaper collection.
for i in $(seq -w 1 16); do
  src="$ROOT/overlay/rootfs/usr/share/backgrounds/mechos/mechos-wallpaper-$i.jpg"
  dst="$STAGE/usr/share/mechos/wallpapers/0.3.1/mechos-wallpaper-$i.jpg"
  [ -s "$src" ] || { echo "Missing 0.3.1 wallpaper source: $src" >&2; exit 1; }
  install -m0644 "$src" "$dst"
done

install -m0755 "$ROOT/scripts/mechos-0.3.1-phase1-apply.sh"   "$STAGE/usr/local/libexec/mechos-0.3.1-phase1-apply"
install -m0755 "$ROOT/scripts/mechos-031-control-suite.py"   "$STAGE/usr/local/libexec/mechos-031-control-suite"
install -m0755 "$ROOT/scripts/mechos-bridge-v031.py"   "$STAGE/usr/local/libexec/mechos-bridge-v031"
install -m0755 "$ROOT/scripts/mechos-game-run-v031.py"   "$STAGE/usr/local/bin/mechos-game-run"

install -m0644 "$ROOT/data/mechos-0.3.1-feature-registry.json"   "$STAGE/usr/share/mechos/0.3.1/feature-registry.json"
install -m0644 "$ROOT/data/mechos-0.3.1-game-compatibility.json"   "$STAGE/usr/share/mechos/0.3.1/game-compatibility.json"
install -m0644 "$ROOT/data/mechos-0.3.1-creator-tools.json"   "$STAGE/usr/share/mechos/0.3.1/creator-tools.json"

if [ -s "$ROOT/overlay/rootfs/usr/share/backgrounds/mechos/mechscope-loading.png" ]; then
  install -m0644 "$ROOT/overlay/rootfs/usr/share/backgrounds/mechos/mechscope-loading.png"     "$STAGE/usr/share/mechos/0.3.1/mechscope-loading.png"
fi

make_wrapper(){
  local name="$1" mode="$2"
  cat >"$STAGE/usr/local/bin/$name" <<EOF
#!/usr/bin/env bash
exec /usr/bin/python3 /usr/local/libexec/mechos-031-control-suite "$mode" "\$@"
EOF
  chmod 0755 "$STAGE/usr/local/bin/$name"
}
make_wrapper mechos-downloads downloads
make_wrapper mechos-network network
make_wrapper mechos-browser browser
make_wrapper mechos-gpu gpu
make_wrapper mechos-inputs inputs
make_wrapper mechos-compat compat
make_wrapper mechos-creator creator
make_wrapper mechos-power power
make_wrapper mechos-crashes crashes
make_wrapper mechos-bridge-settings bridge

cat >"$STAGE/usr/lib/systemd/user/mechos-bridge.service" <<'EOF'
[Unit]
Description=MechOS 0.3.1 Companion Bridge
After=graphical-session.target network-online.target
ConditionPathExists=/var/lib/mechos/installed

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/libexec/mechos-bridge-v031
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.config/mechos %h/.local/share/mechos %h/.local/state/mechos

[Install]
WantedBy=default.target
EOF

cat >"$STAGE/usr/lib/systemd/system/mechos-0.3.1-phase1.service" <<'EOF'
[Unit]
Description=Apply MechOS 0.3.1 wallpaper collection
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
ln -sfn /usr/lib/systemd/system/mechos-0.3.1-phase1.service   "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-0.3.1-phase1.service"

desktop(){
  local file="$1" name="$2" exec="$3" icon="$4" categories="$5"
  cat >"$STAGE/usr/share/applications/$file" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Exec=$exec
Icon=$icon
Categories=$categories
Terminal=false
EOF
}
desktop mechos-downloads.desktop "MechOS Downloads & Updates" /usr/local/bin/mechos-downloads system-software-update "System;Utility;"
desktop mechos-network.desktop "MechOS Network Setup" /usr/local/bin/mechos-network network-wireless "System;Settings;"
desktop mechos-browser.desktop "MechBrowser" /usr/local/bin/mechos-browser web-browser "Network;WebBrowser;"
desktop mechos-gpu.desktop "MechOS GPU Compatibility" /usr/local/bin/mechos-gpu video-display "System;Settings;"
desktop mechos-inputs.desktop "MechOS USB4 / HOTAS / Controller Setup" /usr/local/bin/mechos-inputs input-gaming "Game;Settings;"
desktop mechos-power.desktop "MechOS Game Power Profiles" /usr/local/bin/mechos-power battery "Game;Settings;"
desktop mechos-crashes.desktop "MechOS Game Crash Protection" /usr/local/bin/mechos-crashes dialog-warning "Game;System;"
desktop mechos-bridge.desktop "MechOS Companion & Bridge" /usr/local/bin/mechos-bridge-settings network-server "System;Settings;"
desktop mechos-creator-031.desktop "MechOS Creator Store" /usr/local/bin/mechos-creator applications-development "Development;"
desktop mechos-compat.desktop "MechOS Game Compatibility" /usr/local/bin/mechos-compat applications-games "Game;"

# Prefer new 0.3.1 Network Setup from MechScope while retaining systemsettings fallback.
RUNTIME="$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"
python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
text=p.read_text(encoding='utf-8')
old='"network": lambda: self._launch_first((("systemsettings", ["kcm_networkmanagement"]), ("systemsettings", []))),'
new='"network": lambda: self._launch_first((("/usr/local/bin/mechos-network", []), ("systemsettings", ["kcm_networkmanagement"]), ("systemsettings", []))),'
if old in text:
    text=text.replace(old,new,1)
elif '/usr/local/bin/mechos-network' not in text:
    raise SystemExit('could not patch MechScope Network action')
p.write_text(text,encoding='utf-8')
PY

# Static source checks before creating the update.
python3 -m py_compile   "$STAGE/usr/local/libexec/mechos-031-control-suite"   "$STAGE/usr/local/libexec/mechos-bridge-v031"   "$STAGE/usr/local/bin/mechos-game-run"   "$RUNTIME"
bash -n "$STAGE/usr/local/libexec/mechos-0.3.1-phase1-apply"
for f in "$STAGE"/usr/local/bin/mechos-{downloads,network,browser,gpu,inputs,compat,creator,power,crashes,bridge-settings}; do
  bash -n "$f"
done

grep -Fq 'MECHOS_031_CONTROL_SUITE_V1' "$STAGE/usr/local/libexec/mechos-031-control-suite"
grep -Fq 'MECHOS_BRIDGE_V031' "$STAGE/usr/local/libexec/mechos-bridge-v031"
grep -Fq 'MECHOS_GAME_RUN_V031' "$STAGE/usr/local/bin/mechos-game-run"
grep -Fq '/usr/local/bin/mechos-network' "$RUNTIME"

# Proven cumulative update/runtime components must remain present.
for required in   "$STAGE/usr/local/bin/mechos-update-helper"   "$STAGE/usr/local/bin/mechos-update-center"   "$STAGE/usr/local/bin/mechscope"   "$STAGE/usr/local/bin/mechos-unified-store"   "$STAGE/usr/local/libexec/mechos-update-transaction-v25"   "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"; do
  [ -e "$required" ] || { echo "Cumulative component missing: $required" >&2; exit 1; }
done

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
  'version':'0.3.1',
  'release_name':'MechOS v0.3.1',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative MechOS 0.3.1 roadmap release built on Hotfix 35. Adds the official wallpaper collection, MechOS Downloads hub, dedicated Network Setup, MechBrowser launcher, GPU compatibility diagnostics, per-game power/crash wrapper, Companion Bridge service/settings, Creator Store catalog, Windows-game compatibility profiles including S.T.A.L.K.E.R. G.A.M.M.A. and Star Citizen as Needs Setup/Testing, plus USB4/HOTAS/controller diagnostics. Hardware- and game-specific compatibility remains conservatively labeled until real-device validation. Update Center retains SHA-256 verification and transactional rollback; signed-manifest publication remains a release certification gate.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.1-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'MechOS 0.3.1 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
