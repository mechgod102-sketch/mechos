#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPLASH="$ROOT/branding/mechos-splash-reference.png"
INTEGRATION="$ROOT/scripts/mechos-reference-splash-integration.sh"
FINAL="$ROOT/scripts/mechos-plymouth-boot-final.sh"
BUILD113="$ROOT/scripts/mechos-build113-live-boot-splash-fix.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
fail(){ echo "[validate-reference-splash] ERROR: $*" >&2; exit 1; }

[ -s "$SPLASH" ] || fail "branding/mechos-splash-reference.png missing"
[ -f "$INTEGRATION" ] || fail "reference splash integration missing"
[ -f "$FINAL" ] || fail "final Plymouth boot-chain integration missing"
[ -f "$BUILD113" ] || fail "Build 113 Live boot/splash authority missing"
bash -n "$INTEGRATION" || fail "reference splash integration shell syntax failed"
bash -n "$FINAL" || fail "final Plymouth boot-chain shell syntax failed"
bash -n "$BUILD113" || fail "Build 113 Live boot/splash authority shell syntax failed"

grep -Fq 'MECHOS_REFERENCE_SPLASH_V1' "$INTEGRATION" || fail "reference Plymouth marker missing"
grep -Fq 'Image("mechos-splash-reference.png")' "$INTEGRATION" || fail "Plymouth is not loading the approved reference image"
grep -Fq 'reference.original.Scale' "$INTEGRATION" || fail "reference image is not scaled for the active display"
grep -Fq 'Theme=mechos' "$INTEGRATION" || fail "Plymouth theme selection missing"

grep -Fq 'mkinitcpio.conf.d/*.conf' "$FINAL" || fail "ArchISO/native mkinitcpio drop-in support missing"
grep -Fq "for sub in ('efiboot/loader/entries','syslinux','grub')" "$FINAL" || fail "Live bootloader config coverage missing"
grep -Fq 'archisobasedir=' "$FINAL" || fail "Live ArchISO kernel-option detection missing"
grep -Fq 'quiet splash loglevel=3' "$FINAL" || fail "Live/native kernel splash options missing"
grep -Fq 'MECHOS_NATIVE_PLYMOUTH_BOOT_V1' "$FINAL" || fail "native Clean Install Plymouth marker missing"
grep -Fq 'mechos-native-install-helper' "$FINAL" || fail "native installer helper is not targeted"
grep -Fq 'GRUB_CMDLINE_LINUX_DEFAULT' "$FINAL" || fail "native GRUB splash enforcement missing"
grep -Fq 'plymouth-set-default-theme mechos' "$FINAL" || fail "native theme selection missing"

# Build 113 regression guards: Build 112 could show a black screen forever and
# never reach the Live installer. The final authority must separate the Live and
# installed themes, put artwork on a visible layer, release Plymouth before SDDM,
# use the real plasma.desktop session, and provide a redundant installer launch.
grep -Fq 'MECHOS_BUILD113_VISIBLE_SPLASH_V1' "$BUILD113" || fail "Build 113 visible splash marker missing"
grep -Fq 'Theme=mechos-live' "$BUILD113" || fail "separate Live Plymouth theme missing"
grep -Fq 'reference.sprite.SetZ(10)' "$BUILD113" || fail "Build 113 artwork is not on a visible layer"
grep -Fq 'LOADING MECHOS LIVE ENVIRONMENT' "$BUILD113" || fail "Live splash wording missing"
grep -Fq 'STARTING MECHOS' "$BUILD113" || fail "installed splash wording missing"
grep -Fq 'Session=plasma.desktop' "$BUILD113" || fail "Live SDDM session repair missing"
grep -Fq 'mechos-live-plymouth-release.service' "$BUILD113" || fail "Live Plymouth release service missing"
grep -Fq 'mechos-live-installer.service' "$BUILD113" || fail "Live installer systemd-user fallback missing"
grep -Fq 'flock -n 9' "$BUILD113" || fail "Live installer duplicate-launch lock missing"

grep -Fq 'mechos-reference-splash-integration.sh' "$PATCHER" || fail "reference splash not wired into final build chain"
grep -Fq 'mechos-plymouth-boot-final.sh' "$PATCHER" || fail "final Plymouth boot-chain authority not wired"
grep -Fq 'mechos-build113-live-boot-splash-fix.sh' "$PATCHER" || fail "Build 113 Live boot authority not wired"
python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text()
a=text.find('mechos-reference-splash-integration.sh')
b=text.find('mechos-plymouth-boot-final.sh')
c=text.find('mechos-reference-v5-postinstall-stage.sh commit')
d=text.find('mechos-preoobe-update-auth-final.sh')
e=text.find('mechos-build113-live-boot-splash-fix.sh')
if min(a,b,c,d,e)<0 or not (a < b < c < d < e):
    raise SystemExit('[validate-reference-splash] Build 113 Live boot authority must be the final splash/session pass after installed-payload updates')
PY

echo '[validate-reference-splash] OK: visible split Live/installed splashes, Live Plymouth release, plasma.desktop session, and installer fallback are enforced'
