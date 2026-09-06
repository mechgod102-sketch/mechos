#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.19-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H18="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.18-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

# Hotfix 19 is cumulative with Hotfixes 15-18.
bash "$ROOT/scripts/build-hotfix-0.3.0-18.sh"
[ -s "$H18" ] || { echo 'Hotfix 18 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H18" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/share/wayland-sessions" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

# Reinstall the complete updater surface. Hotfix 19 must be recoverable even on
# a machine where the public helper/reboot files disappeared during a failed
# older transaction.
install -m0755 "$ROOT/scripts/mechos-reboot-v14.sh" "$STAGE/usr/local/bin/mechos-reboot"
install -m0755 "$ROOT/scripts/mechos-reboot-v14.sh" "$STAGE/usr/local/libexec/mechos-reboot-v14"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py" "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py" "$STAGE/usr/local/libexec/mechos-update-center-v8-rescue.py"
install -m0644 "$ROOT/src/mechos_ui/update_shell.py" "$STAGE/usr/local/share/mechos/ui/update_shell.py"
install -m0644 "$ROOT/src/mechos_ui/fixed_canvas.py" "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"
cat >"$STAGE/usr/local/libexec/mechos-update-center-launcher-v19" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/update-center-v19-launch.log"
mkdir -p "$(dirname "$LOG")"
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@" >>"$LOG" 2>&1
EOF
chmod 0755 "$STAGE/usr/local/libexec/mechos-update-center-launcher-v19"
install -m0755 "$STAGE/usr/local/libexec/mechos-update-center-launcher-v19" "$STAGE/usr/local/bin/mechos-update-center"

install -m0755 "$ROOT/scripts/mechos-update-helper-v14.sh" "$STAGE/usr/local/libexec/mechos-update-helper-core-v18"
install -m0755 "$ROOT/scripts/mechos-pacman-health-v18.sh" "$STAGE/usr/local/libexec/mechos-pacman-health-v18"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v14.sh" "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
install -m0755 "$ROOT/scripts/mechos-update-transaction-v14.sh" "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
install -m0755 "$ROOT/scripts/mechos-update-helper-v19.sh" "$STAGE/usr/local/bin/mechos-update-helper"
install -m0755 "$ROOT/scripts/mechos-update-helper-v19.sh" "$STAGE/usr/local/libexec/mechos-update-helper-v19"
install -m0755 "$ROOT/scripts/mechos-update-rescue-v19.sh" "$STAGE/usr/local/bin/mechos-update-rescue"

# Creator/shell routing repair.
install -m0755 "$ROOT/scripts/mechos-mode-launch-v19.sh" "$STAGE/usr/local/bin/mechos-mode-launch"
install -m0755 "$ROOT/scripts/mechos-shell-route-v19.sh" "$STAGE/usr/local/bin/mechos-shell-route"
# Preserve the complete Hotfix 15 Creator handoff under a dedicated name so
# Creator can launch directly without passing through Gaming/MechScope.
install -m0755 "$ROOT/scripts/mechos-mode-launch-v15.sh" "$STAGE/usr/local/libexec/mechos-creator-launch-v19"

# Hardware MechScope launch repair.
install -m0755 "$ROOT/scripts/mechscope-session-v19.sh" "$STAGE/usr/local/bin/mechscope-session"
cat >"$STAGE/usr/share/wayland-sessions/mechscope.desktop" <<'EOF'
[Desktop Entry]
Name=MechScope
Comment=MechOS Gaming Shell
Exec=/usr/local/bin/mechscope-session
TryExec=/usr/local/bin/mechscope-session
Type=Application
DesktopNames=MechScope
EOF
chmod 0644 "$STAGE/usr/share/wayland-sessions/mechscope.desktop"

install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-19-apply.sh" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-19-apply"
cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-19.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 19 updater, Creator and hardware MechScope repair
After=local-fs.target mechos-hotfix-0.3.0-18.service
Requires=mechos-hotfix-0.3.0-18.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-19-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-19-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-19.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-19.service"

for f in \
  "$STAGE/usr/local/bin/mechos-reboot" \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/bin/mechos-update-rescue" \
  "$STAGE/usr/local/bin/mechos-mode-launch" \
  "$STAGE/usr/local/bin/mechos-shell-route" \
  "$STAGE/usr/local/bin/mechscope-session" \
  "$STAGE/usr/local/libexec/mechos-creator-launch-v19" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-19-apply"; do
  bash -n "$f"
done
python3 -m py_compile \
  "$STAGE/usr/local/libexec/mechos-update-center-v8.py" \
  "$STAGE/usr/local/share/mechos/ui/update_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"

grep -Fq 'MECHOS_UPDATE_HELPER_V19' "$STAGE/usr/local/bin/mechos-update-helper"
grep -Fq 'MECHOS_UPDATE_RESCUE_V19' "$STAGE/usr/local/bin/mechos-update-rescue"
grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$STAGE/usr/local/libexec/mechos-update-transaction-v14"
grep -Fq 'MECHOS_MODE_LAUNCH_V19' "$STAGE/usr/local/bin/mechos-mode-launch"
grep -Fq 'MECHOS_SHELL_ROUTE_V19' "$STAGE/usr/local/bin/mechos-shell-route"
grep -Fq 'MECHOS_CREATOR_HANDOFF_V15' "$STAGE/usr/local/libexec/mechos-creator-launch-v19"
grep -Fq 'MECHOS_MECHSCOPE_SESSION_V19' "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'Exec=/usr/local/bin/mechscope-session' "$STAGE/usr/share/wayland-sessions/mechscope.desktop"

for required in \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/bin/mechos-reboot" \
  "$STAGE/usr/local/bin/mechos-update-rescue" \
  "$STAGE/usr/local/libexec/mechos-update-helper-core-v18" \
  "$STAGE/usr/local/libexec/mechos-pacman-health-v18" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v13" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-18-apply" \
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
  'version':'0.3.0-hotfix.19',
  'release_name':'MechOS v0.3.0 Hotfix 19',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Recovery and mode-launch reliability hotfix. Restores the complete Update Center helper/reboot trio and adds a standalone rescue updater for systems where those public helpers are already missing. Future updates prefer the validated rsync-free transaction engine carried by the staged bundle, allowing the updater to repair itself. Creator Mode is a first-class target: if the unified shell is absent, Creator launches directly instead of bootstrapping Gaming/MechScope. Physical-hardware MechScope now uses conservative Gamescope startup with VRR/HDR opt-in and a Plasma-hosted fallback if Gamescope cannot start. Hotfix 19 is cumulative with Hotfixes 15-18.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.19-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 19 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
