#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX34_MECHSCOPE_RESPONSIVE_UI_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.34-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H33="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.33-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H33" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-33.sh"
[ -s "$H33" ] || { echo 'Hotfix 33 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H33" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/share/mechos/mechscope" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

install -m0644 "$ROOT/src/mechscope/mechscope_shell.py" \
  "$STAGE/usr/local/share/mechos/mechscope/mechscope_shell.py"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-34-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-34-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-34.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 34 MechScope responsive UI cleanup
After=local-fs.target mechos-hotfix-0.3.0-33.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-34-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-34-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-34.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-34.service"

bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-34-apply"
python3 -m py_compile "$STAGE/usr/local/share/mechos/mechscope/mechscope_shell.py"
grep -Fq 'MECHOS_MECHSCOPE_RESPONSIVE_UI_V34' "$STAGE/usr/local/share/mechos/mechscope/mechscope_shell.py"
grep -Fq 'MECHOS_QUICK_ACTION_SINGLE_LINE_V34' "$STAGE/usr/local/share/mechos/mechscope/mechscope_shell.py"
grep -Fq 'MECHOS_HOTFIX34_MECHSCOPE_RESPONSIVE_UI_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-34-apply"

# Preserve the complete HF33 runtime architecture while changing only the shell.
for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-33-apply" \
  "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33" \
  "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31" \
  "$STAGE/usr/local/bin/mechscope-session" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/oobe_shell.py" \
  "$STAGE/usr/local/bin/mechos-update-helper"; do
  [ -e "$required" ] || { echo "Cumulative component missing: $required" >&2; exit 1; }
done

grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33' "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"
grep -Fq 'MECHOS_MECHSCOPE_SOURCE_RUNTIME_ROUTE_V33' "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31"
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V23_SOURCE_RUNTIME' "$STAGE/usr/local/bin/mechscope-session"

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
  'version':'0.3.0-hotfix.34',
  'release_name':'MechOS v0.3.0 Hotfix 34',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative MechScope responsive UI cleanup. Fixes dark hero/header text on the source-owned shell, long GPU names wrapping into the temperature row, clipped two-line Quick Actions and chevrons, and an oversized Recent Games empty state. Quick Actions are now single-line rows with separate right-side chevrons, long status strings elide cleanly with full tooltip text, and the layout keeps readable dimensions across 720p, 900p and 1080p. The Hotfix 33 source-owned MechScope runtime, single-owner hardware session, safe launcher and crash recovery remain unchanged. Includes all Hotfix 33 fixes.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.34-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 34 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
