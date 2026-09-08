#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX27_OOBE_UI_NAMEERROR_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.27-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H26="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.26-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

[ -s "$H26" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-26.sh"
[ -s "$H26" ] || { echo 'Hotfix 26 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H26" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

# Ship the source-owned UI directly so already-installed HF26 systems receive
# the same corrected shell future ISO builds will use.
install -m0644 "$ROOT/src/mechos_ui/oobe_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/oobe_shell.py"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-27-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-27-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-27.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 27 OOBE UI NameError repair
After=local-fs.target mechos-hotfix-0.3.0-26.service
Requires=mechos-hotfix-0.3.0-26.service
Before=mechos-oobe-rearm-v25.service sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-27-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-27-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-27.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-27.service"

bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-27-apply"
python3 -m py_compile "$STAGE/usr/local/share/mechos/ui/oobe_shell.py"
python3 - "$STAGE/usr/local/share/mechos/ui/oobe_shell.py" <<'PY'
import ast, pathlib, sys
p=pathlib.Path(sys.argv[1]); tree=ast.parse(p.read_text(encoding='utf-8'))
build=None
for node in tree.body:
    if isinstance(node,ast.ClassDef) and node.name=='OOBEShell':
        build=next((n for n in node.body if isinstance(n,ast.FunctionDef) and n.name=='build'),None)
        break
assert build is not None
bad={n.id for n in ast.walk(build) if isinstance(n,ast.Name) and isinstance(n.ctx,ast.Load) and n.id in {'zones','locales','keymaps'}}
assert not bad, bad
PY

grep -Fq 'self.zone.addItems(self.zones)' "$STAGE/usr/local/share/mechos/ui/oobe_shell.py"
grep -Fq 'self.locale.addItems(self.locales)' "$STAGE/usr/local/share/mechos/ui/oobe_shell.py"
grep -Fq 'for label,code in self.keymaps:' "$STAGE/usr/local/share/mechos/ui/oobe_shell.py"

for required in \
  "$STAGE/usr/local/bin/mechos-oobe-start" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-26-apply" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-25-apply" \
  "$STAGE/usr/local/libexec/mechos-oobe-rearm-v25" \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14"; do
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
  'version':'0.3.0-hotfix.27',
  'release_name':'MechOS v0.3.0 Hotfix 27',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative First System Setup UI crash repair. Fixes the OOBE shell NameError that prevented the account-creation window from rendering after Hotfix 26. OOBEShell.build now reads timezone, locale, and keyboard data from self.zones, self.locales, and self.keymaps instead of undefined local names. Adds a static regression check for the same class of error and ships the corrected source-owned OOBE shell directly to installed systems. Includes all Hotfix 26 graphical launcher recovery and Hotfix 25 update/account recovery fixes.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.27-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 27 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
