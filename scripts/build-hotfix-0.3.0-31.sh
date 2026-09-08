#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX31_PUBLIC_MECHSCOPE_PYTHON_WRAPPER_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.31-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H30="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.30-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H30" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-30.sh"
[ -s "$H30" ] || { echo 'Hotfix 30 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H30" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

install -m0755 "$ROOT/scripts/mechos-mechscope-safe-launch-v31.sh" \
  "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31"
install -m0755 "$ROOT/scripts/mechos-session-autostart-v31.sh" \
  "$STAGE/usr/local/libexec/mechos-session-autostart-v31"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-31-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-31-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-31.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 31 public MechScope Python-wrapper recovery
After=local-fs.target mechos-hotfix-0.3.0-30.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-31-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-31-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-31.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-31.service"

bash -n \
  "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31" \
  "$STAGE/usr/local/libexec/mechos-session-autostart-v31" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-31-apply"
grep -Fq 'MECHOS_MECHSCOPE_SAFE_LAUNCH_V31' "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31"
grep -Fq '/usr/bin/python3 "$target" "$@"' "$STAGE/usr/local/libexec/mechos-mechscope-safe-launch-v31"
grep -Fq 'MECHOS_SESSION_AUTOSTART_V31' "$STAGE/usr/local/libexec/mechos-session-autostart-v31"
grep -Fq 'MECHOS_HOTFIX31_PUBLIC_MECHSCOPE_PYTHON_WRAPPER_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-31-apply"

for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-30-apply" \
  "$STAGE/usr/local/bin/mechscope-session" \
  "$STAGE/usr/local/libexec/mechos-mechscope-runtime-v23" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/oobe_shell.py" \
  "$STAGE/usr/local/bin/mechos-update-helper"; do
  [ -e "$required" ] || { echo "Cumulative component missing: $required" >&2; exit 1; }
done

grep -Fq 'MECHOS_MECHSCOPE_SESSION_V21' "$STAGE/usr/local/bin/mechscope-session"

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
  'version':'0.3.0-hotfix.31',
  'release_name':'MechOS v0.3.0 Hotfix 31',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative public MechScope Python-wrapper recovery. Fixes physical-hardware systems where the first-run tutorial Bash wrapper still executed /usr/local/bin/mechscope.real directly even though that preserved target is Python source. A single interpreter-aware safe launcher now validates raw Python and invokes it through /usr/bin/python3. Hotfix 31 patches the installed tutorial wrapper in place without removing tutorial/OOBE behavior and replaces the legacy KDE autostart fallback so it cannot bypass the safe launch path. Future ISO tutorial postinstall integration also installs the same safe launcher. Includes all Hotfix 30 hardware session, crash-loop, Creator icon, VMware, OOBE and updater repairs.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.31-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 31 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
