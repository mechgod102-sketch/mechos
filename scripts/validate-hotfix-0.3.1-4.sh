#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX_0314_PACKAGE_REFRESH_STATUS_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/scripts/mechos-update-helper-core-v39.sh"
python3 -m py_compile "$ROOT/scripts/mechos-update-center-reference-v8.py"

grep -Fq 'MECHOS_UPDATE_HELPER_CORE_V39_PACKAGE_REFRESH_STATUS'   "$ROOT/scripts/mechos-update-helper-core-v39.sh"
grep -Fq 'PACMAN_UPDATE_RESULT='   "$ROOT/scripts/mechos-update-helper-core-v39.sh"
grep -Fq 'PACMAN_UPDATE_REPAIRED='   "$ROOT/scripts/mechos-update-helper-core-v39.sh"
grep -Fq 'POST_UPDATE_WARNINGS='   "$ROOT/scripts/mechos-update-helper-core-v39.sh"
grep -Fq 'MECHOS_HOTFIX4_PACKAGE_REFRESH_RESULT_UI'   "$ROOT/scripts/mechos-update-center-reference-v8.py"
grep -Fq 'MechOS updated; package refresh incomplete'   "$ROOT/scripts/mechos-update-center-reference-v8.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/pacman/sync/download-UlFkSv"

cat >"$tmp/bin/pacman" <<'EOF'
#!/usr/bin/env bash
set -eu
state="${FAKE_PACMAN_STATE:?}"
count=0
[ ! -s "$state" ] || count="$(cat "$state")"
if [ "$count" -eq 0 ]; then
  printf '1\n' >"$state"
  mkdir -p "${MECHOS_PACMAN_DB_DIR}/sync/download-UlFkSv"
  echo "error: could not open file ${MECHOS_PACMAN_DB_DIR}/sync/download-UlFkSv/core.db.part: Permission denied" >&2
  echo "error: failed to setup a download payload for core.db" >&2
  echo "error: failed to synchronize all databases (failed to retrieve some files)" >&2
  exit 1
fi
echo ':: Synchronizing package databases...'
echo 'there is nothing to do'
exit 0
EOF
chmod 0755 "$tmp/bin/pacman"

cat >"$tmp/bin/flatpak" <<'EOF'
#!/usr/bin/env bash
echo 'Looking for updates…'
echo 'Nothing to update.'
exit 0
EOF
chmod 0755 "$tmp/bin/flatpak"

export FAKE_PACMAN_STATE="$tmp/pacman-state"
out="$(
  PATH="$tmp/bin:/usr/bin:/bin"   MECHOS_PACKAGE_REFRESH_TEST_MODE=1   MECHOS_PACMAN_DB_DIR="$tmp/pacman"   bash "$ROOT/scripts/mechos-update-helper-core-v39.sh" package-refresh
)"
printf '%s\n' "$out"
grep -Fq 'PACMAN_UPDATE_RESULT=success' <<<"$out"
grep -Fq 'PACMAN_UPDATE_REPAIRED=1' <<<"$out"
grep -Fq 'FLATPAK_UPDATE_RESULT=success' <<<"$out"
grep -Fq 'POST_UPDATE_WARNINGS=0' <<<"$out"
test ! -d "$tmp/pacman/sync/download-UlFkSv"
test "$(cat "$FAKE_PACMAN_STATE")" = 1

cat >"$tmp/bin/pacman" <<'EOF'
#!/usr/bin/env bash
echo 'error: failed retrieving file: network unreachable' >&2
exit 1
EOF
chmod 0755 "$tmp/bin/pacman"

set +e
out="$(
  PATH="$tmp/bin:/usr/bin:/bin"   MECHOS_PACKAGE_REFRESH_TEST_MODE=1   MECHOS_PACMAN_DB_DIR="$tmp/pacman"   bash "$ROOT/scripts/mechos-update-helper-core-v39.sh" package-refresh 2>&1
)"
rc=$?
set -e
printf '%s\n' "$out"
test "$rc" -ne 0
grep -Fq 'PACMAN_UPDATE_RESULT=failed' <<<"$out"
grep -Fq 'PACMAN_UPDATE_REPAIRED=0' <<<"$out"
grep -Fq 'FLATPAK_UPDATE_RESULT=success' <<<"$out"
grep -Fq 'POST_UPDATE_WARNINGS=1' <<<"$out"

echo 'MechOS 0.3.1 Hotfix 4 package refresh contracts validated.'
