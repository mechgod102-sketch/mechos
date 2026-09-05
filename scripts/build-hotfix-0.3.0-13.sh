#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.13-update.tar.zst"
SUM="$BUNDLE.sha256"; MANIFEST="$ROOT/updates/stable.json"
mkdir -p "$STAGE/usr/local/bin" "$STAGE/usr/local/libexec" "$STAGE/usr/local/share/mechos/ui" "$STAGE/usr/lib/systemd/system" "$STAGE/etc/systemd/system/multi-user.target.wants" "$(dirname "$BUNDLE")"

# Update Center and Performance Center are replaced immediately when the bundle
# is installed, so both can be reopened without waiting for a reboot.
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py" "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
cat >"$STAGE/usr/local/bin/mechos-update-center" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/update-center-v13-launch.log"
mkdir -p "$(dirname "$LOG")"
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@" >>"$LOG" 2>&1
EOF
chmod 0755 "$STAGE/usr/local/bin/mechos-update-center"
install -m0755 "$ROOT/scripts/mechos-performance-center-v13.py" "$STAGE/usr/local/bin/mechos-performance-center"
for f in fixed_canvas.py update_shell.py performance_shell.py; do install -m0644 "$ROOT/src/mechos_ui/$f" "$STAGE/usr/local/share/mechos/ui/$f"; done

# Future-update protection and installed MechScope repair are activated by the
# one-shot service on the user's next MANUAL restart. Nothing in this bundle
# reboots, logs out, or powers off the machine.
install -m0755 "$ROOT/scripts/mechos-update-transaction-v13.sh" "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
install -m0755 "$ROOT/scripts/mechos-update-helper-v13-patch.py" "$STAGE/usr/local/libexec/mechos-update-helper-v13-patch"
install -m0755 "$ROOT/scripts/mechos-hotfix13-mechscope-patch.py" "$STAGE/usr/local/libexec/mechos-hotfix13-mechscope-patch"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-13-apply.sh" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-13-apply"
cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-13.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 13 stability policy
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-13-applied
[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-13-apply
[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-13.service "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-13.service"

bash -n "$STAGE/usr/local/bin/mechos-update-center"
bash -n "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-13-apply"
python3 -m py_compile "$STAGE/usr/local/libexec/mechos-update-center-v8.py" "$STAGE/usr/local/bin/mechos-performance-center" "$STAGE/usr/local/libexec/mechos-update-helper-v13-patch" "$STAGE/usr/local/libexec/mechos-hotfix13-mechscope-patch"
! grep -R -Fq 'systemctl reboot' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-13-apply" "$STAGE/usr/local/libexec/mechos-update-transaction-v13"
! grep -R -Fq 'shutdown -r' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-13-apply" "$STAGE/usr/local/libexec/mechos-update-transaction-v13"

rm -f "$BUNDLE" "$SUM"
tar --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE"|awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"
python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
 'schema':1,'channel':'stable','version':'0.3.0-hotfix.13','release_name':'MechOS v0.3.0 Hotfix 13',
 'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
 'notes':'Stability and system-surface hotfix. Restores the Update Center to the proven key/value backend so stale or malformed JSON cannot disable updates; replaces the no-op Performance/Optimization Center with the canonical responsive UI and logged launch actions; makes MechScope reassert true frameless fullscreen with screen-height scaling; launches Unified Store as its own fullscreen process with diagnostics; and installs a transactional future-update engine that validates staged files, backs up overwritten files, applies the updater last, self-tests critical surfaces, and rolls back on failure. Updates never reboot, log out, or power off automatically. A manual restart is requested only to activate the installed MechScope and future-update policy service.',
 'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.13-update.tar.zst',
 'bundle_sha256':sha,'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 13 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
