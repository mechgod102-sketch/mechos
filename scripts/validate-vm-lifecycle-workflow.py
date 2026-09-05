#!/usr/bin/env python3
from pathlib import Path
import py_compile
import sys

root = Path(__file__).resolve().parents[1]
workflow = root / '.github/workflows/vm-smoke-test.yml'
runner = root / 'scripts/vm_lifecycle_runner.py'
text = workflow.read_text(encoding='utf-8')
runner_text = runner.read_text(encoding='utf-8')

required_workflow = [
    'name: VM Lifecycle Test MechOS ISO',
    'timeout-minutes: 90',
    'qemu-img create -f qcow2',
    '-boot once=d,menu=on',
    'scripts/vm_lifecycle_runner.py',
    'Audit installed filesystem and first-boot cleanup',
    'mechvmtest',
    'oobe-complete',
    'mechos-update-center',
    'mechos-recovery-center',
    'mechos-quick-actions',
    'mechos-creator-mode',
    'mechos-mode-launch',
    'mechos-reboot',
    'MechOS-VM-lifecycle-',
]
required_runner = [
    'Live -> install -> OOBE -> post-install lifecycle',
    '1705, 978',
    'mechvmtest',
    'MechOSvm1234',
    'Creator Store',
    'Creator Settings',
    'Unified Store',
    '/usr/local/bin/mechos-update-center',
    '/usr/local/bin/mechos-recovery-center',
    '/usr/local/bin/mechos-quick-actions',
    '/usr/local/bin/mechos-creator-mode',
    '/usr/local/bin/mechos-mode-launch mechscope',
    '/usr/local/bin/mechos-reboot',
]

missing = [token for token in required_workflow if token not in text]
missing += [token for token in required_runner if token not in runner_text]
if missing:
    print('VM lifecycle contract missing:', file=sys.stderr)
    for token in missing:
        print(' -', token, file=sys.stderr)
    raise SystemExit(1)

py_compile.compile(str(runner), doraise=True)
print('PASS: full Live-to-postinstall VM lifecycle workflow contract is present and runner compiles')
