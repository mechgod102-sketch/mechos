#!/usr/bin/env python3
"""Replace Build 118's fragile exact-text MechScope launcher patch with a semantic guard."""
from pathlib import Path
import subprocess

path = Path('/workspace/scripts/mechos-build118-six-regression-final.sh')
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_BUILD118_SEMANTIC_LAUNCHER_GUARD_V2'
if marker in text:
    subprocess.run(['bash', '-n', str(path)], check=True)
    print('[MechOS Build 127 Compat] semantic Build 118 launcher guard already installed')
    raise SystemExit(0)

start_token = 'patch_mode_launcher(){\n'
end_token = '\n}\n\npatch_update_reboot(){'
start = text.find(start_token)
if start < 0:
    raise SystemExit('[Build 127 compat] Build 118 patch_mode_launcher function is missing')
end = text.find(end_token, start)
if end < 0:
    raise SystemExit('[Build 127 compat] Build 118 patch_mode_launcher boundary is missing')
end += 2

replacement = r'''patch_mode_launcher(){
  local tree="$1" file="$1/usr/local/bin/mechos-mode-launch"
  local runtime="$1/usr/local/bin/mechos-vm-mode-runtime"
  [ -f "$file" ] || return 0
  python3 - "$file" "$runtime" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
runtime = Path(sys.argv[2])
t = p.read_text(encoding='utf-8')
semantic = '# MECHOS_BUILD118_SEMANTIC_LAUNCHER_GUARD_V2'
legacy_marker = '# MECHOS_BUILD118_DIRECT_MECHSCOPE_FALLBACK'

if semantic in t:
    raise SystemExit(0)

# Build 118 used to depend on one exact launcher body. Newer MechOS builds may
# route MechScope directly through mechos-vm-mode-runtime or through the older
# gaming-layer controller. Validate capabilities instead of formatting.
has_vm_runtime = 'mechos-vm-mode-runtime' in t
has_controller = 'mechos-gaming-layer-control' in t or '"$CONTROL"' in t
has_mode_route = 'mechscope' in t or 'gaming' in t
if not has_mode_route or not (has_vm_runtime or has_controller):
    raise SystemExit('MechScope launcher semantic route missing: no VM runtime/controller gaming route')

legacy_old = """    if \"$CONTROL\" start >>\"$LOG\" 2>&1; then
      log \"MechScope launch request accepted\"
      exit 0
    fi
    notify_error \"MechScope could not be started.\"
    exit 1
"""
legacy_new = """    if \"$CONTROL\" start >>\"$LOG\" 2>&1; then
      log \"MechScope launch request accepted\"
      exit 0
    fi
    # MECHOS_BUILD118_DIRECT_MECHSCOPE_FALLBACK
    if [ -e /var/lib/mechos/oobe-complete ] && [ -x /usr/local/bin/mechscope ]; then
      nohup /usr/local/bin/mechscope >>\"$LOG\" 2>&1 &
      _pid=$!; sleep 0.8
      if kill -0 \"$_pid\" >/dev/null 2>&1; then exit 0; fi
    fi
    notify_error \"MechScope could not be started.\"
    exit 1
"""

if has_vm_runtime:
    if not runtime.is_file():
        raise SystemExit('MechScope launcher references VM runtime but installed VM runtime is missing')
    rt = runtime.read_text(encoding='utf-8', errors='ignore')
    if ('MECHOS_VM_DIRECT_APP_FALLBACK_V1' not in rt and
            'start_mode_app mechos-vm-mechscope.service' not in rt):
        raise SystemExit('VM MechScope runtime is present but its direct app fallback is missing')
    # The current VM router already owns the fallback. Do not rewrite it just
    # because whitespace, case formatting or error text changed.
elif legacy_marker not in t:
    if legacy_old not in t:
        raise SystemExit('Legacy MechScope controller route exists but safe fallback insertion point is missing')
    t = t.replace(legacy_old, legacy_new, 1)

# Stamp the launcher after semantic validation so later build stages can prove
# that Build 118 accepted the current route without caring about its text shape.
lines = t.splitlines(True)
insert = 1
if len(lines) > 1 and lines[1].lstrip().startswith('set '):
    insert = 2
lines.insert(insert, semantic + '\n')
t = ''.join(lines)
p.write_text(t, encoding='utf-8')
PY
  chmod 0755 "$file"
  bash -n "$file" || fail "mode launcher syntax failed after semantic Build 118 guard"
  grep -Fq 'MECHOS_BUILD118_SEMANTIC_LAUNCHER_GUARD_V2' "$file" \
    || fail "semantic MechScope launcher guard marker missing"
  grep -Eq 'gaming|mechscope' "$file" \
    || fail "MechScope launcher has no gaming/mechscope route"

  if grep -Fq 'mechos-vm-mode-runtime' "$file"; then
    [ -x "$runtime" ] || fail "mode launcher routes to missing VM runtime"
    grep -Eq 'MECHOS_VM_DIRECT_APP_FALLBACK_V1|start_mode_app mechos-vm-mechscope.service' "$runtime" \
      || fail "VM runtime lacks MechScope direct-launch fallback"
  else
    grep -Fq 'MECHOS_BUILD118_DIRECT_MECHSCOPE_FALLBACK' "$file" \
      || fail "legacy controller launcher lacks Build 118 direct fallback"
  fi
}
'''

text = text[:start] + replacement + text[end:]
path.write_text(text, encoding='utf-8')
subprocess.run(['bash', '-n', str(path)], check=True)

patched = path.read_text(encoding='utf-8')
required = (
    marker,
    "has_vm_runtime = 'mechos-vm-mode-runtime' in t",
    "MECHOS_VM_DIRECT_APP_FALLBACK_V1",
    "legacy controller launcher lacks Build 118 direct fallback",
)
missing = [item for item in required if item not in patched]
if missing:
    raise SystemExit('[Build 127 compat] semantic launcher guard incomplete: ' + ', '.join(missing))

print('[MechOS Build 127 Compat] Build 118 now validates MechScope routes semantically; exact launcher formatting is no longer an anchor')
