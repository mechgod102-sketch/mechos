#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
POSTINSTALL="$PAYLOAD/mechos-postinstall-target"

log() { printf '[MechOS Bootloader] %s\n' "$*"; }
fail() { printf '[MechOS Bootloader] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Bootloader] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -f "$POSTINSTALL" ] || fail "post-install target is missing: $POSTINSTALL"

if ! grep -Fq 'MECHOS_GRAPHICAL_BOOTLOADER_POSTINSTALL' "$POSTINSTALL"; then
cat >> "$POSTINSTALL" <<'MECHOS_BOOTLOADER_POSTINSTALL_EOF'

# MECHOS_GRAPHICAL_BOOTLOADER_POSTINSTALL
# Install and configure the MechOS graphical boot menu after the target system
# exists. The previous bootloader is never deleted; a failed GRUB install keeps
# the existing boot path available as a fallback.
cat > /usr/local/sbin/mechos-bootloader-theme <<'MECHOS_BOOTLOADER_HELPER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

THEME_DIR="/boot/grub/themes/mechos"
THEME_FILE="$THEME_DIR/theme.txt"
BACKGROUND="$THEME_DIR/mechos-background.tga"
GRUB_DEFAULT_FILE="/etc/default/grub"

log() { printf '[MechOS Bootloader] %s\n' "$*"; }
warn() { printf '[MechOS Bootloader] WARNING: %s\n' "$*" >&2; }

make_background() {
  mkdir -p "$THEME_DIR"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$BACKGROUND" <<'PY'
from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
w, h = 1280, 720
header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, w, h, 24, 0)
with path.open('wb') as f:
    f.write(header)
    for y in range(h):
        fy = y / max(1, h - 1)
        row = bytearray()
        for x in range(w):
            fx = x / max(1, w - 1)
            # Dark MechOS base with cool-blue and purple edge glows.
            blue_glow = max(0.0, 1.0 - abs(fx - 0.16) / 0.42)
            purple_glow = max(0.0, 1.0 - abs(fx - 0.84) / 0.42)
            horizon = max(0.0, 1.0 - abs(fy - 0.53) / 0.42)
            r = int(5 + 18 * purple_glow + 9 * horizon)
            g = int(8 + 14 * blue_glow + 5 * horizon)
            b = int(20 + 40 * blue_glow + 28 * purple_glow + 7 * horizon)

            # Subtle tactical grid and bright center horizon.
            if (x % 80) < 2 or (y % 80) < 2:
                r += 6; g += 7; b += 11
            if abs(y - int(h * 0.53)) < 2:
                r += 28; g += 20; b += 42

            r = max(0, min(255, r))
            g = max(0, min(255, g))
            b = max(0, min(255, b))
            row.extend((b, g, r))
        f.write(row)
PY
  fi
}

write_theme() {
  mkdir -p "$THEME_DIR"
  cat > "$THEME_FILE" <<'MECHOS_GRUB_THEME_EOF'
desktop-color: "#050816"
desktop-image: "mechos-background.tga"
desktop-image-scale-method: "stretch"
title-text: "MECHOS  //  SYSTEM BOOT"
title-color: "#c4b5fd"

+ label {
  left = 12%
  top = 15%
  width = 76%
  height = 40
  text = "SELECT BOOT TARGET"
  color = "#60a5fa"
  align = "center"
}

+ boot_menu {
  left = 18%
  top = 26%
  width = 64%
  height = 44%
  item_color = "#dbeafe"
  selected_item_color = "#c084fc"
  item_height = 42
  item_padding = 12
  item_spacing = 8
  icon_width = 28
  icon_height = 28
  item_icon_space = 10
  scrollbar = false
}

+ progress_bar {
  id = "__timeout__"
  left = 25%
  top = 76%
  width = 50%
  height = 5
  fg_color = "#8b5cf6"
  bg_color = "#172033"
}

+ label {
  id = "__timeout__"
  left = 20%
  top = 79%
  width = 60%
  height = 28
  color = "#94a3b8"
  align = "center"
}

+ label {
  left = 8%
  top = 91%
  width = 84%
  height = 24
  text = "UP/DOWN Navigate   ENTER Boot   E Edit   C Console   ESC Back"
  color = "#7c8aa5"
  align = "center"
}
MECHOS_GRUB_THEME_EOF
}

