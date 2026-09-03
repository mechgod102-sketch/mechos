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

# Insert immediately before the final ArchISO build command. Older cumulative
# patchers are allowed to add any number of integration lines above mkarchiso,
# so do not depend on an exact two-line relationship with current-integration.
anchor = '\nmkarchiso -v \\\n'
pos = text.rfind(anchor)
if pos < 0:
    raise SystemExit('[MechOS Reference UI v5] final mkarchiso insertion point not found')

# Sanity-check that the current late integration stage exists before the final
# build. This protects against accidentally inserting v5 into an unrelated
# script that merely happens to invoke mkarchiso.
late = text.rfind('# MECHOS_CURRENT_INTEGRATION_LATE', 0, pos)
if late < 0:
    raise SystemExit('[MechOS Reference UI v5] current late integration stage not found before mkarchiso')

insert = '''

# MECHOS_REFERENCE_UI_V5_FINAL
# The approved visual reference is the last UI authority. Creator Mode and
# Quick Actions remain post-install-only: they are temporarily materialized
# from the install payload for v5 patching, captured back into the payload, and
# removed from Live before mkarchiso.
bash /workspace/scripts/mechos-reference-v5-postinstall-stage.sh prepare
bash /workspace/scripts/mechos-reference-v5-integration.sh final
bash /workspace/scripts/mechos-reference-v5-store-layout.sh
bash /workspace/scripts/mechos-reference-v5-mechscope-layout.sh
# Legacy compatibility pass. It may provide runtime helpers, but the actual
# MechScope composition is replaced by the source-owned shell below.
bash /workspace/scripts/mechos-reference-v5-mechscope-exact-layout.sh
bash /workspace/scripts/mechos-reference-v5-creator-layout.sh
bash /workspace/scripts/mechos-reference-v5-controls-layout.sh
bash /workspace/scripts/mechos-reference-v5-controls-compat.sh
# Add the native MechOS AUR helper after Update Center's final reference layout
# exists, so its AUR Packages entry cannot be overwritten by an earlier UI pass.
bash /workspace/scripts/mechos-aur-helper-integration.sh
bash /workspace/scripts/mechos-reference-v5-installer-layout.sh
# Keep-Home Live Update runs against an installed root from the Live image.
# Repair Pacman 7+ DownloadUser/sandbox prerequisites before its online package
# refresh and keep a one-invocation chroot-only sandbox fallback available.
bash /workspace/scripts/mechos-live-update-pacman-sandbox-hotfix.sh
# Python 3.14/PyQt6 can abort if a Qt toggled callback raises. Initialize the
# default Clean Install radio with signals blocked and guard future callbacks.
bash /workspace/scripts/mechos-installer-radio-signal-hotfix.sh
bash /workspace/scripts/mechos-live-installer-runtime-guard.sh
# The reference installer remains the normal UI. If it terminates abnormally,
# keep the Live environment installable through a separately confirmed safe
# fallback that uses the same native MechOS install backends.
bash /workspace/scripts/mechos-live-installer-crash-fallback.sh
# VM behavior is applied before final visual authority so it can change
# rendering policy without being allowed to redesign the authored shell.
bash /workspace/scripts/mechos-vm-ui-runtime-guard.sh
# Desktop and application-menu mode shortcuts share one entrypoint. It imports
# the active graphical environment into systemd --user and applies VM-only
# rendering/Gamescope flags before the persistent mode service is started.
bash /workspace/scripts/mechos-vm-shortcut-launch-hotfix.sh
# FINAL MECHSCOPE VISUAL AUTHORITY. This installs the repository-owned 1920x1080
# composition after every generated/reference/VM patch. No later integration is
# allowed to replace MechScope.build_ui() with stretch-factor layouts.
bash /workspace/scripts/mechos-native-ui-shell-integration.sh
bash /workspace/scripts/mechos-reference-v5-postinstall-stage.sh commit
bash /workspace/scripts/mechos-finalize-install-payload.sh final
'''

text = text[:pos] + insert + text[pos:]
path.write_text(text, encoding='utf-8')
