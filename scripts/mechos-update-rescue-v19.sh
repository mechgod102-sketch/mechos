#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_RESCUE_V19
# MECHOS_UPDATE_RESCUE_V20
# One-time bootstrap for systems whose installed transaction engine is broken.
# Bypasses the installed update helper, verifies the stable manifest + SHA-256,
# extracts the bundle, then runs the validated transaction implementation carried
# by the update itself. Hotfix 20 support deliberately normalizes staging-root
# metadata before copying so a rescue can never make / non-traversable.

[ "$(id -u)" -eq 0 ] || { echo 'Run this rescue with sudo.' >&2; exit 77; }
for cmd in curl python3 tar sha256sum grep mktemp stat chmod chown; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Required command missing: $cmd" >&2; exit 41; }
done

MANIFEST_URL='https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json'
WORK="$(mktemp -d /tmp/mechos-rescue-v20.XXXXXX)"
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

# Preserve the installed root metadata before any staged transaction runs.
ROOT_MODE="$(stat -c '%a' /)"
ROOT_UID="$(stat -c '%u' /)"
ROOT_GID="$(stat -c '%g' /)"
chmod "$ROOT_MODE" "$STAGE"
chown "$ROOT_UID:$ROOT_GID" "$STAGE"

TX=''
WRAPPER="$STAGE/usr/local/libexec/mechos-update-transaction-v14"
CORE20="$STAGE/usr/local/libexec/mechos-update-transaction-core-v20"

# A Hotfix 20 wrapper normally calls its installed core by absolute path. During
# rescue that core is only present in STAGE, so invoke the staged core directly
# after normalizing STAGE to the installed root metadata.
if [ -x "$WRAPPER" ] && grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' "$WRAPPER" \
   && [ -x "$CORE20" ] && grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$CORE20"; then
  TX="$CORE20"
else
  for candidate in \
    "$STAGE/usr/local/libexec/mechos-update-transaction-v14" \
    "$STAGE/usr/local/libexec/mechos-update-transaction-v13"; do
    if [ -x "$candidate" ] && grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' "$candidate"; then
      TX="$candidate"
      break
    fi
  done
fi
[ -n "$TX" ] || { echo 'Stable bundle does not contain a validated rescue transaction engine.' >&2; exit 12; }

echo "Using staged rescue engine: $TX"
set +e
"$TX" "$STAGE" "$LATEST"
rc=$?
set -e

# Always restore root metadata, including when the transaction reports failure.
chown "$ROOT_UID:$ROOT_GID" /
chmod "$ROOT_MODE" /
[ "$rc" -eq 0 ] || exit "$rc"

mode="$(stat -c '%a' /)"
other="${mode: -1}"
case "$other" in
  1|3|5|7) ;;
  *) echo "Rescue safety failure: root mode became $mode" >&2; exit 60 ;;
esac

mkdir -p /var/lib/mechos
[ "$REBOOT" = 1 ] && touch /var/lib/mechos/reboot-required

echo "MechOS $LATEST staged successfully. Restart MechOS to activate the release."
