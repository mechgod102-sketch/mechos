#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX23_ACCOUNT_REPAIR_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.23-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
H22="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.22.6-update.tar.zst"
mkdir -p "$(dirname "$BUNDLE")"

# Hotfix 23 is cumulative from 22.6. If the binary base is not present in a
# fresh checkout, reconstruct it through the existing source-owned builder.
[ -s "$H22" ] || bash "$ROOT/scripts/build-hotfix-0.3.0-22.sh"
[ -s "$H22" ] || { echo 'Hotfix 22.6 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$H22" -C "$STAGE"

mkdir -p \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants"

# Keep the canonical Update Center backend that knows how to route an
# incomplete-OOBE session through mechos-firstboot-update-apply.
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py" \
  "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
install -m0755 "$ROOT/scripts/mechos-update-center-reference-v8.py" \
  "$STAGE/usr/local/libexec/mechos-update-center-v8-rescue.py"

install -m0755 "$ROOT/scripts/mechos-firstboot-update-apply-v23.sh" \
  "$STAGE/usr/local/libexec/mechos-firstboot-update-apply"
install -m0755 "$ROOT/scripts/mechos-hotfix-0.3.0-23-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-23-apply"

cat >"$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-23.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 23 post-install account repair
After=local-fs.target mechos-hotfix-0.3.0-22.service
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-23-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-23-apply

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/mechos-hotfix-0.3.0-23.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-23.service"

bash -n "$STAGE/usr/local/libexec/mechos-firstboot-update-apply"
bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-23-apply"
python3 -m py_compile \
  "$STAGE/usr/local/libexec/mechos-update-center-v8.py" \
  "$STAGE/usr/local/libexec/mechos-update-center-v8-rescue.py"

grep -Fq 'FIRSTBOOT_APPLY = "/usr/local/libexec/mechos-firstboot-update-apply"' \
  "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
grep -Fq 'user == "mechos-setup"' "$STAGE/usr/local/libexec/mechos-update-center-v8.py"
grep -Fq 'MECHOS_FIRSTBOOT_UPDATE_APPLY_V23' "$STAGE/usr/local/libexec/mechos-firstboot-update-apply"
grep -Fq 'PKEXEC_UID' "$STAGE/usr/local/libexec/mechos-firstboot-update-apply"
grep -Fq 'exec "$HELPER" apply' "$STAGE/usr/local/libexec/mechos-firstboot-update-apply"
grep -Fq 'MECHOS_HOTFIX23_POSTINSTALL_ACCOUNT_REPAIR_V1' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-23-apply"
grep -Fq 'showFullScreen()' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-23-apply"
grep -Fq 'mechos-oobe-finish-reboot' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-23-apply"
grep -Fq '99-mechos-final-user.conf' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-23-apply"
grep -Fq 'userdel -r "$SETUP_USER"' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-23-apply"
grep -Fq 'Relogin=false' "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-23-apply"
grep -Fq 'ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-23-applied' \
  "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-23.service"

# Cumulative safety: Hotfix 23 must retain the proven updater transaction core
# and the 22.6 runtime payload, not replace it with an account-only delta.
for required in \
  "$STAGE/usr/local/bin/mechos-update-helper" \
  "$STAGE/usr/local/bin/mechos-update-center" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v13" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-22-apply"; do
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
  'version':'0.3.0-hotfix.23',
  'release_name':'MechOS v0.3.0 Hotfix 23',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Cumulative post-install account-creation recovery update. Repairs systems that can reach the temporary mechos-setup session but do not complete the permanent-user handoff. The OOBE is forced fullscreen, the temporary account remains non-admin, completion creates or renames the permanent user and sets its password/admin groups, SDDM is cleared of stale mechos-setup autologin fragments, reboot is scheduled by the privileged OOBE helper, and the temporary setup account is removed before the final sign-in. Update Center also retains the restricted firstboot apply bridge so incomplete-OOBE systems can install manifest-pinned MechOS updates without giving mechos-setup general administrator access. Includes the complete Hotfix 22.6 cumulative runtime and transactional updater protections.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.23-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
printf 'Hotfix 23 cumulative bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
