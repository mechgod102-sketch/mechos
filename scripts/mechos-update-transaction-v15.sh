#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_TRANSACTION_V14
# MECHOS_UPDATE_TRANSACTION_V14_031_REPAIR_V1
# MECHOS_UPDATE_TRANSACTION_V14_0312_SELF_REPAIR_V1
# MECHOS_UPDATE_TRANSACTION_V15
# MECHOS_UPDATE_TRANSACTION_V15_AB_ENGINE_ISOLATION_V1
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

# A/B updater isolation: cumulative bundles may carry the stable public
# launchers for old machines, but those launchers are treated as protected
# bootstrap files rather than ordinary hotfix payload.
if [ -e "$STAGE/usr/local/bin/mechos-update-center" ] || [ -e "$STAGE/usr/local/bin/mechos-update-helper" ]; then
  [ -x "$STAGE/usr/local/bin/mechos-update-center" ] || { fail 'bundle carries non-executable Update Center launcher'; exit 42; }
  [ -x "$STAGE/usr/local/bin/mechos-update-helper" ] || { fail 'bundle carries non-executable update helper launcher'; exit 42; }
  [ -x "$STAGE/usr/local/bin/mechos-reboot" ] || { fail 'bundle carries non-executable reboot helper'; exit 42; }
  bash -n "$STAGE/usr/local/bin/mechos-update-center"
  bash -n "$STAGE/usr/local/bin/mechos-update-helper"
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

# Copy ordinary payload while protecting the active updater entry points.
# Engine slots under /usr/local/share/mechos/update-engine/slots are ordinary
# signed payload and can be added safely without replacing the active engine.
tar -C "$STAGE" \
  --exclude='./usr/local/bin/mechos-update-center' \
  --exclude='./usr/local/bin/mechos-update-helper' \
  --exclude='./usr/local/bin/mechos-reboot' \
  --exclude='./usr/local/libexec/mechos-update-center-v8.py' \
  --exclude='./usr/local/libexec/mechos-update-center-v8-rescue.py' \
  --exclude='./usr/local/libexec/mechos-update-transaction-v14' \
  --exclude='./usr/local/libexec/mechos-update-transaction-v15' \
  -cpf - . | tar --warning=no-timestamp -C / -xpf -

# One-time migration/bootstrap only: install the stable public launchers when
# they are missing or are still the pre-A/B implementation. A healthy v38
# launcher is never replaced by an ordinary cumulative hotfix.
if ! grep -Fq 'MECHOS_UPDATE_HELPER_AB_LAUNCHER_V38' /usr/local/bin/mechos-update-helper 2>/dev/null; then
  install -D -m0755 "$STAGE/usr/local/bin/mechos-update-helper" /usr/local/bin/mechos-update-helper
  log 'installed stable A/B update helper launcher'
fi
if ! grep -Fq 'MECHOS_UPDATE_CENTER_AB_LAUNCHER_V38' /usr/local/bin/mechos-update-center 2>/dev/null; then
  install -D -m0755 "$STAGE/usr/local/bin/mechos-update-center" /usr/local/bin/mechos-update-center
  log 'installed stable A/B Update Center launcher'
fi
if [ ! -x /usr/local/bin/mechos-reboot ]; then
  install -D -m0755 "$STAGE/usr/local/bin/mechos-reboot" /usr/local/bin/mechos-reboot
  log 'restored missing reboot helper'
fi

# Activate a new engine slot only when this release actually contains one.
ENGINE_SWITCH=/usr/local/libexec/mechos-update-engine-switch-v38
ENGINE_SLOT="/usr/local/share/mechos/update-engine/slots/$VERSION"
if [ -d "$ENGINE_SLOT" ]; then
  [ -x "$ENGINE_SWITCH" ] || { fail 'A/B Update Engine switcher missing after payload copy'; exit 48; }
  SWITCH_OUT="$("$ENGINE_SWITCH" --activate "$VERSION" 2>&1)" || {
    fail "A/B Update Engine activation failed: $SWITCH_OUT"
    exit 48
  }
  log "$SWITCH_OUT"
