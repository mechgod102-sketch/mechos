#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/mechos-new-build-final-gate.sh"
HARDENING="$ROOT/scripts/mechos-new-build-final-hardening.sh"
BUILD111="$ROOT/scripts/mechos-build111-firstboot-splash-hotfix.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
fail(){ echo "[validate-new-build-final-gate] ERROR: $*" >&2; exit 1; }

[ -f "$GATE" ] || fail "final clean-build gate is missing"
bash -n "$GATE" || fail "final clean-build gate has invalid shell syntax"
[ -f "$HARDENING" ] || fail "new-build final hardening is missing"
bash -n "$HARDENING" || fail "new-build final hardening has invalid shell syntax"
[ -f "$BUILD111" ] || fail "Build 111 firstboot/splash hotfix is missing"
bash -n "$BUILD111" || fail "Build 111 firstboot/splash hotfix has invalid shell syntax"
[ -f "$PATCHER" ] || fail "Reference v5 patcher is missing"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$PATCHER" || fail "Reference v5 patcher has invalid Python syntax"

grep -Fq 'MECHOS_FINAL_USER_UPDATE_CACHE_V1' "$GATE" || fail "user-writable update cache repair missing"
grep -Fq 'XDG_CACHE_HOME' "$GATE" || fail "per-user update cache path missing"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$GATE" || fail "Return to MechScope does not use shared launcher"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch creator' "$GATE" || fail "Creator Mode does not use shared launcher"
grep -Fq 'systemd-detect-virt' "$GATE" || fail "VM/physical runtime detection missing"
grep -Fq 'nohup /usr/local/bin/mechscope' "$GATE" || fail "MechScope direct fallback missing"
grep -Fq 'nohup /usr/local/bin/mechos-creator-mode' "$GATE" || fail "Creator direct fallback missing"
grep -Fq 'mechos-firstboot-authority.service' "$GATE" || fail "first-boot OOBE authority missing"
grep -Fq 'User=mechos-setup' "$GATE" || fail "temporary setup account handoff missing"
grep -Fq 'Exec=/usr/local/bin/mechos-oobe-start' "$GATE" || fail "OOBE automatic launcher missing"
grep -Fq 'MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V2' "$GATE" || fail "Creator alignment final repair missing"
grep -Fq 'MECHOS_NEW_BUILD_FINAL_GATE_V1' "$GATE" || fail "post-install final gate marker missing"
grep -Fq "printf '0.3.0-hotfix.2\\n'" "$GATE" || fail "installed release metadata is not aligned with Hotfix 2"

# Build 110 Live sudo regression guard. The disposable Live account must remain
# passwordless, while the installed OOBE-created wheel account must use normal
# password authentication. Do not let a generic wheel rule leak into Live.
grep -Fq 'patch_tree "$ROOT" live' "$HARDENING" || fail "Live rootfs is not using the Live auth scope"
grep -Fq 'patch_tree "$tmp" installed' "$HARDENING" || fail "installed payload is not using the installed auth scope"
grep -Fq 'mechos ALL=(ALL:ALL) NOPASSWD: ALL' "$HARDENING" || fail "Live passwordless sudo policy missing"
grep -Fq '%wheel ALL=(ALL:ALL) ALL' "$HARDENING" || fail "installed wheel sudo policy missing"
grep -Fq '99-mechos-live' "$HARDENING" || fail "authoritative late Live sudoers rule missing"
grep -Fq 'installed wheel sudo policy leaked into Live ISO' "$HARDENING" || fail "Live wheel-policy regression assertion missing"
grep -Fq 'Live sudo policy leaked into installed payload' "$HARDENING" || fail "installed-payload Live-policy leak assertion missing"

# Build 111 VM regressions: account creation reached Plasma but did not launch,
# and Plasma displayed its stock KDE splash after the MechOS boot splash.
grep -Fq 'MECHOS_BUILD111_FIRSTBOOT_HANDOFF_V1' "$BUILD111" || fail "Build 111 native OOBE handoff marker missing"
grep -Fq 'MECHOS_BUILD111_OOBE_AUTHORITY_V1' "$BUILD111" || fail "Build 111 final OOBE authority marker missing"
grep -Fq 'mechos-oobe-autostart.service' "$BUILD111" || fail "systemd-user OOBE fallback missing"
grep -Fq 'ConditionUser=mechos-setup' "$BUILD111" || fail "OOBE user service is not restricted to the temporary setup account"
grep -Fq 'ExecStart=/usr/local/bin/mechos-oobe-start' "$BUILD111" || fail "OOBE user service bypasses guarded launcher"
grep -Fq 'passwd -d "$SETUP_USER"' "$BUILD111" || fail "temporary setup account is not made usable for SDDM firstboot"
grep -Fq 'gpasswd -d "$SETUP_USER" wheel' "$BUILD111" || fail "temporary setup account is not removed from wheel"
grep -Fq 'Engine=none' "$BUILD111" || fail "stock KDE/Plasma session splash suppression missing"
grep -Fq 'Theme=mechos' "$BUILD111" || fail "MechOS Plymouth authority check missing"

finalizer_line="$(grep -n 'mechos-finalize-install-payload.sh final' "$PATCHER" | tail -n1 | cut -d: -f1)"
hardening_line="$(grep -n 'mechos-new-build-final-hardening.sh' "$PATCHER" | tail -n1 | cut -d: -f1)"
gate_line="$(grep -n 'mechos-new-build-final-gate.sh' "$PATCHER" | tail -n1 | cut -d: -f1)"
build111_line="$(grep -n 'mechos-build111-firstboot-splash-hotfix.sh' "$PATCHER" | tail -n1 | cut -d: -f1)"
[ -n "$finalizer_line" ] || fail "payload finalizer call missing"
[ -n "$hardening_line" ] || fail "new-build hardening is not wired into the build"
[ -n "$gate_line" ] || fail "new-build final gate is not wired into the build"
[ -n "$build111_line" ] || fail "Build 111 post-install update is not wired into the build"
[ "$hardening_line" -gt "$finalizer_line" ] || fail "new-build hardening must run after payload finalization"
[ "$gate_line" -gt "$hardening_line" ] || fail "new-build gate must run after final hardening"
[ "$build111_line" -gt "$gate_line" ] || fail "Build 111 OOBE/splash update must be the final targeted build stage"

echo '[validate-new-build-final-gate] OK: OOBE, updater, VM/hardware mode switching, Creator alignment, Live/installed sudo separation, Build 111 firstboot launch, KDE splash suppression and final build order are guarded'
