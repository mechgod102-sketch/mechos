#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.6-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$(dirname "$BUNDLE")"

install -m 0755 "$ROOT/scripts/mechos-hotfix-0.3.0-6-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-6-apply"
install -m 0755 "$ROOT/scripts/mechos-reboot-hotfix6.sh" \
  "$STAGE/usr/local/bin/mechos-reboot"
install -m 0644 "$ROOT/src/mechos_ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"

cat > "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-6.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 6 reboot and VM Creator repair
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-6-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-6-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-6.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-6.service"

bash -n "$STAGE/usr/local/bin/mechos-reboot"
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-6-apply"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"

rm -f "$BUNDLE" "$SUM"
tar --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" > "$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.6',
  'release_name':'MechOS v0.3.0 Hotfix 6',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Repairs the Update Center Restart MechOS action by replacing the invalid legacy reboot path with KDE Plasma shutdown authority, systemd-logind fallback and visible PolicyKit failure reporting. Also improves VirtualBox/VMware/QEMU Creator Mode at low resolutions by compacting short two-line controls and preventing narrow status labels from wrapping into neighboring controls.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.6-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'Hotfix 6 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
