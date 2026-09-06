#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HOTFIX13_STABILITY_INTEGRATION_V2
ROOT=/workspace/archlive/airootfs
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
REPO=/workspace
log(){ printf '[MechOS Hotfix13 integration] %s\n' "$*"; }
fail(){ printf '[MechOS Hotfix13 integration] ERROR: %s\n' "$*" >&2; exit 1; }
[ -d "$ROOT" ] || fail 'ArchISO rootfs missing'

patch_tree(){
  local tree="$1"
  local mech="$tree/usr/local/bin/mechscope"
  [ -f "$tree/usr/local/bin/mechscope.real" ] && mech="$tree/usr/local/bin/mechscope.real"
  mkdir -p "$tree/usr/local/bin" "$tree/usr/local/libexec" "$tree/usr/local/share/mechos/ui"

  install -m0755 "$REPO/scripts/mechos-update-center-reference-v8.py" "$tree/usr/local/libexec/mechos-update-center-v8.py"
  install -m0755 "$REPO/scripts/mechos-performance-center-v13.py" "$tree/usr/local/bin/mechos-performance-center"
  install -m0755 "$REPO/scripts/mechos-game-install-controller-v13.py" "$tree/usr/local/bin/mechos-game-install"
  install -m0755 "$REPO/scripts/mechos-update-transaction-v13.sh" "$tree/usr/local/libexec/mechos-update-transaction-v13"
  install -m0755 "$REPO/scripts/mechos-update-helper-v13-patch.py" "$tree/usr/local/libexec/mechos-update-helper-v13-patch"
  install -m0755 "$REPO/scripts/mechos-hotfix13-mechscope-patch.py" "$tree/usr/local/libexec/mechos-hotfix13-mechscope-patch"
  install -m0644 "$REPO/src/mechos_ui/fixed_canvas.py" "$tree/usr/local/share/mechos/ui/fixed_canvas.py"
  install -m0644 "$REPO/src/mechos_ui/update_shell.py" "$tree/usr/local/share/mechos/ui/update_shell.py"
  install -m0644 "$REPO/src/mechos_ui/performance_shell.py" "$tree/usr/local/share/mechos/ui/performance_shell.py"

  cat >"$tree/usr/local/bin/mechos-update-center" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mechos/update-center-v13-launch.log"
mkdir -p "$(dirname "$LOG")"
exec /usr/bin/python3 /usr/local/libexec/mechos-update-center-v8.py "$@" >>"$LOG" 2>&1
EOF
  chmod 0755 "$tree/usr/local/bin/mechos-update-center"

  [ -f "$tree/usr/local/bin/mechos-update-helper" ] || fail "update helper missing in $tree"
  python3 "$REPO/scripts/mechos-update-helper-v13-patch.py" "$tree/usr/local/bin/mechos-update-helper"
  bash -n "$tree/usr/local/bin/mechos-update-helper"

  [ -f "$mech" ] || fail "MechScope implementation missing in $tree"
  python3 "$REPO/scripts/mechos-hotfix13-mechscope-patch.py" "$mech"
  chmod 0755 "$mech"

  python3 - "$tree/usr/local/libexec/mechos-update-center-v8.py" "$tree/usr/local/bin/mechos-performance-center" "$tree/usr/local/bin/mechos-game-install" "$mech" <<'PY'
from pathlib import Path
import sys
for name in sys.argv[1:]:
    p=Path(name); compile(p.read_text(encoding='utf-8'),str(p),'exec')
PY
  grep -Fq 'MECHOS_UPDATE_HELPER_TRANSACTIONAL_V13' "$tree/usr/local/bin/mechos-update-helper" || fail 'transactional updater marker missing'
  grep -Fq 'MECHOS_HOTFIX13_FULLSCREEN_STORE_V1' "$mech" || fail 'MechScope fullscreen marker missing'
  grep -Fq 'MECHOS_HOTFIX13_STORE_PROCESS_V1' "$mech" || fail 'Unified Store launch marker missing'
  grep -Fq 'MECHOS_HOTFIX13_PROVIDER_INSTALL_V1' "$mech" || fail 'Unified Store provider install marker missing'
  grep -Fq 'steam://install/' "$tree/usr/local/bin/mechos-game-install" || fail 'Steam install adapter missing'
  grep -Fq 'lutris-installer-uri' "$tree/usr/local/bin/mechos-game-install" || fail 'Lutris install adapter missing'
  grep -Fq 'MECHOS_PERFORMANCE_CENTER_V13' "$tree/usr/local/bin/mechos-performance-center" || fail 'Performance Center v13 marker missing'
  for bad in 'systemctl reboot' 'shutdown -r' 'reboot -f' '/sbin/reboot'; do ! grep -Fq "$bad" "$tree/usr/local/bin/mechos-update-helper" || fail "automatic reboot command found: $bad"; done
}

patch_tree "$ROOT"
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xpf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  replacement="$ARCHIVE.hotfix13"
  tar --zstd -cpf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$ARCHIVE"
  rm -rf "$tmp"; trap - EXIT
fi

# Absolute-final Live installer authority. Run after every older GUI/runtime
# generator so password prompts, automatic disk selection and misrouted Custom
# install paths cannot be restored immediately before mkarchiso.
bash "$REPO/scripts/mechos-live-installer-final-hardening.sh" final

log 'future ISO payload owns transactional updater, working Performance Center, fullscreen MechScope, separate-process Unified Store and provider install controller; Live installer hardening is final'