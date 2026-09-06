#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.18-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H17="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.17-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

bash "$ROOT/scripts/build-hotfix-0.3.0-17.sh"
[ -s "$H17" ] || { echo 'Hotfix 17 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H17" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

# Hotfix 18 replaces the public helper. The transaction contract therefore
# requires the complete public updater trio in the same bundle. Re-add the
# canonical Hotfix 14 Update Center and reboot surfaces explicitly instead of
# assuming they are present in the Hotfix 15-17 cumulative payloads.
install -m0755 "$ROOT/scripts/mechos-reboot-v14.sh" \
  "$STAGE/usr/local/bin/mechos-reboot"
install -m0755 "$ROOT/scripts/mechos-reboot-v14.sh" \
  "$STAGE/usr/local/libexec/mechos-reboot-v14"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py" \
  "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py" \
  "$STAGE/usr/local/libexec/mechos-update-center-v8-rescue.py"
install -m0644 "$ROOT/src/mechos_ui/update_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/update_shell.py"
install -m0644 "$ROOT/src/mechos_ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"
cat >"$STAGE/usr/local/libexec/mechos-update-center-launcher-v14" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/update-center-v14-launch.log"
mkdir -p "$(dirname "$LOG")"
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@" >>"$LOG" 2>&1
EOF
chmod 0755 "$STAGE/usr/local/libexec/mechos-update-center-launcher-v14"
install -m0755 "$STAGE/usr/local/libexec/mechos-update-center-launcher-v14" \
  "$STAGE/usr/local/bin/mechos-update-center"

# Keep the proven v14 helper implementation as the core and place the Hotfix 18
# health/partial-success wrapper at the public helper and protected rescue path.
install -m0755 "$ROOT/scripts/mechos-update-helper-v14.sh" \
  "$STAGE/usr/local/libexec/mechos-update-helper-core-v18"
install -m0755 "$ROOT/scripts/mechos-pacman-health-v18.sh" \
  "$STAGE/usr/local/libexec/mechos-pacman-health-v18"
install -m0755 "$ROOT/scripts/mechos-update-helper-v18.sh" \
  "$STAGE/usr/local/bin/mechos-update-helper"
install -m0755 "$ROOT/scripts/mechos-update-helper-v18.sh" \
  "$STAGE/usr/local/libexec/mechos-update-helper-v14"
install -m0755 "$ROOT/scripts/mechos-update-helper-v18.sh" \
  "$STAGE/usr/local/libexec/mechos-update-helper-v18"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-18-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-18-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-18.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 18 package update reliability repair
After=local-fs.target mechos-hotfix-0.3.0-17.service
Requires=mechos-hotfix-0.3.0-17.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-18-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-18-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-18.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-18.service"

for f in \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechos-reboot" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/libexec/mechos-update-helper-core-v18" \
  "$STAGE/usr/local/libexec/mechos-pacman-health-v18" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-18-apply"; do
  bash -n "$f"
done
python3 -m py_compile \
  "$STAGE/usr/local/libexec/mechos-update-center-v8.py" \
  "$STAGE/usr/local/share/mechos/ui/update_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"

grep -Fq 'MECHOS_UPDATE_HELPER_V18' "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'MECHOS_UPDATE_HELPER_V14' "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'MECHOS_REBOOT_V14' "$STAGE/usr/local/bin/mechos-reboot"
grep -Fq 'MECHOS_UPDATE_CENTER_REFERENCE_V8' "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
grep -Fq 'MECHOS_PACMAN_HEALTH_V18' "$STAGE/usr/local/libexec/mechos-pacman-health-v18"
grep -Fq 'PACKAGE_UPDATE_FAILED=1' "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'transaction committed for ' "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'After=local-fs.target mechos-hotfix-0.3.0-17.service' "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-18.service"

for required in \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/bin/mechos-reboot" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-17-apply" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-16-apply" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-15-apply"; do
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
  'version':'0.3.0-hotfix.18',
  'release_name':'MechOS v0.3.0 Hotfix 18',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Package update reliability hotfix. Repairs pacman download-directory ownership/permissions and clears stale pacman download sandboxes before package refreshes. A successfully committed MechOS OS update is now preserved even if a later Arch or Flatpak package refresh needs to be retried, preventing the Update Center from treating a staged OS release as a total install failure. Hotfix 18 is cumulative and retains Hotfix 15 Creator/Unified Store, Hotfix 16 single-window shell and Hotfix 17 rsync-free updater repairs.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.18-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 18 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
