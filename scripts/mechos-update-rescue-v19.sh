#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_RESCUE_V19
# One-time bootstrap for systems whose installed transaction engine is broken.
# This deliberately bypasses the installed update helper, verifies the stable
# manifest and SHA-256, extracts the bundle, then executes the validated staged
# rsync-free transaction engine carried by the update itself.

[ "$(id -u)" -eq 0 ] || { echo 'Run this rescue with sudo.' >&2; exit 77; }
for cmd in curl python3 tar sha256sum grep mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Required command missing: $cmd" >&2; exit 41; }
done

MANIFEST_URL='https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json'
WORK="$(mktemp -d /tmp/mechos-rescue-v19.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
MANIFEST="$WORK/stable.json"
BUNDLE="$WORK/update.tar.zst"
STAGE="$WORK/stage"
mkdir -p "$STAGE"

curl -fsSL --retry 3 --connect-timeout 10 -H 'Cache-Control: no-cache' \
  "${MANIFEST_URL}?t=$(date +%s)" -o "$MANIFEST"

readarray -t VALUES < <(python3 - "$MANIFEST" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p,encoding='utf-8'))
for key in ('version','bundle_url','bundle_sha256'):
    v=d.get(key)
    if not isinstance(v,str) or not v.strip():
        raise SystemExit(f'invalid stable manifest: {key}')
sha=d['bundle_sha256'].strip().lower()
if len(sha)!=64 or any(c not in '0123456789abcdef' for c in sha):
    raise SystemExit('invalid stable manifest SHA-256')
print(d['version'].strip())
print(d['bundle_url'].strip())
print(sha)
print('1' if d.get('requires_reboot') else '0')
PY
)
LATEST="${VALUES[0]}"; URL="${VALUES[1]}"; SHA="${VALUES[2]}"; REBOOT="${VALUES[3]}"

echo "Rescuing MechOS update to $LATEST"
curl -fL --retry 3 --connect-timeout 10 -H 'Cache-Control: no-cache' "$URL" -o "$BUNDLE"
printf '%s  %s\n' "$SHA" "$BUNDLE" | sha256sum -c -

tar --warning=no-timestamp --zstd -xpf "$BUNDLE" -C "$STAGE"

TX=''
for candidate in \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
  "$STAGE/usr/local/libexec/mechos-update-transaction-v13"; do
  if [ -x "$candidate" ] && grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$candidate"; then
    TX="$candidate"
    break
  fi
done
[ -n "$TX" ] || { echo 'Stable bundle does not contain the validated rescue transaction engine.' >&2; exit 12; }

echo "Using staged rescue engine: $TX"
"$TX" "$STAGE" "$LATEST"
mkdir -p /var/lib/mechos
[ "$REBOOT" = 1 ] && touch /var/lib/mechos/reboot-required

echo "MechOS $LATEST staged successfully. Restart MechOS to activate the release."
