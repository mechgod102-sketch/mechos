#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_TRANSACTION_V13
STAGE="${1:?stage required}"
VERSION="${2:-unknown}"
STATE=/var/lib/mechos
BACKUPS="$STATE/update-backups"
LOG=/var/log/mechos-update-transaction.log
mkdir -p "$BACKUPS" /var/log
exec >>"$LOG" 2>&1
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d /var/cache/mechos/update-center/tx.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
BACKUP="$BACKUPS/${VERSION}-${STAMP}.tar"
EXISTING="$WORK/existing.txt"
ADDED="$WORK/added.txt"

log(){ printf '[%s] [transaction-v13] %s\n' "$(date -Is)" "$*"; }
fail(){ log "ERROR: $*"; return 1; }
[ -d "$STAGE" ] || { fail "stage missing: $STAGE"; exit 40; }

# Validate scripts without writing bytecode into protected system directories.
python3 - "$STAGE" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
for p in root.rglob('*'):
    if not p.is_file(): continue
    try: raw=p.read_bytes()
    except Exception: continue
    first=raw.splitlines()[0] if raw else b''
    if p.suffix=='.py' or b'python' in first:
        try: src=raw.decode('utf-8')
        except UnicodeDecodeError: continue
        compile(src,str(p),'exec')
PY
while IFS= read -r -d '' f; do
  first="$(head -n1 "$f" 2>/dev/null || true)"
  case "$first" in *bash*|*'/sh'*) bash -n "$f" ;; esac
done < <(find "$STAGE" -type f -print0)

# Core surfaces are self-hosting. If an update touches them, require the whole
# validated pair before changing the running OS.
if [ -e "$STAGE/usr/local/bin/mechos-update-center" ] || [ -e "$STAGE/usr/local/bin/mechos-update-helper" ]; then
  [ -x "$STAGE/usr/local/bin/mechos-update-center" ] || fail 'bundle touches updater but lacks executable Update Center'
  [ -x "$STAGE/usr/local/bin/mechos-update-helper" ] || fail 'bundle touches updater but lacks executable update helper'
fi

# Save every file/symlink that will be replaced and track new files so rollback
# can restore the exact pre-update state if postflight fails.
while IFS= read -r -d '' src; do
  rel="${src#$STAGE/}"
  if [ -e "/$rel" ] || [ -L "/$rel" ]; then printf '%s\n' "$rel" >>"$EXISTING"; else printf '%s\n' "$rel" >>"$ADDED"; fi
done < <(find "$STAGE" \( -type f -o -type l \) -print0)
if [ -s "$EXISTING" ]; then tar -C / -cpf "$BACKUP" -T "$EXISTING"; else tar -cf "$BACKUP" --files-from /dev/null; fi
chmod 0600 "$BACKUP"

rollback(){
  log 'postflight failed; restoring pre-update files'
  if [ -s "$ADDED" ]; then tac "$ADDED" | while read -r rel; do rm -f "/$rel" 2>/dev/null || true; done; fi
  tar -C / -xpf "$BACKUP" || true
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then rollback; fi; rm -rf "$WORK"; exit "$rc"' EXIT

# Install ordinary files first. Update Center/helper are applied last so a bad
# app or theme cannot destroy the updater that would be needed for recovery.
rsync -aHAX --safe-links \
  --exclude='usr/local/bin/mechos-update-center' \
  --exclude='usr/local/bin/mechos-update-helper' \
  --exclude='usr/local/libexec/mechos-update-center-v8.py' \
  --exclude='usr/local/share/mechos/ui/update_shell.py' \
  --exclude='usr/local/share/mechos/ui/fixed_canvas.py' \
  "$STAGE/" /

for rel in \
  usr/local/libexec/mechos-update-center-v8.py \
  usr/local/share/mechos/ui/fixed_canvas.py \
  usr/local/share/mechos/ui/update_shell.py \
  usr/local/bin/mechos-update-helper \
  usr/local/bin/mechos-update-center; do
  [ -e "$STAGE/$rel" ] || continue
  install -D -m "$( [ -x "$STAGE/$rel" ] && echo 0755 || echo 0644 )" "$STAGE/$rel" "/$rel"
done

# Postflight: the OS is not accepted unless the updater and user-facing system
# surfaces are still executable and syntactically healthy.
for f in /usr/local/bin/mechos-update-helper /usr/local/bin/mechos-update-center; do [ -x "$f" ] || { fail "critical updater missing: $f"; exit 50; }; done
bash -n /usr/local/bin/mechos-update-helper
python3 - <<'PY'
from pathlib import Path
for name in ['/usr/local/libexec/mechos-update-center-v8.py','/usr/local/bin/mechos-performance-center']:
    p=Path(name)
    if p.is_file() and p.read_bytes().splitlines()[0].find(b'python')>=0:
        compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
STATUS="$(timeout 8 /usr/local/bin/mechos-update-helper status 2>&1)" || { fail 'update helper status self-test failed'; exit 51; }
printf '%s\n' "$STATUS" | grep -q '^CURRENT_MECHOS_VERSION=' || { fail 'update helper status contract missing CURRENT_MECHOS_VERSION'; exit 52; }
printf '%s\n' "$STATUS" | grep -q '^REBOOT_REQUIRED=' || { fail 'update helper status contract missing REBOOT_REQUIRED'; exit 53; }
[ -x /usr/local/bin/mechos-performance-center ] || { fail 'Performance Center missing after update'; exit 54; }
[ -x /usr/local/bin/mechscope ] || [ -x /usr/local/bin/mechscope.real ] || { fail 'MechScope missing after update'; exit 55; }

log "transaction committed for $VERSION; backup=$BACKUP"
trap - EXIT
rm -rf "$WORK"
exit 0
