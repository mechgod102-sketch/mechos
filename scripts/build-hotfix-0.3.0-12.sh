#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.12-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$(dirname "$BUNDLE")"

install -m 0755 "$ROOT/scripts/mechos-vm-mode-runtime-hotfix5.sh" "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
install -m 0755 "$ROOT/scripts/mechos-mode-launch-hotfix10.sh" "$STAGE/usr/local/bin/mechos-mode-launch"
install -m 0755 "$ROOT/scripts/mechos-hotfix-0.3.0-12-apply.sh" "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-12-apply"

cat > "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-12.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 12 MechScope permission repair
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-12-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-12-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-12.service "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-12.service"

for f in \
  "$STAGE/usr/local/bin/mechos-vm-mode-runtime" \
  "$STAGE/usr/local/bin/mechos-mode-launch" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-12-apply"; do
  bash -n "$f"
done

grep -Fq 'MECHOS_VM_MECHSCOPE_NO_PYCACHE_HEALTHCHECK_V4' "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
grep -Fq 'MECHOS_HOTFIX12_NO_PYCACHE_HEALTHCHECK_V1' "$STAGE/usr/local/bin/mechos-mode-launch"
! grep -Fq 'python3 -m py_compile "$target"' "$STAGE/usr/local/bin/mechos-vm-mode-runtime"
! grep -Fq 'python3 -m py_compile "$target"' "$STAGE/usr/local/bin/mechos-mode-launch"

rm -f "$BUNDLE" "$SUM"
tar --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" > "$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime, json, sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.12',
  'release_name':'MechOS v0.3.0 Hotfix 12',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'MechScope permission hotfix. Fixes the Oracle VirtualBox runtime rc=1 failure caused by the launcher health check attempting to write Python bytecode into root-owned /usr/local/bin/__pycache__. Runtime validation now compiles MechScope source entirely in memory with no filesystem writes, while retaining Hotfix 11 Qt backend fallbacks and VM diagnostics.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.12-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'Hotfix 12 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
