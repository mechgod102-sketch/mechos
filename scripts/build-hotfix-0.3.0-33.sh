#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX33_SOURCE_OWNED_MECHSCOPE_RUNTIME_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.33-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H32="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.32-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H32" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-32.sh"
[ -s "$H32" ] || { echo 'Hotfix 32 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H32" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/local/share/mechos/mechscope" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$STAGE/etc/xdg/autostart"

install -m0755 "$ROOT/scripts/mechos-mechscope-source-runtime-v33.py" \
  "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"
install -m0644 "$ROOT/src/mechscope/mechscope_shell.py" \
  "$STAGE/usr/local/share/mechos/mechscope/mechscope_shell.py"
install -m0755 "$ROOT/scripts/mechscope-session-v20.sh" \
  "$STAGE/usr/local/bin/mechscope-session"
install -m0755 "$ROOT/scripts/mechos-mechscope-safe-launch-v31.sh" \
  "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31"
install -m0755 "$ROOT/scripts/mechos-mechscope-user-cleanup-v33.sh" \
  "$STAGE/usr/local/libexec/mechos-mechscope-user-cleanup-v33"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-33-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-33-apply"

cat >"$STAGE/etc/xdg/autostart/mechos-mechscope-user-cleanup-v33.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS MechScope Legacy Launcher Cleanup
Exec=/usr/local/libexec/mechos-mechscope-user-cleanup-v33
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-33.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 33 source-owned MechScope runtime recovery
After=local-fs.target mechos-hotfix-0.3.0-32.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-33-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-33-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-33.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-33.service"

bash -n \
  "$STAGE/usr/local/bin/mechscope-session" \
  "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31" \
  "$STAGE/usr/local/libexec/mechos-mechscope-user-cleanup-v33" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-33-apply"
python3 -m py_compile \
  "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33" \
  "$STAGE/usr/local/share/mechos/mechscope/mechscope_shell.py"

grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33' "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"
grep -Fq 'class MechScopeShell' "$STAGE/usr/local/share/mechos/mechscope/mechscope_shell.py"
grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_ROUTE_V33' "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31"
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V23_SOURCE_RUNTIME' "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'MECHOS_HOTFIX33_SOURCE_OWNED_MECHSCOPE_RUNTIME_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-33-apply"
grep -Fq 'MECHOS_MECHSCOPE_USER_CLEANUP_V33' "$STAGE/usr/local/libexec/mechos-mechscope-user-cleanup-v33"

# HF33 must remain cumulative while no longer depending on the legacy generated
# MechScope owner for startup.
for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-32-apply" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/oobe_shell.py" \
  "$STAGE/usr/local/bin/mechos-update-helper"; do
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
  'version':'0.3.0-hotfix.33',
  'release_name':'MechOS v0.3.0 Hotfix 33',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative source-owned MechScope runtime recovery. Fixes physical-hardware systems where the update bundle installed the persistent runtime but could not restore its generated mechscope-owner-v23.py dependency, causing the safe launcher to fall back to legacy mechscope.real and repeatedly restart it. Hotfix 33 ships a complete source-owned PyQt MechScope runtime plus the source-owned MechScope shell, makes both the hardware session and public safe launcher prefer that runtime, refuses automatic legacy .real fallback on installed systems, cleans stale per-user MechScope autostarts/services, preserves the single-owner lock, and keeps the three-crash Desktop Mode safety fallback. Includes all Hotfix 32 fixes.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.33-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 33 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
