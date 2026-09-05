#!/usr/bin/env python3
# MECHOS_UPDATE_HELPER_TRANSACTIONAL_V13
from pathlib import Path
import sys

p = Path(sys.argv[1] if len(sys.argv) > 1 else '/usr/local/bin/mechos-update-helper')
text = p.read_text(encoding='utf-8')
marker = '# MECHOS_UPDATE_HELPER_TRANSACTIONAL_V13'
if marker in text:
    raise SystemExit(0)

# Earlier Update Center guards deliberately replace rsync with coreutils cp so
# the installed updater does not depend on rsync. Hotfix 13 runs after those
# guards, so accept either historical direct-copy form and replace it with the
# same transactional engine.
copy_blocks = (
    '''  echo "[mechos] Installing verified MechOS-owned files..."\n  if ! cp -a "$stage/." /; then rm -rf "$stage"; return 27; fi\n  rm -rf "$stage"\n''',
    '''  echo "[mechos] Installing verified MechOS-owned files..."\n  if ! rsync -aHAX --safe-links "$stage/" /; then rm -rf "$stage"; return 27; fi\n  rm -rf "$stage"\n''',
)
replacement = '''  echo "[mechos] Installing verified MechOS-owned files transactionally..."\n  # MECHOS_UPDATE_HELPER_TRANSACTIONAL_V13\n  if [ ! -x /usr/local/libexec/mechos-update-transaction-v13 ]; then\n    echo "ERROR: transactional update engine is missing; refusing to modify the running OS."\n    rm -rf "$stage"\n    return 27\n  fi\n  if ! /usr/local/libexec/mechos-update-transaction-v13 "$stage" "$latest"; then\n    echo "ERROR: transactional install failed and the previous system files were restored."\n    rm -rf "$stage"\n    return 28\n  fi\n  rm -rf "$stage"\n'''

for copy_block in copy_blocks:
    if copy_block in text:
        text = text.replace(copy_block, replacement, 1)
        break
else:
    raise SystemExit('supported direct-copy update block not found after Update Center guards')

# Update application may set a restart-required marker, but it must never
# reboot or power off the machine automatically.
for bad in ('systemctl reboot', 'shutdown -r', 'reboot -f', '/sbin/reboot'):
    if bad in text:
        raise SystemExit(f'unsafe automatic reboot command in updater: {bad}')

# Fail before writing if the transactional handoff did not land exactly once.
if text.count(marker) != 1:
    raise SystemExit('transactional updater marker was not installed exactly once')
if text.count('/usr/local/libexec/mechos-update-transaction-v13 "$stage" "$latest"') != 1:
    raise SystemExit('transactional updater handoff was not installed exactly once')

p.write_text(text, encoding='utf-8')
