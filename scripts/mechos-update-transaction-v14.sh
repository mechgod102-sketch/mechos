#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_TRANSACTION_V14
# Hotfix 17: self-contained transaction engine. It deliberately does not depend
# on rsync so a minimal installed MechOS system cannot fail with exit 127 while
# applying an OS bundle.

STAGE="${1:?stage required}"
VERSION="${2:-unknown}"
STATE=/var/lib/mechos
BACKUPS="$STATE/update-backups"
LOG=/var/log/mechos-update-transaction.log
mkdir -p "$BACKUPS" /var/log /var/cache/mechos/update-center
exec >>"$LOG" 2>&1
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d /var/cache/mechos/update-center/tx.XXXXXX)"
BACKUP="$BACKUPS/${VERSION}-${STAMP}.tar"
EXISTING="$WORK/existing.txt"
ADDED="$WORK/added.txt"

cleanup(){ rm -rf "$WORK"; }
trap cleanup EXIT
log(){ printf '[%s] [transaction-v14] %s\n' "$(date -Is 2>/dev/null || date)" "$*"; }
fail(){ log "ERROR: $*"; return 1; }

[ -d "$STAGE" ] || { fail "stage missing: $STAGE"; exit 40; }

# Fail with a useful updater error rather than shell exit 127. Every command in
# this list is provided by MechOS base/core packages.
for cmd in bash python3 find head tar chmod rm mktemp date grep timeout install; do
  command -v "$cmd" >/dev/null 2>&1 || { fail "required base command missing: $cmd"; exit 41; }
done

# Validate staged Python and shell scripts before any system files are changed.
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

# If a future bundle replaces the public updater trio, require the full trio so
# rollback can never leave Update Center without its helper or reboot action.
if [ -e "$STAGE/usr/local/bin/mechos-update-center" ] || [ -e "$STAGE/usr/local/bin/mechos-update-helper" ]; then
  [ -x "$STAGE/usr/local/bin/mechos-update-center" ] || { fail 'bundle touches updater but lacks executable Update Center'; exit 42; }
  [ -x "$STAGE/usr/local/bin/mechos-update-helper" ] || { fail 'bundle touches updater but lacks executable update helper'; exit 42; }
  [ -x "$STAGE/usr/local/bin/mechos-reboot" ] || { fail 'bundle touches updater but lacks executable reboot helper'; exit 42; }
  bash -n "$STAGE/usr/local/bin/mechos-reboot"
fi

# Record replacements/new paths and make a rollback archive before writing.
while IFS= read -r -d '' src; do
  rel="${src#$STAGE/}"
  if [ -e "/$rel" ] || [ -L "/$rel" ]; then
    printf '%s\n' "$rel" >>"$EXISTING"
  else
    printf '%s\n' "$rel" >>"$ADDED"
  fi
done < <(find "$STAGE" \( -type f -o -type l \) -print0)
if [ -s "$EXISTING" ]; then
  tar -C / -cpf "$BACKUP" -T "$EXISTING"
else
  tar -cf "$BACKUP" --files-from /dev/null
fi
chmod 0600 "$BACKUP"

rollback(){
  log 'postflight failed; restoring pre-update files'
  if [ -s "$ADDED" ]; then
    while IFS= read -r rel; do rm -f "/$rel" 2>/dev/null || true; done < <(sort -r "$ADDED")
  fi
  tar --warning=no-timestamp -C / -xpf "$BACKUP" || true
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then rollback; fi; cleanup; exit "$rc"' EXIT

# Copy ordinary payload files with GNU tar, which is part of the base system.
# This replaces the v13 rsync dependency that caused exit 127 on minimal builds.
# Critical updater files are installed explicitly after the ordinary payload.
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

# Postflight contracts.
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

log "transaction committed for $VERSION; rsync-free updater verified; backup=$BACKUP"
trap - EXIT
cleanup
exit 0
