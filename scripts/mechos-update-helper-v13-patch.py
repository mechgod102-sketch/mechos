#!/usr/bin/env python3
# MECHOS_UPDATE_HELPER_TRANSACTIONAL_V13
from pathlib import Path
import sys
p=Path(sys.argv[1] if len(sys.argv)>1 else '/usr/local/bin/mechos-update-helper')
text=p.read_text(encoding='utf-8')
marker='# MECHOS_UPDATE_HELPER_TRANSACTIONAL_V13'
if marker in text: raise SystemExit(0)
needle='''  echo "[mechos] Installing verified MechOS-owned files..."\n  if ! rsync -aHAX --safe-links "$stage/" /; then rm -rf "$stage"; return 27; fi\n  rm -rf "$stage"\n'''
replacement='''  echo "[mechos] Installing verified MechOS-owned files transactionally..."\n  # MECHOS_UPDATE_HELPER_TRANSACTIONAL_V13\n  if [ ! -x /usr/local/libexec/mechos-update-transaction-v13 ]; then\n    echo "ERROR: transactional update engine is missing; refusing to modify the running OS."\n    rm -rf "$stage"\n    return 27\n  fi\n  if ! /usr/local/libexec/mechos-update-transaction-v13 "$stage" "$latest"; then\n    echo "ERROR: transactional install failed and the previous system files were restored."\n    rm -rf "$stage"\n    return 28\n  fi\n  rm -rf "$stage"\n'''
if needle not in text:
    raise SystemExit('legacy direct-rsync update block not found')
text=text.replace(needle,replacement,1)
# Update application may set a restart-required marker, but it must never
# reboot or power off the machine automatically.
for bad in ('systemctl reboot','shutdown -r','reboot -f','/sbin/reboot'):
    if bad in text: raise SystemExit(f'unsafe automatic reboot command in updater: {bad}')
p.write_text(text,encoding='utf-8')