fi

# Postflight contracts. Prefer the A/B-aware self-repair system; keep the
# Hotfix 2 repair path only for pre-migration compatibility.
if [ -x /usr/local/libexec/mechos-update-self-repair-v0313 ]; then
  REPAIR_OUT="$(/usr/local/libexec/mechos-update-self-repair-v0313 --repair 2>&1)" || {
    fail "A/B update self-repair failed: $REPAIR_OUT"
    exit 49
  }
  log "$REPAIR_OUT"
elif [ -x /usr/local/libexec/mechos-update-self-repair-v0312 ]; then
  REPAIR_OUT="$(/usr/local/libexec/mechos-update-self-repair-v0312 --repair 2>&1)" || {
    fail "legacy update self-repair failed: $REPAIR_OUT"
    exit 49
  }
  log "$REPAIR_OUT"
fi

for f in /usr/local/bin/mechos-update-helper /usr/local/bin/mechos-reboot /usr/local/bin/mechos-update-center; do
  [ -x "$f" ] || { fail "critical updater component missing: $f"; exit 50; }
done
bash -n /usr/local/bin/mechos-update-helper
bash -n /usr/local/bin/mechos-update-center
bash -n /usr/local/bin/mechos-reboot
grep -Fq 'MECHOS_UPDATE_HELPER_AB_LAUNCHER_V38' /usr/local/bin/mechos-update-helper || { fail 'stable helper launcher contract missing'; exit 50; }
grep -Fq 'MECHOS_UPDATE_CENTER_AB_LAUNCHER_V38' /usr/local/bin/mechos-update-center || { fail 'stable Update Center launcher contract missing'; exit 50; }
if [ -x /usr/local/libexec/mechos-update-engine-switch-v38 ]; then
  /usr/local/libexec/mechos-update-engine-switch-v38 --check >/dev/null || { fail 'active A/B Update Engine slot invalid'; exit 50; }
fi
python3 - <<'PY'
from pathlib import Path
for name in ['/usr/local/libexec/mechos-update-center-v8.py','/usr/local/bin/mechos-performance-center']:
    p=Path(name)
    if p.is_file() and p.read_bytes().splitlines()[0].find(b'python')>=0:
        compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
# Postflight must be local-only. The bundle and signed manifest were already
# verified before this transaction began; requiring another network round trip
# here made successful installs roll back on slow/offline GitHub access.
SELFTEST="$(/usr/local/bin/mechos-update-helper selftest 2>&1)" || { fail "local update helper self-test failed: $SELFTEST"; exit 51; }
printf '%s\n' "$SELFTEST" | grep '^MECHOS_UPDATE_HELPER_SELFTEST=1' >/dev/null || { fail 'update helper local self-test contract missing'; exit 52; }

# Current source-owned MechScope installations are valid with the supervised
# session + source runtime. Older public mechscope/mechscope.real entry points
# remain accepted for backwards compatibility.
if [ -x /usr/local/bin/mechscope ] || [ -x /usr/local/bin/mechscope.real ]; then
  log 'legacy/public MechScope entry point present'
elif [ -x /usr/local/bin/mechscope-session ] && [ -f /usr/local/libexec/mechos-mechscope-source-runtime-v33 ]; then
  log 'source-owned MechScope session/runtime present'
else
  fail 'no supported MechScope runtime entry point found after update'
  exit 55
fi

# Performance Center is useful but is not part of the minimum cumulative OTA
# contract. Do not roll back a valid OS update solely because an older hardware
# image lacks this optional launcher.
if [ ! -x /usr/local/bin/mechos-performance-center ]; then
  log 'WARNING: Performance Center is absent; update remains valid'
fi

log "transaction committed for $VERSION; offline-safe updater postflight verified; backup=$BACKUP"
trap - EXIT
cleanup
exit 0
