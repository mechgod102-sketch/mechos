#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.16-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H15="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.15-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

# Build and unpack Hotfix 15 first so Hotfix 16 is cumulative. A Hotfix 14
# machine can therefore jump directly to 16 without losing the Creator/Store
# fixes that 16 embeds as pages.
bash "$ROOT/scripts/build-hotfix-0.3.0-15.sh"
[ -s "$H15" ] || { echo 'Hotfix 15 cumulative base bundle missing' >&2; exit 1; }
tar --zstd -xpf "$H15" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

install -m0755 "$ROOT/scripts/mechos-hotfix16-single-shell-patch.py" \
  "$STAGE/usr/local/libexec/mechos-hotfix16-single-shell-patch"
install -m0755 "$ROOT/scripts/mechos-shell-route-v16.sh" \
  "$STAGE/usr/local/bin/mechos-shell-route"
install -m0755 "$ROOT/scripts/mechos-mode-launch-v16.sh" \
  "$STAGE/usr/local/bin/mechos-mode-launch"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-16-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-16-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-16.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 16 single-window shell
After=local-fs.target mechos-hotfix-0.3.0-15.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-16-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-16-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-16.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-16.service"

bash -n "$STAGE/usr/local/bin/mechos-shell-route"
bash -n "$STAGE/usr/local/bin/mechos-mode-launch"
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-16-apply"
python3 -m py_compile "$STAGE/usr/local/libexec/mechos-hotfix16-single-shell-patch"
grep -Fq 'MECHOS_HOTFIX16_SINGLE_SHELL_PATCH' "$STAGE/usr/local/libexec/mechos-hotfix16-single-shell-patch"
grep -Fq 'MECHOS_SHELL_ROUTE_V16' "$STAGE/usr/local/bin/mechos-shell-route"
grep -Fq 'MECHOS_MODE_LAUNCH_V16' "$STAGE/usr/local/bin/mechos-mode-launch"
grep -Fq 'After=local-fs.target mechos-hotfix-0.3.0-15.service' "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-16.service"

# Cumulative-base assertions: Hotfix 15 components must still be present.
for required in \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-15-apply" \
  "$STAGE/usr/local/libexec/mechos-hotfix15-game-browser-patch" \
  "$STAGE/usr/local/libexec/mechos-game-catalog-v15" \
  "$STAGE/usr/local/libexec/mechos-provider-bootstrap-v15" \
  "$STAGE/usr/local/libexec/mechos-mode-launch-base-v15"; do
  [ -e "$required" ] || { echo "Cumulative Hotfix 15 component missing: $required" >&2; exit 1; }
done

rm -f "$BUNDLE" "$SUM"
tar --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime, json, sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.16',
  'release_name':'MechOS v0.3.0 Hotfix 16',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Single-window shell hotfix. MechScope becomes the persistent MechOS shell and internal sections switch inside one QStackedWidget instead of launching separate top-level windows. Gaming, Unified Store, Creator Mode, Performance Center, Update Center and Recovery Center share one navigation bar and back stack. Creator/Gaming mode requests are routed to the running shell. Steam, Heroic, games, Blender, Unity and other true external applications still launch externally. Hotfix 16 is cumulative and includes the Hotfix 15 Creator/Unified Store repairs.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.16-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 16 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
