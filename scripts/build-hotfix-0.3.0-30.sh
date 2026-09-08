#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX30_HARDWARE_PYTHON_CRASH_LOOP_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.30-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H29="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.29-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H29" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-29.sh"
[ -s "$H29" ] || { echo 'Hotfix 29 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H29" -C "$STAGE"

mkdir -p "$STAGE/usr/local/bin" "$STAGE/usr/local/libexec" "$STAGE/usr/lib/systemd/system" "$STAGE/etc/systemd/system/multi-user.target.wants"
install -m0755 "$ROOT/scripts/mechscope-session-v20.sh" "$STAGE/usr/local/bin/mechscope-session"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-30-apply.sh" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-30-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-30.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 30 hardware MechScope Python/crash-loop recovery
After=local-fs.target mechos-hotfix-0.3.0-29.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-30-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-30-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-30.service "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-30.service"

SESSION="$STAGE/usr/local/bin/mechscope-session"
bash -n "$SESSION" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-30-apply"
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V21' "$SESSION"
grep -Fq 'MECHSCOPE_COMMAND=(/usr/bin/python3 "$target")' "$SESSION"
if grep -Fq 'MECHOS_MECHSCOPE_SESSION_V22_SINGLE_OWNER' "$SESSION"; then
  grep -Fq '/usr/bin/gamescope "$@" -- /usr/bin/flock -n "$LOCK_FILE" "${MECHSCOPE_COMMAND[@]}"' "$SESSION"
else
  grep -Fq '/usr/bin/gamescope "$@" -- "${MECHSCOPE_COMMAND[@]}"' "$SESSION"
fi
grep -Fq 'crashes >= 3' "$SESSION"
grep -Fq 'MECHOS_HOTFIX30_HARDWARE_PYTHON_CRASH_LOOP_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-30-apply"

for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-29-apply" \
  "$STAGE/usr/local/libexec/mechos-mechscope-runtime-v23" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/oobe_shell.py" \
  "$STAGE/usr/local/bin/mechos-update-helper"; do
  [ -e "$required" ] || { echo "Cumulative component missing: $required" >&2; exit 1; }
done

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
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.30',
  'release_name':'MechOS v0.3.0 Hotfix 30',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative hardware MechScope Python-target and crash-loop recovery update. Physical-hardware Gaming Mode now resolves the persistent MechScope runtime or legacy mechscope.real target before launch, detects raw Python source, validates it, and invokes it through /usr/bin/python3 instead of executing Python as shell code. Gamescope and Plasma fallback both use the resolved command. Repeated MechScope crashes are capped at three attempts, then MechOS records the failure and safely switches the active session to Desktop Mode instead of flashing/restarting forever. Includes all Hotfix 29 Creator icon, VMware supervision, OOBE and updater repairs.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.30-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 30 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
