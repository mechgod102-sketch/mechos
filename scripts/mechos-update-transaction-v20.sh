#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_TRANSACTION_V14
# MECHOS_UPDATE_TRANSACTION_V20
# Prevent update staging-directory metadata from ever being applied to the
# installed root directory. mktemp creates STAGE as 0700; the older tar copy
# included the archive's `.` entry, which could therefore change `/` to 0700.

STAGE="${1:?stage required}"
VERSION="${2:-unknown}"
CORE=/usr/local/libexec/mechos-update-transaction-core-v20

[ "$(id -u)" -eq 0 ] || { echo 'MechOS transaction requires root.' >&2; exit 77; }
[ -d "$STAGE" ] || { echo "MechOS stage missing: $STAGE" >&2; exit 40; }
[ -x "$CORE" ] || { echo "MechOS transaction core missing: $CORE" >&2; exit 41; }

ROOT_MODE="$(stat -c '%a' /)"
ROOT_UID="$(stat -c '%u' /)"
ROOT_GID="$(stat -c '%g' /)"

# Make the stage root mirror `/` before the legacy tar stream is created. This
# makes the archive's `.` metadata harmless even if an older core sees it.
chmod "$ROOT_MODE" "$STAGE"
chown "$ROOT_UID:$ROOT_GID" "$STAGE"

set +e
"$CORE" "$STAGE" "$VERSION"
rc=$?
set -e

# Belt-and-suspenders restoration. A failed transaction must not strand the
# machine with an untraversable root directory.
chown "$ROOT_UID:$ROOT_GID" /
chmod "$ROOT_MODE" /

# Root must remain traversable by normal users. Abort rather than claiming a
# successful update if this invariant is ever broken again.
mode="$(stat -c '%a' /)"
other="${mode: -1}"
case "$other" in
  1|3|5|7) ;;
  *) echo "MechOS transaction safety failure: root mode became $mode" >&2; exit 60 ;;
esac

exit "$rc"
