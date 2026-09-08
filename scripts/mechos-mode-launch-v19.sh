#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_MODE_LAUNCH_V19
# Backward-compatibility markers: v19 preserves the v15 Creator handoff/VM
# overlay and v16 routing for MechScope-owned pages.
# MECHOS_MODE_LAUNCH_V16
# MECHOS_MODE_LAUNCH_V15
# MECHOS_CREATOR_HANDOFF_V15
# MECHOS_CREATOR_VM_OVERLAY_V15
# MECHOS_CREATOR_EXTERNAL_QT_HANDOFF_V26
# MECHOS_MODE_LAUNCH_VM_DIRECT_V28
# Creator Mode owns its own Qt application and must never be imported/routed
# inside the live MechScope QApplication. On physical hardware use the proven
# external Creator handoff. Installed VMs route all mode changes to the repaired
# Plasma-hosted VM runtime, which also starts Creator as a separate process.

MODE="${1:-}"
ROUTER=/usr/local/bin/mechos-shell-route
BASE=/usr/local/libexec/mechos-mode-launch-base-v15
CREATOR=/usr/local/libexec/mechos-creator-launch-v19
VM_RUNTIME=/usr/local/bin/mechos-vm-mode-runtime

case "$MODE" in
  gaming|mechscope|creator|desktop) ;;
  *) echo 'Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}' >&2; exit 2 ;;
esac

# Mixed-version VMware/VirtualBox/QEMU upgrades must not fall through to an old
# gaming-layer controller. The repaired VM runtime resolves the persistent
# MechScope runtime first and explicitly uses Python for raw Python targets.
virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -n "$virt" ] && [ "$virt" != none ] && \
   [ ! -e /run/archiso/bootmnt ] && ! grep -q archiso /proc/cmdline 2>/dev/null; then
  [ -x "$VM_RUNTIME" ] || {
    echo "MechOS VM runtime is missing: $VM_RUNTIME" >&2
    exit 1
  }
  [ "$MODE" = mechscope ] && MODE=gaming
  exec "$VM_RUNTIME" "$MODE"
fi

case "$MODE" in
  creator)
    [ -x "$CREATOR" ] || { echo 'MechOS Creator launcher is missing' >&2; exit 1; }
    exec "$CREATOR" creator
    ;;
  gaming|mechscope)
    [ -x "$ROUTER" ] || { echo 'MechOS shell router missing' >&2; exit 1; }
    exec "$ROUTER" "$MODE"
    ;;
  desktop)
    [ -x "$BASE" ] || { echo 'MechOS base mode launcher missing' >&2; exit 1; }
    exec "$BASE" desktop
    ;;
esac
