#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX22_APPLY_V7
# MECHOS_HOTFIX22_FINAL_STATE_RECONCILE_V24
# MECHOS_HOTFIX22_MECHSCOPE_REFERENCE_COMPAT_V25
STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-22.5-applied"
LOG=/var/log/mechos-hotfix-0.3.0-22.5.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 22.5 cumulative apply start"
[ -e "$MARKER" ] && exit 0
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }
is_live && { echo 'Live ISO detected; installed-system apply skipped.'; exit 0; }

# The cumulative bundle already installs the final versions of the updater,
# transaction engine and launchers. Re-running every historical patcher over
# those final files caused old text anchors to mutate newer code. Only layers
# that still need to transform the generated MechScope/Creator owners are run;
# updater layers 17-20 are reconciled from their final installed contracts.
apply_legacy_layer(){
  local n="$1"
  local layer_marker="$STATE/hotfix-0.3.0-${n}-applied"
  local helper="/usr/local/libexec/mechos-hotfix-0.3.0-${n}-apply"
  if [ -e "$layer_marker" ]; then
    echo "[$(date -Is)] Hotfix ${n} already active; skipping"
    return 0
  fi
  [ -x "$helper" ] || { echo "ERROR: cumulative Hotfix ${n} helper missing: $helper"; exit $((120 + n)); }
  echo "[$(date -Is)] Activating cumulative Hotfix ${n}"
  "$helper"
  [ -e "$layer_marker" ] || { echo "ERROR: Hotfix ${n} helper returned without creating $layer_marker"; exit $((140 + n)); }
}

mark_reconciled(){
  local n="$1"
  touch "$STATE/hotfix-0.3.0-${n}-applied"
  echo "[$(date -Is)] Hotfix ${n} final-state contracts verified; historical patcher not replayed"
}

apply_legacy_layer 15
apply_legacy_layer 16

if [ ! -e "$STATE/hotfix-0.3.0-17-applied" ]; then
  echo "[$(date -Is)] Reconciling cumulative Hotfix 17 from final installed state"
  [ -x /usr/local/bin/mechos-update-helper ] || { echo 'ERROR: Hotfix17 final helper missing'; exit 157; }
  [ -x /usr/local/libexec/mechos-update-transaction-core-v20 ] || { echo 'ERROR: Hotfix17 final transaction core missing'; exit 157; }
  [ -x /usr/local/libexec/mechos-update-transaction-v13 ] || { echo 'ERROR: Hotfix17 final v13 compatibility wrapper missing'; exit 157; }
  [ -x /usr/local/libexec/mechos-update-transaction-v14 ] || { echo 'ERROR: Hotfix17 final v14 compatibility wrapper missing'; exit 157; }
  [ -f /usr/local/libexec/mechos-update-center-v8.py ] || { echo 'ERROR: Hotfix17 final Update Center missing'; exit 157; }
  grep -Fq 'MECHOS_HOTFIX17_HELPER_WARNING_FIX' /usr/local/bin/mechos-update-helper
  grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' /usr/local/libexec/mechos-update-transaction-core-v20
  grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' /usr/local/libexec/mechos-update-transaction-v13
  grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' /usr/local/libexec/mechos-update-transaction-v14
  grep -Fq 'MECHOS_HOTFIX17_FAILURE_STATE_FIX' /usr/local/libexec/mechos-update-center-v8.py
  bash -n /usr/local/bin/mechos-update-helper
  bash -n /usr/local/libexec/mechos-update-transaction-core-v20
  bash -n /usr/local/libexec/mechos-update-transaction-v13
  bash -n /usr/local/libexec/mechos-update-transaction-v14
  python3 -m py_compile /usr/local/libexec/mechos-update-center-v8.py
  mark_reconciled 17
fi

if [ ! -e "$STATE/hotfix-0.3.0-18-applied" ]; then
  echo "[$(date -Is)] Reconciling cumulative Hotfix 18 from final installed state"
  [ -x /usr/local/bin/mechos-update-helper ] || { echo 'ERROR: Hotfix18 helper missing'; exit 158; }
  [ -x /usr/local/libexec/mechos-update-helper-core-v18 ] || { echo 'ERROR: Hotfix18 core missing'; exit 158; }
  [ -x /usr/local/libexec/mechos-pacman-health-v18 ] || { echo 'ERROR: Hotfix18 pacman health helper missing'; exit 158; }
  grep -Fq 'MECHOS_UPDATE_HELPER_V18' /usr/local/bin/mechos-update-helper
  grep -Fq 'MECHOS_PACMAN_HEALTH_V18' /usr/local/libexec/mechos-pacman-health-v18
  bash -n /usr/local/libexec/mechos-pacman-health-v18
  /usr/local/libexec/mechos-pacman-health-v18
  mark_reconciled 18