write_grub_defaults() {
  [ -f "$GRUB_DEFAULT_FILE" ] || touch "$GRUB_DEFAULT_FILE"
  # Remove an older MechOS theme block before appending the current one.
  sed -i '/^# MECHOS_GRAPHICAL_BOOTLOADER_BEGIN$/,/^# MECHOS_GRAPHICAL_BOOTLOADER_END$/d' "$GRUB_DEFAULT_FILE"
  cat >> "$GRUB_DEFAULT_FILE" <<'MECHOS_GRUB_DEFAULTS_EOF'

# MECHOS_GRAPHICAL_BOOTLOADER_BEGIN
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=6
GRUB_GFXMODE=auto
GRUB_TERMINAL_OUTPUT=gfxterm
GRUB_THEME="/boot/grub/themes/mechos/theme.txt"
GRUB_DISTRIBUTOR="MechOS"
GRUB_DISABLE_OS_PROBER=false
# MECHOS_GRAPHICAL_BOOTLOADER_END
MECHOS_GRUB_DEFAULTS_EOF
}

find_esp() {
  local candidate fs
  for candidate in /efi /boot/efi /boot; do
    [ -d "$candidate" ] || continue
    if mountpoint -q "$candidate" 2>/dev/null; then
      fs="$(findmnt -no FSTYPE "$candidate" 2>/dev/null || true)"
      case "$fs" in
        vfat|fat|fat32) printf '%s\n' "$candidate"; return 0 ;;
      esac
    fi
  done

  # If the ESP is in fstab but not mounted yet, return its mountpoint and let
  # the caller try mounting it before installing GRUB.
  awk '($2=="/efi" || $2=="/boot/efi" || $2=="/boot") && ($3=="vfat" || $3=="fat" || $3=="fat32") {print $2; exit}' /etc/fstab 2>/dev/null || true
}

ensure_grub_tools() {
  if command -v grub-install >/dev/null 2>&1 && command -v grub-mkconfig >/dev/null 2>&1; then
    return 0
  fi
  if command -v pacman >/dev/null 2>&1; then
    log "Installing GRUB boot-menu tools on the installed system"
    pacman -S --needed --noconfirm grub efibootmgr os-prober || return 1
  fi
  command -v grub-install >/dev/null 2>&1 && command -v grub-mkconfig >/dev/null 2>&1
}

install_mechos_grub() {
  if ! ensure_grub_tools; then
    warn "GRUB tools are unavailable; leaving the existing bootloader unchanged."
    return 0
  fi

  make_background
  write_theme
  write_grub_defaults

  if [ -d /sys/firmware/efi ]; then
    local esp
    esp="$(find_esp)"
    if [ -z "$esp" ]; then
      warn "No mounted EFI System Partition was found. Theme files were prepared, but the existing bootloader remains active."
      return 0
    fi
    if ! mountpoint -q "$esp" 2>/dev/null; then
      mkdir -p "$esp"
      mount "$esp" 2>/dev/null || {
        warn "Could not mount the EFI System Partition at $esp; keeping the existing bootloader."
        return 0
      }
    fi

    log "Installing MechOS GRUB EFI entry at $esp"
    if ! grub-install --target=x86_64-efi --efi-directory="$esp" --bootloader-id=MechOS --recheck; then
      warn "GRUB EFI installation failed; the previous bootloader was not removed."
      return 0
    fi
  else
    # On legacy BIOS installs, only theme an already-installed GRUB instance.
    # Installing a new BIOS bootloader requires choosing the physical disk and
    # is intentionally left to the installer/recovery UI.
    if [ ! -d /boot/grub ]; then
      warn "Legacy BIOS system without an existing GRUB install; leaving its current bootloader unchanged."
      return 0
    fi
  fi

  if command -v os-prober >/dev/null 2>&1; then
    os-prober || true
  fi
  if grub-mkconfig -o /boot/grub/grub.cfg; then
    log "MechOS graphical bootloader configured successfully"
  else
    warn "Could not regenerate grub.cfg; the previous boot path remains available."
  fi
}

install_mechos_grub
MECHOS_BOOTLOADER_HELPER_EOF
chmod 755 /usr/local/sbin/mechos-bootloader-theme

# Apply the graphical bootloader during post-install, before OOBE/MechScope is
# ever shown. Failure is non-fatal because the existing bootloader is retained.
/usr/local/sbin/mechos-bootloader-theme || echo "[MechOS Bootloader] WARNING: graphical bootloader setup did not complete; existing bootloader retained." >&2
MECHOS_BOOTLOADER_POSTINSTALL_EOF
fi

bash -n "$POSTINSTALL" || fail "post-install target syntax failed after graphical bootloader integration"
grep -Fq 'MECHOS_GRAPHICAL_BOOTLOADER_POSTINSTALL' "$POSTINSTALL" \
  || fail "graphical bootloader post-install marker is missing"
grep -Fq '/usr/local/sbin/mechos-bootloader-theme' "$POSTINSTALL" \
  || fail "bootloader theme helper is missing from post-install target"
grep -Fq 'GRUB_THEME="/boot/grub/themes/mechos/theme.txt"' "$POSTINSTALL" \
  || fail "MechOS GRUB theme configuration is missing"

log "Post-install graphical bootloader integration added"
