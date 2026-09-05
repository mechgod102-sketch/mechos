#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.3-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$(dirname "$BUNDLE")"

install -m 0755 "$ROOT/scripts/mechos-hotfix-0.3.0-3-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-3-apply"

# Carry the canonical OOBE UI and privileged apply/cleanup helpers so Hotfix 3
# can repair machines where the first-run runtime was incomplete in the ISO.
python3 - "$ROOT/scripts/mechos-oobe-integration.sh" "$STAGE" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text(encoding='utf-8')
stage=Path(sys.argv[2])

def grab(start, end, out):
    i=src.find(start)
    if i < 0: raise SystemExit(f'missing OOBE source marker: {start}')
    i += len(start)
    j=src.find(end,i)
    if j < 0: raise SystemExit(f'missing OOBE end marker for {out}')
    p=stage/out
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(src[i:j].lstrip('\n'),encoding='utf-8')
    p.chmod(0o755)

grab("cat > \"$bin/mechos-oobe\" <<'PYEOF'", "\nPYEOF", Path('usr/local/bin/mechos-oobe'))
grab("cat > \"$libexec/mechos-oobe-apply\" <<'PYEOF'", "\nPYEOF", Path('usr/local/libexec/mechos-oobe-apply'))
grab("cat > \"$libexec/mechos-oobe-cleanup\" <<'EOF'", "\nEOF", Path('usr/local/libexec/mechos-oobe-cleanup'))
PY

cat > "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-3.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 3 firstboot and splash repairs
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-3-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-3-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-3.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-3.service"

bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-3-apply"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$STAGE/usr/local/bin/mechos-oobe"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$STAGE/usr/local/libexec/mechos-oobe-apply"
bash -n "$STAGE/usr/local/libexec/mechos-oobe-cleanup"

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
  'version':'0.3.0-hotfix.3',
  'release_name':'MechOS v0.3.0 Hotfix 3',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Repairs post-install account creation on affected VM and hardware installs by restoring the temporary first-run login, adding both KDE/XDG and systemd-user OOBE launch paths, and keeping that setup account non-admin. Also disables the stock KDE/Plasma session splash so the MechOS Plymouth splash remains the visible boot branding.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.3-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'Hotfix 3 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
