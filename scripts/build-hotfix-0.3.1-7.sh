#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX_0317_CREATOR_QT_CALLBACK_GUARD_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BASE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.6-update.tar.zst"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.7-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p "$(dirname "$BUNDLE")"
[ -s "$BASE" ] || bash "$ROOT/scripts/build-hotfix-0.3.1-6.sh"
[ -s "$BASE" ] || { echo 'MechOS 0.3.1 Hotfix 6 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$BASE" -C "$STAGE"

mkdir -p   "$STAGE/usr/local/share/mechos/ui"   "$STAGE/usr/lib/systemd/user"

install -m0644 "$ROOT/src/mechos_ui/creator_shell.py"   "$STAGE/usr/local/share/mechos/ui/creator_shell.py"

cat >"$STAGE/usr/lib/systemd/user/mechos-creator-mode.service" <<'EOF'
[Unit]
Description=MechOS Creator Mode
After=graphical-session.target
PartOf=graphical-session.target
StartLimitIntervalSec=30
StartLimitBurst=2

[Service]
Type=simple
Environment=MECHOS_MODE=creator
ExecStart=/usr/local/bin/mechos-creator-mode
Restart=on-failure
RestartSec=2
TimeoutStopSec=8
KillMode=control-group

[Install]
WantedBy=default.target
EOF

python3 -m py_compile "$STAGE/usr/local/share/mechos/ui/creator_shell.py"
grep -Fq 'MECHOS_CREATOR_QT_CALLBACK_GUARD_V27'   "$STAGE/usr/local/share/mechos/ui/creator_shell.py"
grep -Fq 'self.metric_timer.timeout.connect(self._timer_refresh_metrics)'   "$STAGE/usr/local/share/mechos/ui/creator_shell.py"
grep -Fq 'self.startup_update_timer = QTimer(self)'   "$STAGE/usr/local/share/mechos/ui/creator_shell.py"
grep -Fq 'self._update_proc.errorOccurred.connect(self._safe_update_error)'   "$STAGE/usr/local/share/mechos/ui/creator_shell.py"
grep -Fq 'Restart=on-failure'   "$STAGE/usr/lib/systemd/user/mechos-creator-mode.service"

# Normal hotfixes are payload-only. Update Center and frozen restart authority
# are platform infrastructure and must never be shipped by this Creator fix.
bash "$ROOT/scripts/mechos-strip-updater-from-stage-v1.sh" "$STAGE"

DAY="$(date -u +%F)"
EPOCH="$(date -u -d "$DAY 00:00:00" +%s)"
rm -f "$BUNDLE" "$SUM"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner   --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"

bash "$ROOT/scripts/validate-payload-only-hotfix-v1.sh" "$BUNDLE"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.1-hotfix.7',
  'release_name':'MechOS v0.3.1 Hotfix 7',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Creator Mode Qt callback crash hardening. Creator background timers and update-status QProcess signals now cross an exception boundary so a failed metric/app/project/update callback is logged instead of escaping into Qt and aborting the entire Python process. The startup update check uses a parented one-shot QTimer, failed update processes are cleaned up safely, and the Creator user service gets a bounded on-failure restart for transient crashes. Payload-only release: Update Center and frozen restart infrastructure are not included.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.1-hotfix.7-update.tar.zst',
  'bundle_sha256':sha,
  'signature_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json.sig',
  'signing_key_id':'mechos-stable-2026-01',
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'MechOS 0.3.1 Hotfix 7 payload-only bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
