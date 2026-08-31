#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS FastBoot] %s\n' "$*"; }
fail() { printf '[MechOS FastBoot] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS FastBoot] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

patch_tree() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local apps="$tree/usr/share/applications"
  local systemd_dir="$tree/etc/systemd/system"
  local unit="$systemd_dir/mechos-firstboot.service"
  local gpu="$bin/mechos-gpu-setup"
  local session="$bin/mechos-gaming-session"

  mkdir -p "$bin" "$apps" "$systemd_dir"

  # Gaming Mode does not need to block the graphical boot waiting for internet.
  # NetworkManager still starts normally; only the wait-online barrier is
  # disabled. Services that actually need networking can still wait/retry on
  # their own.
  ln -sfn /dev/null "$systemd_dir/NetworkManager-wait-online.service"

  # Keep package/GPU setup completely out of both the installer/OOBE critical
  # path and the MechScope login critical path. OOBE reboots after completion,
  # so this deferred service becomes eligible on the following boot.
  cat > "$unit" <<'FIRSTBOOT_EOF'
[Unit]
Description=MechOS deferred first-boot gaming and GPU setup
After=sddm.service NetworkManager.service
Wants=NetworkManager.service
ConditionPathExists=!/run/archiso/bootmnt
ConditionPathExists=/var/lib/mechos/oobe-complete
ConditionPathExists=!/var/lib/mechos/firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mechos-firstboot
RemainAfterExit=yes
TimeoutStartSec=5min
Nice=15
IOSchedulingClass=idle
CPUWeight=10
IOWeight=10

[Install]
WantedBy=graphical.target
FIRSTBOOT_EOF

  # Do not perform a full system upgrade from the first-boot GPU probe.
  if [ -f "$gpu" ]; then
    sed -i 's/pacman -Syu --needed --noconfirm/pacman -S --needed --noconfirm/g' "$gpu"
  fi

  # FastBoot v2: cache Vulkan/Gamescope validation until something relevant
  # changes instead of re-running smoke tests every 24 hours. The signature
  # includes kernel, GPU identity, Gamescope and vulkaninfo binaries. A runtime
  # Gamescope failure invalidates the cache immediately.
  if [ -f "$session" ]; then
    python3 - "$session" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
v2_marker = "# MECHOS_FASTBOOT_V2"

if v2_marker not in text:
    if "# MECHOS_FASTBOOT_V1" in text:
        start = text.find("# MECHOS_FASTBOOT_V1")
    else:
        start = text.find("# Never allow a broken Vulkan probe to block the login session forever.")
    end_marker = 'echo "[MechOS] Starting real Gamescope + MechScope mode."'
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise SystemExit(f"FastBoot v2 could not locate Gaming Mode preflight block in {path}")

    replacement = r'''# MECHOS_FASTBOOT_V2
PRECHECK_STAMP="$STATE_DIR/gaming-preflight.ok"
PRECHECK_SIGNATURE="$STATE_DIR/gaming-preflight.signature"

make_precheck_signature() {
  {
    printf 'kernel=%s\n' "$(uname -r 2>/dev/null || true)"
    for tool in gamescope vulkaninfo; do
      resolved="$(command -v "$tool" 2>/dev/null || true)"
      printf '%s=%s\n' "$tool" "$resolved"
      if [ -n "$resolved" ]; then
        stat -Lc '%n:%Y:%s' "$resolved" 2>/dev/null || true
      fi
    done
    lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' || true
  } | sha256sum | awk '{print $1}'
}

CURRENT_PRECHECK_SIGNATURE="$(make_precheck_signature)"
PRECHECK_FRESH=0
if [ -s "$PRECHECK_STAMP" ] && [ -s "$PRECHECK_SIGNATURE" ] && \
   [ "$(cat "$PRECHECK_SIGNATURE" 2>/dev/null)" = "$CURRENT_PRECHECK_SIGNATURE" ]; then
  PRECHECK_FRESH=1
fi

if [ "$PRECHECK_FRESH" -eq 1 ]; then
  echo "[MechOS] FastBoot v2: hardware/software signature unchanged; skipping preflight."
else
  VULKAN_OK=0
  if command -v vulkaninfo >/dev/null 2>&1; then
    if timeout 3s vulkaninfo --summary >/tmp/mechos-vulkan-summary.log 2>&1; then
      VULKAN_OK=1
      echo "[MechOS] Vulkan preflight passed."
    else
      RC=$?
      echo "[MechOS] Vulkan preflight failed/timed out (rc=$RC)."
    fi
  else
    echo "[MechOS] vulkaninfo not found."
  fi

  if [ "$VULKAN_OK" -ne 1 ] || ! command -v gamescope >/dev/null 2>&1; then
    start_plasma_fallback
  fi

  if ! timeout 5s gamescope -f -- /usr/bin/true >/tmp/mechos-gamescope-test.log 2>&1; then
    RC=$?
    echo "[MechOS] Gamescope smoke test failed/timed out (rc=$RC)."
    start_plasma_fallback
  fi

  printf '%s\n' "$CURRENT_PRECHECK_SIGNATURE" > "$PRECHECK_SIGNATURE"
  touch "$PRECHECK_STAMP"
fi

FAIL_COUNT=0

MECHSCOPE_HANDOFF_UPTIME="$(awk '{print $1}' /proc/uptime 2>/dev/null || true)"
{
  printf 'gamescope_handoff_uptime_seconds=%s\n' "$MECHSCOPE_HANDOFF_UPTIME"
  printf 'preflight_cached=%s\n' "$PRECHECK_FRESH"
  printf 'preflight_signature=%s\n' "$CURRENT_PRECHECK_SIGNATURE"
} > "$STATE_DIR/gaming-launch.metrics"
'''.replace('\\"', '"')

    text = text[:start] + replacement + text[end:]

    original_failure = r'''      if [ "$GS_RC" -ne 0 ]; then
        echo "[MechOS] Gamescope failed; entering safe fallback."
        start_plasma_fallback
      fi
      continue'''.replace('\\"', '"')

    v1_failure = r'''      if [ "$GS_RC" -ne 0 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        rm -f "$PRECHECK_STAMP"
        if [ "$FAIL_COUNT" -le 1 ]; then
          echo "[MechOS] FastBoot: Gamescope failed; retrying once."
          sleep 1
          continue
        fi
        echo "[MechOS] Gamescope failed twice; entering safe Plasma fallback."
        start_plasma_fallback
      fi
      FAIL_COUNT=0
      continue'''.replace('\\"', '"')

    v2_failure = r'''      if [ "$GS_RC" -ne 0 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        rm -f "$PRECHECK_STAMP" "$PRECHECK_SIGNATURE"
        if [ "$FAIL_COUNT" -le 1 ]; then
          echo "[MechOS] FastBoot v2: Gamescope failed; invalidating cache and retrying once."
          sleep 1
          continue
        fi
        echo "[MechOS] Gamescope failed twice; entering safe Plasma fallback."
        start_plasma_fallback
      fi
      FAIL_COUNT=0
      continue'''.replace('\\"', '"')

    if v1_failure in text:
        text = text.replace(v1_failure, v2_failure, 1)
    elif original_failure in text:
        text = text.replace(original_failure, v2_failure, 1)
    elif v2_failure not in text:
        raise SystemExit(f"FastBoot v2 could not locate Gaming Mode failure block in {path}")

    path.write_text(text, encoding="utf-8")
PY
  fi

  # A single comparable optimization report: boot timing, MechScope handoff,
  # idle RAM/CPU, running/failed services and top memory consumers.
  cat > "$bin/mechos-boot-diagnostics" <<'DIAG_EOF'
#!/usr/bin/env bash
set +e

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
mkdir -p "$STATE_DIR"
REPORT="$STATE_DIR/optimization-report-$(date +%Y%m%d-%H%M%S).txt"

exec > >(tee "$REPORT") 2>&1

echo "=== MechOS Optimization Report ==="
echo "Generated: $(date -Is)"
echo "Report: $REPORT"
echo

echo "--- Boot timing ---"
systemd-analyze time 2>&1 || true

echo
echo "--- Ten slowest startup units ---"
systemd-analyze blame --no-pager 2>&1 | head -n 10 || true

echo
echo "--- Graphical critical chain ---"
systemd-analyze critical-chain graphical.target 2>&1 || true

echo
echo "--- MechScope handoff ---"
if [ -s "$STATE_DIR/gaming-launch.metrics" ]; then
  cat "$STATE_DIR/gaming-launch.metrics"
else
  echo "No Gaming Mode handoff metrics recorded yet."
fi

echo
echo "--- Idle system snapshot ---"
printf 'running_services='
systemctl list-units --type=service --state=running --no-legend 2>/dev/null | wc -l
printf 'load_average='
cat /proc/loadavg 2>/dev/null || true
free -h 2>/dev/null || true
df -h / 2>/dev/null || true

echo
echo "--- Top memory consumers ---"
ps -eo pid,comm,%cpu,%mem,rss --sort=-rss 2>/dev/null | head -n 12 || true

echo
echo "--- Failed units ---"
systemctl --failed --no-pager 2>&1 || true

echo
echo "--- Wait-online status ---"
systemctl is-enabled NetworkManager-wait-online.service 2>&1 || true
systemctl status NetworkManager-wait-online.service --no-pager -n 0 2>&1 || true

echo
echo "--- OOBE / deferred firstboot ---"
for marker in /var/lib/mechos/installed /var/lib/mechos/oobe-complete /var/lib/mechos/firstboot.done; do
  if [ -e "$marker" ]; then
    echo "[OK] $marker"
  else
    echo "[MISSING] $marker"
  fi
done
systemctl --no-pager --full status mechos-firstboot.service 2>&1 || true

echo
echo "--- SDDM startup ---"
systemctl --no-pager --full status sddm.service 2>&1 || true

echo
echo "--- GPU ---"
lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true

echo
echo "--- Cached preflight ---"
if [ -f "$STATE_DIR/gaming-preflight.ok" ]; then
  stat "$STATE_DIR/gaming-preflight.ok" 2>/dev/null || true
  printf 'signature='
  cat "$STATE_DIR/gaming-preflight.signature" 2>/dev/null || true
else
  echo "No successful Gaming Mode preflight has been cached yet."
fi

echo
echo "--- Gaming session log ---"
tail -n 120 "$STATE_DIR/gaming-session.log" 2>/dev/null || true

echo
echo "--- MechScope log ---"
tail -n 120 "$STATE_DIR/mechscope.log" 2>/dev/null || true

echo
echo "Optimization report saved to: $REPORT"
DIAG_EOF
  chmod 755 "$bin/mechos-boot-diagnostics"
  ln -sfn mechos-boot-diagnostics "$bin/mechos-optimization-report"

  cat > "$apps/mechos-boot-diagnostics.desktop" <<'DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=MechOS Optimization Report
Comment=Measure boot time, MechScope handoff, idle memory, services and startup bottlenecks
Exec=konsole -e bash -lc '/usr/local/bin/mechos-optimization-report; echo; read -rp "Press Enter to close..."'
Icon=utilities-system-monitor
Terminal=false
Categories=System;Settings;
Keywords=MechOS;Optimization;Performance;Boot;MechScope;Diagnostics;
DESKTOP_EOF
}