fi

if [ ! -e "$STATE/hotfix-0.3.0-19-applied" ]; then
  echo "[$(date -Is)] Reconciling cumulative Hotfix 19 from final installed state"
  for f in \
    /usr/local/bin/mechos-update-center \
    /usr/local/bin/mechos-update-helper \
    /usr/local/bin/mechos-reboot \
    /usr/local/bin/mechos-update-rescue \
    /usr/local/bin/mechos-mode-launch \
    /usr/local/bin/mechos-shell-route \
    /usr/local/bin/mechscope-session \
    /usr/local/libexec/mechos-creator-launch-v19; do
    [ -x "$f" ] || { echo "ERROR: Hotfix19 final component missing: $f"; exit 159; }
  done
  grep -Fq 'MECHOS_UPDATE_HELPER_V19' /usr/local/bin/mechos-update-helper
  grep -Fq 'MECHOS_UPDATE_RESCUE_V19' /usr/local/bin/mechos-update-rescue
  grep -Fq 'MECHOS_MODE_LAUNCH_V19' /usr/local/bin/mechos-mode-launch
  grep -Fq 'MECHOS_SHELL_ROUTE_V19' /usr/local/bin/mechos-shell-route
  grep -Fq 'MECHOS_MECHSCOPE_SESSION_V19' /usr/local/bin/mechscope-session
  grep -Fq 'MECHOS_CREATOR_HANDOFF_V15' /usr/local/libexec/mechos-creator-launch-v19
  status_tmp="$(mktemp /tmp/mechos-hotfix22-status.XXXXXX)"
  if ! /usr/local/bin/mechos-update-helper status >"$status_tmp" 2>&1; then
    cat "$status_tmp" || true
    rm -f "$status_tmp"
    echo 'ERROR: Hotfix19 final update helper status self-test failed'
    exit 159
  fi
  grep -Fq 'CURRENT_MECHOS_VERSION=' "$status_tmp"
  rm -f "$status_tmp"
  mark_reconciled 19
fi

if [ ! -e "$STATE/hotfix-0.3.0-20-applied" ]; then
  echo "[$(date -Is)] Reconciling cumulative Hotfix 20 from final installed state"
  for f in \
    /usr/local/libexec/mechos-update-transaction-v13 \
    /usr/local/libexec/mechos-update-transaction-v14 \
    /usr/local/libexec/mechos-update-transaction-core-v20; do
    [ -x "$f" ] || { echo "ERROR: Hotfix20 final transaction component missing: $f"; exit 160; }
    bash -n "$f"
  done
  grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' /usr/local/libexec/mechos-update-transaction-v13
  grep -Fq 'MECHOS_UPDATE_TRANSACTION_V20' /usr/local/libexec/mechos-update-transaction-v14
  grep -Fq 'MECHOS_UPDATE_TRANSACTION_V14' /usr/local/libexec/mechos-update-transaction-core-v20
  mode="$(stat -c '%a' /)"
  other="${mode: -1}"
  case "$other" in 1|3|5|7) ;; *) echo "ERROR: installed root directory is not traversable (mode=$mode)"; exit 160 ;; esac
  mark_reconciled 20
fi

apply_legacy_layer 21

for n in 15 16 17 18 19 20 21; do
  [ -e "$STATE/hotfix-0.3.0-${n}-applied" ] || { echo "ERROR: cumulative activation incomplete at Hotfix ${n}"; exit 170; }
done

echo "[$(date -Is)] Hotfixes 15-21 confirmed active; applying Hotfix 22 icon layer"

MODULE=/usr/local/share/mechos/ui/creator_real_icons_v22.py
PATCH=/usr/local/libexec/mechos-creator-real-icons-owner-v22-patch
[ -f "$MODULE" ] || { echo "ERROR: Creator real-icon module missing: $MODULE"; exit 90; }
[ -x "$PATCH" ] || { echo "ERROR: Creator owner patch missing: $PATCH"; exit 91; }
python3 -m py_compile "$MODULE" "$PATCH"

