#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX29_MECHSCOPE_LIFETIME_CREATOR_ICONS_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.29-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H28="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.28-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H28" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-28.sh"
[ -s "$H28" ] || { echo 'Hotfix 28 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H28" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/share/wayland-sessions" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

# Preserve the proven HF28 VM launcher as the v5 core and put the new sustained
# health wrapper at the public runtime path.
install -m0755 "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh" \
  "$STAGE/usr/local/libexec/mechos-vm-mode-runtime-v5"
install -m0755 "$ROOT/scripts/mechos-vm-mode-runtime-hotfix6.sh" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
install -m0755 "$ROOT/scripts/mechos-vm-mechscope-watchdog-v29.sh" \
  "$STAGE/usr/local/libexec/mechos-vm-mechscope-watchdog-v29"

# Hardware Gaming Mode gets a supervised Gamescope session with a Plasma
# recovery path instead of considering a clean early child exit successful.
install -m0755 "$ROOT/scripts/mechscope-session-v20.sh" \
  "$STAGE/usr/local/bin/mechscope-session"

# Persistent MechScope owns QApplication lifetime on both VM and hardware.
install -m0755 "$ROOT/scripts/mechos-mechscope-runtime-v23.py" \
  "$STAGE/usr/local/libexec/mechos-mechscope-runtime-v23"

# Make Creator icon behavior Update-Center-owned rather than ISO-build-only,
# then re-apply the existing real application icon resolver at boot.
install -m0644 "$ROOT/src/mechos_ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"
install -m0644 "$ROOT/src/mechos_ui/creator_real_icons_v22.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_real_icons_v22.py"
install -m0755 "$ROOT/scripts/mechos-creator-real-icons-owner-v22-patch.py" \
  "$STAGE/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch"

install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-29-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-29-apply"

cat >"$STAGE/usr/share/wayland-sessions/mechscope.desktop" <<'EOF'
[Desktop Entry]
Name=MechScope
Comment=MechOS Gamescope + Steam Gaming Mode
Exec=/usr/local/bin/mechscope-session
TryExec=/usr/local/bin/mechscope-session
Type=Application
DesktopNames=MechScope
EOF
chmod 0644 "$STAGE/usr/share/wayland-sessions/mechscope.desktop"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-29.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 29 MechScope lifetime and Creator icon recovery
After=local-fs.target mechos-hotfix-0.3.0-28.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-29-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-29-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-29.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-29.service"

bash -n \
  "$STAGE/usr/local/bin/mechscope-session" \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime" \
  "$STAGE/usr/local/libexec/mechos-vm-mode-runtime-v5" \
  "$STAGE/usr/local/libexec/mechos-vm-mechscope-watchdog-v29" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-29-apply"
python3 -m py_compile \
  "$STAGE/usr/local/libexec/mechos-mechscope-runtime-v23" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_real_icons_v22.py" \
  "$STAGE/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch"

grep -Fq 'MECHOS_MECHSCOPE_SESSION_V20' "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'MECHOS_SESSION_SUPERVISED=1' "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'return 90' "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'MECHOS_VM_MECHSCOPE_SUSTAINED_HEALTH_V6' "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
grep -Fq 'MECHOS_VM_MECHSCOPE_PERSISTENT_RUNTIME_V5' "$STAGE/usr/local/libexec/mechos-vm-mode-runtime-v5"
grep -Fq 'MECHOS_VM_MECHSCOPE_WATCHDOG_V29' "$STAGE/usr/local/libexec/mechos-vm-mechscope-watchdog-v29"
grep -Fq 'MECHOS_MECHSCOPE_LIFETIME_V29' "$STAGE/usr/local/libexec/mechos-mechscope-runtime-v23"
grep -Fq 'app.setQuitOnLastWindowClosed(False)' "$STAGE/usr/local/libexec/mechos-mechscope-runtime-v23"
grep -Fq 'MECHOS_CREATOR_BUTTON_ICONS_V1' "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"
grep -Fq 'MECHOS_CREATOR_REAL_ICONS_V22' "$STAGE/usr/local/share/mechos/ui/creator_real_icons_v22.py"
grep -Fq 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' "$STAGE/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch"
grep -Fq 'MECHOS_HOTFIX29_MECHSCOPE_LIFETIME_CREATOR_ICONS_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-29-apply"
grep -Fq 'Exec=/usr/local/bin/mechscope-session' "$STAGE/usr/share/wayland-sessions/mechscope.desktop"

# Hotfix 29 must remain cumulative with the account/update repairs and HF28 VM
# recovery path rather than replacing them with a narrow delta.
for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-28-apply" \
  "$STAGE/usr/local/share/mechos/ui/oobe_shell.py" \
  "$STAGE/usr/local/bin/mechos-oobe-start" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14"; do
  [ -e "$required" ] || { echo "Cumulative component missing: $required" >&2; exit 1; }
done

# Sensitive SDDM files are repaired by the root apply helper. They are not
# shipped directly because the Update Center bundle allowlist intentionally
# excludes /etc/sddm.conf.d and /etc/polkit-1.
if find "$STAGE" -path '*/etc/sddm.conf.d/*' -o -path '*/etc/polkit-1/*' | grep -q .; then
  echo 'Hotfix 29 bundle contains a forbidden sensitive runtime path' >&2
  exit 1
fi

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
  'version':'0.3.0-hotfix.29',
  'release_name':'MechOS v0.3.0 Hotfix 29',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative MechScope lifetime and Creator icon recovery update. Creator Mode now receives source-owned responsive button icons through Update Center and re-applies the real installed application icon resolver to upgraded Creator owners. VMware Gaming Mode extends the prior short startup probe to sustained health verification and runs a mode-aware recovery watchdog. Physical hardware Gaming Mode no longer treats an early Gamescope/MechScope rc=0 exit as a successful session while Gaming Mode remains selected; it retries Gamescope and falls back to a supervised Plasma-hosted MechScope loop. The persistent Qt runtime also prevents last-window-close from silently ending supervised Gaming Mode on both VM and hardware. Includes all Hotfix 28 cumulative repairs.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.29-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 29 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