patch_tree "$ROOT"

# The installed-system rootfs archive is created before the final cumulative
# integration call. Patch one extracted copy and repack once, so the installed
# OS receives the same optimization policy.
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  new_archive="$ARCHIVE.fastboot"
  tar --zstd -cf "$new_archive" -C "$tmp" .
  mv -f "$new_archive" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
fi

# Keep ArchISO executable permissions explicit for files modified late.
if [ -f "$PROFILE" ]; then
  for path in \
    /usr/local/bin/mechos-gaming-session \
    /usr/local/bin/mechos-boot-diagnostics; do
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="0:0:755"\n' "$path" >> "$PROFILE"
    fi
  done
fi

bash -n "$ROOT/usr/local/bin/mechos-gaming-session" || fail "Gaming Mode syntax validation failed"
bash -n "$ROOT/usr/local/bin/mechos-boot-diagnostics" || fail "optimization report syntax validation failed"
grep -Fq '# MECHOS_FASTBOOT_V2' "$ROOT/usr/local/bin/mechos-gaming-session" \
  || fail "FastBoot v2 Gaming Mode marker is missing"
grep -Fq 'ConditionPathExists=/var/lib/mechos/oobe-complete' "$ROOT/etc/systemd/system/mechos-firstboot.service" \
  || fail "deferred firstboot is not gated behind completed OOBE"
[ -L "$ROOT/etc/systemd/system/NetworkManager-wait-online.service" ] \
  || fail "NetworkManager wait-online is not masked"
grep -Fq 'gamescope_handoff_uptime_seconds' "$ROOT/usr/local/bin/mechos-gaming-session" \
  || fail "MechScope handoff metric is missing"

log "Optimization pass 1 applied: OOBE-safe deferred firstboot, no wait-online barrier, signature-cached preflight, startup/idle metrics"
