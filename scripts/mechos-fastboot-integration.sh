#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS FastBoot] %s\n' "$*"; }
fail() { printf '[MechOS FastBoot] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

patch_tree() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local apps="$tree/usr/share/applications"
  local unit="$tree/etc/systemd/system/mechos-firstboot.service"
  local gpu="$bin/mechos-gpu-setup"
  local session="$bin/mechos-gaming-session"

  mkdir -p "$bin" "$apps"

  # First-boot setup used to wait for network-online and explicitly run before
  # SDDM. That made package/GPU work part of the login critical path. Start it
  # after SDDM instead, at low CPU/IO priority. The post-install stage already
  # creates the installed SDDM configuration, so firstboot no longer needs to
  # hold the display manager hostage.
  mkdir -p "$(dirname "$unit")"
  cat > "$unit" <<'EOF'
[Unit]
Description=MechOS deferred first-boot gaming and GPU setup
After=sddm.service NetworkManager.service
Wants=NetworkManager.service
ConditionPathExists=!/run/archiso/bootmnt
ConditionPathExists=!/var/lib/mechos/firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mechos-firstboot
RemainAfterExit=yes
TimeoutStartSec=5min
Nice=10
IOSchedulingClass=idle
CPUWeight=20
IOWeight=20

[Install]
WantedBy=graphical.target
EOF

  # Do not perform a full system upgrade from the first-boot GPU probe. All
  # normal MechOS GPU stacks are already part of the image; --needed makes this
  # a fast no-op when the correct packages are present and still allows a
  # missing vendor stack to be installed without upgrading the whole OS.
  if [ -f "$gpu" ]; then
    sed -i 's/pacman -Syu --needed --noconfirm/pacman -S --needed --noconfirm/g' "$gpu"
  fi

  # Patch the generated Gaming Mode session. A successful compositor/Vulkan
  # preflight is cached for 24 hours, cutting the repeated timeout budget from
  # as much as 20 seconds on every login. If Gamescope still fails, retry once
  # before falling back to Plasma instead of immediately trapping the user in a
  # relogin loop.
  if [ -f "$session" ]; then
    python3 - "$session" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_FASTBOOT_V1"
if marker not in text:
    start_marker = "# Never allow a broken Vulkan probe to block the login session forever."
    end_marker = 'echo "[MechOS] Starting real Gamescope + MechScope mode."'
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise SystemExit(f"FastBoot could not locate Gaming Mode preflight block in {path}")

    replacement = r'''# MECHOS_FASTBOOT_V1
PRECHECK_STAMP="$STATE_DIR/gaming-preflight.ok"
PRECHECK_FRESH=0
if [ -f "$PRECHECK_STAMP" ] && \
   find "$PRECHECK_STAMP" -mmin -1440 -print -quit 2>/dev/null | grep -q .; then
  PRECHECK_FRESH=1
fi

if [ "$PRECHECK_FRESH" -eq 1 ]; then
  echo "[MechOS] FastBoot: using cached Vulkan/Gamescope preflight."
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

  touch "$PRECHECK_STAMP"
fi

FAIL_COUNT=0
'''.replace('\\"', '"')
    text = text[:start] + replacement + text[end:]

    old = r'''      if [ "$GS_RC" -ne 0 ]; then
        echo "[MechOS] Gamescope failed; entering safe fallback."
        start_plasma_fallback
      fi
      continue'''.replace('\\"', '"')
    new = r'''      if [ "$GS_RC" -ne 0 ]; then
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
    if old not in text:
        raise SystemExit(f"FastBoot could not locate Gaming Mode failure block in {path}")
    text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")
PY
  fi

  # Boot profiler: captures the five slowest units, critical chain, firstboot,
  # SDDM and MechScope logs into one report that can be compared between builds.
  cat > "$bin/mechos-boot-diagnostics" <<'EOF'
#!/usr/bin/env bash
set +e

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
mkdir -p "$STATE_DIR"
REPORT="$STATE_DIR/boot-report-$(date +%Y%m%d-%H%M%S).txt"

exec > >(tee "$REPORT") 2>&1

echo "=== MechOS FastBoot Diagnostics ==="
echo "Generated: $(date -Is)"
echo "Report: $REPORT"
echo

echo "--- Overall boot timing ---"
systemd-analyze time 2>&1 || true

echo
echo "--- Five slowest startup units ---"
systemd-analyze blame --no-pager 2>&1 | head -n 5 || true

echo
echo "--- Graphical critical chain ---"
systemd-analyze critical-chain graphical.target 2>&1 || true

echo
echo "--- MechOS firstboot ---"
systemctl --no-pager --full status mechos-firstboot.service 2>&1 || true
journalctl -b -u mechos-firstboot.service --no-pager -n 100 2>&1 || true

echo
echo "--- SDDM startup ---"
systemctl --no-pager --full status sddm.service 2>&1 || true
journalctl -b -u sddm.service --no-pager -n 100 2>&1 || true

echo
echo "--- GPU ---"
lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true

echo
echo "--- Gaming session log ---"
tail -n 200 "$STATE_DIR/gaming-session.log" 2>/dev/null || true

echo
echo "--- MechScope log ---"
tail -n 200 "$STATE_DIR/mechscope.log" 2>/dev/null || true

echo
echo "--- Cached preflight ---"
if [ -f "$STATE_DIR/gaming-preflight.ok" ]; then
  stat "$STATE_DIR/gaming-preflight.ok" 2>/dev/null || true
else
  echo "No successful Gaming Mode preflight has been cached yet."
fi

echo
echo "FastBoot report saved to: $REPORT"
EOF
  chmod 755 "$bin/mechos-boot-diagnostics"

  cat > "$apps/mechos-boot-diagnostics.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Boot Diagnostics
Comment=Profile boot, SDDM, firstboot and MechScope startup performance
Exec=konsole -e bash -lc '/usr/local/bin/mechos-boot-diagnostics; echo; read -rp "Press Enter to close..."'
Icon=utilities-system-monitor
Terminal=false
Categories=System;Settings;
Keywords=MechOS;Performance;Boot;MechScope;Diagnostics;
EOF
}

patch_tree "$ROOT"

# The installed-system rootfs archive is created before the final cumulative
# integration call. Patch a temporary extracted copy and repack it so installed
# MechOS receives exactly the same FastBoot changes as the live rootfs.
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
bash -n "$ROOT/usr/local/bin/mechos-boot-diagnostics" || fail "boot diagnostics syntax validation failed"
grep -Fq '# MECHOS_FASTBOOT_V1' "$ROOT/usr/local/bin/mechos-gaming-session" \
  || fail "FastBoot Gaming Mode marker is missing"
grep -Fq 'After=sddm.service NetworkManager.service' "$ROOT/etc/systemd/system/mechos-firstboot.service" \
  || fail "firstboot is still on the pre-SDDM critical path"

log "FastBoot v1 applied: deferred firstboot, cached preflight, one retry, boot profiler"
