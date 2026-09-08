#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_TRANSACTION_V14
# MECHOS_UPDATE_TRANSACTION_V20
# MECHOS_UPDATE_TRANSACTION_V25_RELEASE_COMMIT_V1
# Self-contained staged transaction used by Hotfix 25. It preserves the Hotfix
# 20 root-permission guard and atomically commits /etc/mechos/release only after
# every payload/postflight check succeeds.

STAGE="${1:?stage required}"
VERSION="${2:-unknown}"
STATE=/var/lib/mechos
BACKUPS="$STATE/update-backups"
LOG=/var/log/mechos-update-transaction.log
CACHE=/var/cache/mechos/update-center
mkdir -p "$BACKUPS" /var/log "$CACHE"
exec >>"$LOG" 2>&1

STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d "$CACHE/tx-v25.XXXXXX")"
BACKUP="$BACKUPS/${VERSION}-${STAMP}.tar"
EXISTING="$WORK/existing.txt"
ADDED="$WORK/added.txt"
touch "$EXISTING" "$ADDED"

ROOT_MODE="$(stat -c '%a' /)"
ROOT_UID="$(stat -c '%u' /)"
ROOT_GID="$(stat -c '%g' /)"
RELEASE=/etc/mechos/release

cleanup(){ rm -rf "$WORK"; }
log(){ printf '[%s] [transaction-v25] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }
fail(){ log "ERROR: $*"; return 1; }

restore_root(){
  chown "$ROOT_UID:$ROOT_GID" / 2>/dev/null || true
  chmod "$ROOT_MODE" / 2>/dev/null || true
}

rollback(){
  log 'postflight failed; restoring pre-update files'
  if [ -s "$ADDED" ]; then
    while IFS= read -r rel; do rm -f "/$rel" 2>/dev/null || true; done < <(sort -r "$ADDED")
  fi
  tar --warning=no-timestamp -C / -xpf "$BACKUP" || true
  restore_root
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then rollback; fi; cleanup; exit "$rc"' EXIT

[ "$(id -u)" -eq 0 ] || { fail 'transaction requires root'; exit 77; }
[ -d "$STAGE" ] || { fail "stage missing: $STAGE"; exit 40; }
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-hotfix\.[0-9]+(\.[0-9]+)*)?$ ]]; then
  fail "invalid MechOS version: $VERSION"
  exit 40
fi

for cmd in bash python3 find head tar chmod chown rm mktemp date grep timeout install stat sort mv tr; do
  command -v "$cmd" >/dev/null 2>&1 || { fail "required base command missing: $cmd"; exit 41; }
done

# Match the stage root to `/` before creating a tar stream. This keeps the
# archive's `.` metadata from reproducing the Hotfix 20 root-mode regression.
chmod "$ROOT_MODE" "$STAGE"
chown "$ROOT_UID:$ROOT_GID" "$STAGE"

# Validate staged Python and shell scripts before changing the installed root.
python3 - "$STAGE" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
for p in root.rglob('*'):
    if not p.is_file():
        continue
    try:
        raw=p.read_bytes()
    except Exception:
        continue
    first=raw.splitlines()[0] if raw else b''
    if p.suffix=='.py' or b'python' in first:
        try:
            src=raw.decode('utf-8')
        except UnicodeDecodeError:
            continue
        compile(src,str(p),'exec')
PY
while IFS= read -r -d '' f; do
  first="$(head -n1 "$f" 2>/dev/null || true)"
  case "$first" in *bash*|*'/sh'*) bash -n "$f" ;; esac
done < <(find "$STAGE" -type f -print0)

if [ -e "$STAGE/usr/local/bin/mechos-update-center" ] || [ -e "$STAGE/usr/local/bin/mechos-update-helper" ]; then
  [ -x "$STAGE/usr/local/bin/mechos-update-center" ] || { fail 'bundle touches updater but lacks executable Update Center'; exit 42; }
  [ -x "$STAGE/usr/local/bin/mechos-update-helper" ] || { fail 'bundle touches updater but lacks executable update helper'; exit 42; }
  [ -x "$STAGE/usr/local/bin/mechos-reboot" ] || { fail 'bundle touches updater but lacks executable reboot helper'; exit 42; }
  bash -n "$STAGE/usr/local/bin/mechos-reboot"
fi

# Record rollback paths before writing anything. Always protect the installed
# release marker because Hotfix 25 commits it as the transaction's final state.
while IFS= read -r -d '' src; do
  rel="${src#$STAGE/}"
  if [ -e "/$rel" ] || [ -L "/$rel" ]; then
    printf '%s\n' "$rel" >>"$EXISTING"
  else
    printf '%s\n' "$rel" >>"$ADDED"
  fi
