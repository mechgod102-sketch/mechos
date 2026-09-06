#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HARDWARE_VERIFY_V22_6

EXPECTED_VERSION="0.3.0-hotfix.22.6"
PASS=0
WARN=0
FAIL=0

say(){ printf '%s\n' "$*"; }
pass(){ PASS=$((PASS+1)); printf '[PASS] %s\n' "$*"; }
warn(){ WARN=$((WARN+1)); printf '[WARN] %s\n' "$*"; }
fail(){ FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
is_live(){ [ -e /run/archiso/bootmnt ] || grep -q archiso /proc/cmdline 2>/dev/null; }

section(){ printf '\n== %s ==\n' "$*"; }

say "MechOS physical hardware verification"
say "Expected installed release: $EXPECTED_VERSION"
say "Generated: $(date -Is 2>/dev/null || date)"

section "Build and boot"
if [ -r /etc/mechos/hardware-test-build ]; then
  pass "hardware-test build marker: $(tr '\n' ' ' </etc/mechos/hardware-test-build)"
else
  warn "/etc/mechos/hardware-test-build is missing"
fi

if is_live; then
  warn "running from the Live ISO; installed-system Hotfix 22.6 activation checks are deferred until first installed boot"
else
  current="$(cat /etc/mechos/release 2>/dev/null || true)"
  if [ "$current" = "$EXPECTED_VERSION" ]; then
    pass "installed release is $current"
  else
    fail "installed release is '${current:-unknown}', expected $EXPECTED_VERSION"
  fi
fi

virt="$(systemd-detect-virt 2>/dev/null || true)"
if [ -z "$virt" ] || [ "$virt" = none ]; then
  pass "bare-metal environment detected"
else
  warn "virtualization detected ($virt); this ISO is intended for physical-hardware validation"
fi

if [ -d /sys/firmware/efi ]; then
  pass "UEFI boot detected"
else
  warn "legacy/CSM boot detected; UEFI install path is not being exercised"
fi

section "CPU and firmware"
cpu="$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n1)"
[ -n "$cpu" ] && pass "CPU: $cpu" || warn "CPU model could not be read"
if pacman -Q amd-ucode >/dev/null 2>&1 || pacman -Q intel-ucode >/dev/null 2>&1; then
  pass "CPU microcode package present"
else
  warn "no AMD/Intel microcode package detected"
fi
if pacman -Q linux-firmware >/dev/null 2>&1; then
  pass "linux-firmware installed"
else
  fail "linux-firmware package is missing"
fi

section "Graphics"
gpu_block="$(lspci -nnk 2>/dev/null | awk '/VGA compatible controller|3D controller|Display controller/{show=1; print; next} show && /Kernel driver in use:/{print; show=0}')"
if [ -n "$gpu_block" ]; then
  say "$gpu_block"
  if grep -q 'Kernel driver in use:' <<<"$gpu_block"; then
    pass "GPU has a kernel driver in use"
  else
    fail "GPU detected but no kernel driver is reported in use"
  fi
else
  fail "no VGA/3D/display controller detected"
fi
if have vulkaninfo; then
  if timeout 12s vulkaninfo --summary >/tmp/mechos-vulkan-summary.$$ 2>&1; then
    pass "Vulkan initializes successfully"
    sed -n '1,24p' /tmp/mechos-vulkan-summary.$$
  else
    warn "vulkaninfo did not complete successfully"
  fi
  rm -f /tmp/mechos-vulkan-summary.$$
else
  warn "vulkaninfo is unavailable"
fi

section "Network and Bluetooth"
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
  pass "NetworkManager is active"
else
  fail "NetworkManager is not active"
fi
if have nmcli; then
  nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null || true
  if nmcli -t -f TYPE device status 2>/dev/null | grep -qx wifi; then
    pass "Wi-Fi adapter detected by NetworkManager"
  else
    warn "no Wi-Fi adapter detected; skip if this machine is Ethernet-only"
  fi
fi
if systemctl is-active --quiet bluetooth 2>/dev/null; then
  pass "Bluetooth service is active"
else
  warn "Bluetooth service is not active or no Bluetooth hardware is present"
fi

section "Audio"
if systemctl --user is-active --quiet pipewire 2>/dev/null; then
  pass "PipeWire user service is active"
else
  warn "PipeWire user service is not active in this session"
fi
if have wpctl; then
  if wpctl status >/tmp/mechos-wpctl.$$ 2>&1; then
    pass "WirePlumber/PipeWire device graph responds"
    sed -n '1,40p' /tmp/mechos-wpctl.$$
  else
    warn "wpctl could not query the audio graph"
  fi
  rm -f /tmp/mechos-wpctl.$$
fi

section "Storage"
root_source="$(findmnt -no SOURCE / 2>/dev/null || true)"
[ -n "$root_source" ] && pass "root filesystem mounted from $root_source" || fail "root filesystem source could not be resolved"
lsblk -d -o NAME,MODEL,SIZE,ROTA,TRAN 2>/dev/null || true
if have smartctl; then
  pass "SMART tooling is available"
else
  warn "smartctl is unavailable"
fi
if have nvme; then
  pass "NVMe tooling is available"
else
  warn "nvme-cli is unavailable"
fi

section "Input and controllers"
if compgen -G '/dev/input/event*' >/dev/null; then
  pass "Linux input event devices are present"
else
  fail "no /dev/input/event* devices found"
fi
if compgen -G '/dev/input/js*' >/dev/null; then
  pass "joystick/controller device node detected"
elif have python3 && python3 - <<'PY' >/dev/null 2>&1
from pathlib import Path
raise SystemExit(0 if any(Path('/dev/input').glob('event*')) else 1)
PY
then
  warn "no legacy /dev/input/js* node detected; connect a controller and rerun to verify controller input"
else
  warn "controller detection could not be completed"
fi

section "MechOS runtime fixes"
if is_live; then
  warn "Creator/MechScope installed-runtime checks are skipped on the Live ISO"
else
  if [ -e /var/lib/mechos/hotfix-0.3.0-22.6-applied ]; then
    pass "Hotfix 22.6 activation marker exists"
  else
    fail "Hotfix 22.6 activation marker is missing"
  fi
  if grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_V26' /usr/local/bin/mechscope 2>/dev/null || \
     grep -Fq 'MECHOS_MECHSCOPE_RUNTIME_V26' /usr/local/bin/mechscope.real 2>/dev/null; then
    pass "MechScope persistent runtime v26 is installed"
  else
    fail "MechScope runtime v26 marker is missing"
  fi
  if grep -Fq 'MECHOS_CREATOR_EXTERNAL_QT_HANDOFF_V26' /usr/local/bin/mechos-mode-launch 2>/dev/null; then
    pass "Creator external Qt handoff is active in mode launcher"
  else
    fail "Creator external Qt handoff marker missing from mode launcher"
  fi
  if grep -Fq 'MECHOS_CREATOR_EXTERNAL_QT_HANDOFF_V26' /usr/local/bin/mechos-shell-route 2>/dev/null; then
    pass "Creator external Qt handoff is active in shell router"
  else
    fail "Creator external Qt handoff marker missing from shell router"
  fi
  if systemctl is-failed --quiet mechos-hotfix-0.3.0-22.service 2>/dev/null; then
    fail "Hotfix 22.6 activation service is failed"
  else
    pass "Hotfix 22.6 activation service is not failed"
  fi
fi

section "Hardware utilities"
for cmd in lspci lsusb nmcli wpctl vulkaninfo smartctl nvme; do
  if have "$cmd"; then
    pass "$cmd available"
  else
    warn "$cmd unavailable"
  fi
done

printf '\nRESULT: %d PASS / %d WARN / %d FAIL\n' "$PASS" "$WARN" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  say "Hardware validation found blocking failures. Save this output with the device model before reporting the issue."
  exit 1
fi
say "Core automated hardware checks passed. Manually verify suspend/resume, Wi-Fi reconnect, Bluetooth pairing, audio playback/mic, controller input, MechScope, Creator Mode, and reboot/shutdown on the physical machine."
