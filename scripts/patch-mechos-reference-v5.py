#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: patch-mechos-reference-v5.py <build-script>')

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_REFERENCE_UI_V5_FINAL'
if marker in text:
    raise SystemExit(0)

anchor = '\nmkarchiso -v \\\n'
pos = text.rfind(anchor)
if pos < 0:
    raise SystemExit('[MechOS Reference UI v5] final mkarchiso insertion point not found')
late = text.rfind('# MECHOS_CURRENT_INTEGRATION_LATE', 0, pos)
if late < 0:
    raise SystemExit('[MechOS Reference UI v5] current late integration stage not found before mkarchiso')

insert = '''

# MECHOS_REFERENCE_UI_V5_FINAL
bash /workspace/scripts/mechos-reference-v5-postinstall-stage.sh prepare
bash /workspace/scripts/mechos-reference-v5-integration.sh final
bash /workspace/scripts/mechos-reference-v5-store-layout.sh
bash /workspace/scripts/mechos-reference-v5-mechscope-layout.sh
bash /workspace/scripts/mechos-reference-v5-mechscope-exact-layout.sh
bash /workspace/scripts/mechos-reference-v5-creator-layout.sh
bash /workspace/scripts/mechos-reference-v5-controls-layout.sh
bash /workspace/scripts/mechos-reference-v5-controls-compat.sh
bash /workspace/scripts/mechos-aur-helper-integration.sh
bash /workspace/scripts/mechos-reference-v5-installer-layout.sh
bash /workspace/scripts/mechos-live-update-pacman-sandbox-hotfix.sh
bash /workspace/scripts/mechos-installer-radio-signal-hotfix.sh
bash /workspace/scripts/mechos-live-installer-runtime-guard.sh
bash /workspace/scripts/mechos-live-installer-crash-fallback.sh
bash /workspace/scripts/mechos-vm-ui-runtime-guard.sh
bash /workspace/scripts/mechos-vm-shortcut-launch-hotfix.sh
bash /workspace/scripts/mechos-native-ui-shell-integration.sh
bash /workspace/scripts/mechos-auto-optimization-hotfix.sh
bash /workspace/scripts/mechos-source-owned-system-ui.sh
# Keep any legacy Creator reference compatibility stage from disturbing the
# live native dashboard, then make every Creator Shortcut a distinct real action.
bash /workspace/scripts/mechos-creator-alignment-hotfix.sh
bash /workspace/scripts/mechos-creator-shortcuts-live.sh
bash /workspace/scripts/mechos-update-center-v1-integration.sh
bash /workspace/scripts/mechos-update-center-v1-runtime-guard.sh
bash /workspace/scripts/mechos-update-center-v2-integration.sh
bash /workspace/scripts/mechos-installer-auto-reboot-hotfix.sh
bash /workspace/scripts/mechos-installed-mechscope-launch-hotfix.sh
bash /workspace/scripts/mechos-vm-mode-runtime-final.sh
# FIRST-BOOT SESSION AUTHORITY. Before OOBE completion, installed systems are
# forced into the temporary setup account/Plasma session and VM fullscreen modes
# are blocked. The final gate below reasserts this after payload finalization.
bash /workspace/scripts/mechos-firstboot-session-authority.sh
# VM APP FALLBACK. MechScope and Creator first try their user service and then
# fall back to direct launch in the same Plasma VM graphical session.
bash /workspace/scripts/mechos-vm-app-launch-final.sh
# Install approved Plymouth artwork/theme first, then enforce the actual Live
# ArchISO + native Clean Install boot chain that consumes it.
bash /workspace/scripts/mechos-reference-splash-integration.sh
bash /workspace/scripts/mechos-plymouth-boot-final.sh
bash /workspace/scripts/mechos-reference-v5-postinstall-stage.sh commit
bash /workspace/scripts/mechos-finalize-install-payload.sh final
# NEW BUILD HARDENING. Fix every issue found during VM + hardware testing in the
# actual installed payload: automatic OOBE, wheel/sudo policy, user-writable
# update discovery cache, working Creator/MechScope desktop icons and Creator UI
# coordinate alignment.
bash /workspace/scripts/mechos-new-build-final-hardening.sh
# FINAL INSTALLED-PAYLOAD AUTHORITY. Reassert OOBE, updater, mode-switch
# shortcuts and Creator geometry after payload finalization.
bash /workspace/scripts/mechos-new-build-final-gate.sh
# BUILD 111 POST-INSTALL UPDATE. Account creation now has both KDE/XDG and
# systemd-user launch paths, the temporary setup account is usable but non-admin,
# and Plasma's stock KDE splash is suppressed.
bash /workspace/scripts/mechos-build111-firstboot-splash-hotfix.sh
# UPDATE DISCOVERY AUTHORITY. Keep stable-manifest discovery fresh.
bash /workspace/scripts/mechos-update-manifest-refresh-final.sh
# PRE-OOBE UPDATE AUTHORITY. A temporary mechos-setup session can apply a
# verified update without being asked for a password that cannot exist before
# account creation. The PolicyKit grant remains narrowly scoped.
bash /workspace/scripts/mechos-preoobe-update-auth-final.sh
# BUILD 113 LIVE-BOOT AUTHORITY. This intentionally runs last because Build 112
# could remain on a black screen before the Live desktop. Reassert a visible,
# separate Live splash, repair the SDDM plasma.desktop autologin target, force
# Plymouth to release the VT, and add a redundant single-instance installer
# launcher. It also restores the installed-system splash identity after all
# installed-payload patch passes above.
bash /workspace/scripts/mechos-build113-live-boot-splash-fix.sh
'''

text = text[:pos] + insert + text[pos:]
path.write_text(text, encoding='utf-8')