done < <(find "$STAGE" \( -type f -o -type l \) -print0)

if [ -e "$RELEASE" ] || [ -L "$RELEASE" ]; then
  grep -Fxq 'etc/mechos/release' "$EXISTING" || printf '%s\n' 'etc/mechos/release' >>"$EXISTING"
else
  grep -Fxq 'etc/mechos/release' "$ADDED" || printf '%s\n' 'etc/mechos/release' >>"$ADDED"
fi

if [ -s "$EXISTING" ]; then
  tar -C / -cpf "$BACKUP" -T "$EXISTING"
else
  tar -cf "$BACKUP" --files-from /dev/null
fi
chmod 0600 "$BACKUP"

# Copy the ordinary payload, then install updater-critical files explicitly.
tar -C "$STAGE" \
  --exclude='./usr/local/bin/mechos-update-center' \
  --exclude='./usr/local/bin/mechos-update-helper' \
  --exclude='./usr/local/bin/mechos-reboot' \
  --exclude='./usr/local/libexec/mechos-update-center-v8.py' \
  --exclude='./usr/local/share/mechos/ui/update_shell.py' \
  --exclude='./usr/local/share/mechos/ui/fixed_canvas.py' \
  -cpf - . | tar --warning=no-timestamp -C / -xpf -

for rel in \
  usr/local/libexec/mechos-update-center-v8.py \
  usr/local/share/mechos/ui/fixed_canvas.py \
  usr/local/share/mechos/ui/update_shell.py \
  usr/local/bin/mechos-update-helper \
  usr/local/bin/mechos-reboot \
  usr/local/bin/mechos-update-center; do
  [ -e "$STAGE/$rel" ] || continue
  install -D -m "$( [ -x "$STAGE/$rel" ] && echo 0755 || echo 0644 )" "$STAGE/$rel" "/$rel"
done

restore_root
mode="$(stat -c '%a' /)"
other="${mode: -1}"
case "$other" in
  1|3|5|7) ;;
  *) fail "root mode became $mode"; exit 60 ;;
esac

# Postflight contracts. Version is intentionally not advanced until all of
# these checks pass.
for f in /usr/local/bin/mechos-update-helper /usr/local/bin/mechos-reboot /usr/local/bin/mechos-update-center; do
  [ -x "$f" ] || { fail "critical updater component missing: $f"; exit 50; }
done
bash -n /usr/local/bin/mechos-update-helper
bash -n /usr/local/bin/mechos-reboot
python3 - <<'PY'
from pathlib import Path
for name in ['/usr/local/libexec/mechos-update-center-v8.py','/usr/local/bin/mechos-performance-center']:
    p=Path(name)
    if p.is_file() and p.read_bytes().splitlines()[0].find(b'python')>=0:
        compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
STATUS="$(timeout 8 /usr/local/bin/mechos-update-helper status 2>&1)" || { fail 'update helper status self-test failed'; exit 51; }
printf '%s\n' "$STATUS" | grep '^CURRENT_MECHOS_VERSION=' >/dev/null || { fail 'update helper status contract missing CURRENT_MECHOS_VERSION'; exit 52; }
printf '%s\n' "$STATUS" | grep '^REBOOT_REQUIRED=' >/dev/null || { fail 'update helper status contract missing REBOOT_REQUIRED'; exit 53; }
[ -x /usr/local/bin/mechos-performance-center ] || { fail 'Performance Center missing after update'; exit 54; }
[ -x /usr/local/bin/mechscope ] || [ -x /usr/local/bin/mechscope.real ] || { fail 'MechScope missing after update'; exit 55; }

# Atomic success-only release commit. If this write fails the EXIT trap restores
# the pre-update release marker and all payload files.
mkdir -p /etc/mechos
RELEASE_TMP="$(mktemp /etc/mechos/.release-v25.XXXXXX)"
printf '%s\n' "$VERSION" >"$RELEASE_TMP"
chmod 0644 "$RELEASE_TMP"
mv -f "$RELEASE_TMP" "$RELEASE"
ACTUAL="$(tr -d '\r\n' <"$RELEASE")"
[ "$ACTUAL" = "$VERSION" ] || { fail "release commit verification failed: expected=$VERSION actual=$ACTUAL"; exit 56; }

log "transaction committed for $VERSION; release marker verified; root metadata preserved; backup=$BACKUP"
trap - EXIT
cleanup
exit 0