TARGET=/usr/local/bin/mechos-creator-mode
[ -f /usr/local/bin/mechos-creator-mode.real ] && TARGET=/usr/local/bin/mechos-creator-mode.real
[ -f "$TARGET" ] || { echo 'ERROR: Creator Mode implementation missing'; exit 92; }

grep -Fq 'MECHOS_HOTFIX10_CREATOR_VISUAL_OWNER_V1' "$TARGET" || {
  echo 'ERROR: Creator visual owner v10 is not active; refusing an unsafe icon-only patch.'
  exit 93
}
python3 "$PATCH" "$TARGET"
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
compile(t,str(p),'exec')
assert 'MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1' in t
assert "creator_real_icons_v22.py" in t
assert 'icons.install(shell)' in t
PY

grep -Fq 'MECHOS_CREATOR_REAL_ICONS_V22' "$MODULE"
grep -Fq '/var/lib/flatpak/appstream' "$MODULE"
grep -Fq '/var/lib/flatpak/exports/share/applications' "$MODULE"
grep -Fq 'QIcon.fromTheme' "$MODULE"

# MECHOS_HOTFIX22_3_MECHSCOPE_PERSISTENT_RUNTIME
# MECHOS_HOTFIX22_5_MECHSCOPE_REFERENCE_COMPAT
RUNTIME=/usr/local/libexec/mechos-mechscope-runtime-v23
COMPAT=/usr/local/share/mechos/ui/mechscope_reference_compat_v25.py
OWNER=/usr/local/libexec/mechscope-owner-v23.py
MECH_TARGET=/usr/local/bin/mechscope
[ -f /usr/local/bin/mechscope.real ] && MECH_TARGET=/usr/local/bin/mechscope.real

[ -x "$RUNTIME" ] || { echo "ERROR: MechScope persistent runtime missing: $RUNTIME"; exit 94; }
[ -f "$COMPAT" ] || { echo "ERROR: MechScope reference compatibility module missing: $COMPAT"; exit 94; }
python3 -m py_compile "$RUNTIME" "$COMPAT"
grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_V25' "$RUNTIME"
grep -Fq 'MECHOS_MECHSCOPE_REFERENCE_COMPAT_V25' "$COMPAT"
grep -Fq 'class MechReferenceGauge' "$COMPAT"
grep -Fq 'def mechos_gpu_load_percent' "$COMPAT"

if grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_V23' "$MECH_TARGET" 2>/dev/null; then
  [ -f "$OWNER" ] || { echo 'ERROR: MechScope runtime already installed but preserved owner is missing'; exit 95; }
else
  [ -f "$MECH_TARGET" ] || { echo "ERROR: MechScope implementation missing: $MECH_TARGET"; exit 96; }
  install -D -m0755 "$MECH_TARGET" "$OWNER"
fi

python3 - "$OWNER" <<'PY'
from pathlib import Path
import ast,sys
p=Path(sys.argv[1])
text=p.read_text(encoding='utf-8')
compile(text,str(p),'exec')
tree=ast.parse(text,str(p))
classes={node.name for node in tree.body if isinstance(node,ast.ClassDef)}
if 'MechScope' not in classes:
    raise SystemExit('preserved MechScope owner has no top-level MechScope class')
PY

install -m0755 "$RUNTIME" "$MECH_TARGET"
grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_V23' "$MECH_TARGET"
grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_V25' "$MECH_TARGET"
grep -Fq 'install_owner_compat(module)' "$MECH_TARGET"
grep -Fq 'QApplication.instance()' "$MECH_TARGET"
grep -Fq 'app.exec()' "$MECH_TARGET"
echo "[$(date -Is)] MechScope persistent runtime installed target=$MECH_TARGET owner=$OWNER compat=$COMPAT"

mkdir -p /etc/mechos
printf '0.3.0-hotfix.22.5\n' >/etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.22.5/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.22.5\n' >>/etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 22.5\n' >/etc/system-release

rm -f "$STATE/reboot-required"
touch "$MARKER"
echo "[$(date -Is)] Hotfix 22.5 applied: final-state recovery remains active and the persistent MechScope runtime now restores missing MechReferenceGauge and GPU-load helpers from a source-owned compatibility module before constructing the generated owner."
