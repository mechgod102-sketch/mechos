#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VALIDATE_HOTFIX_0315_GT730_MECHSCOPE_UPDATE_HEALTH_V1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n   "$ROOT/scripts/mechscope-session-v20.sh"   "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"   "$ROOT/scripts/mechos-update-helper-core-v39.sh"   "$ROOT/scripts/mechos-update-transaction-v15.sh"   "$ROOT/scripts/build-hotfix-0.3.1-5.sh"
python3 -m py_compile "$ROOT/scripts/mechos-update-center-reference-v8.py"

grep -Fq 'MECHOS_MECHSCOPE_SESSION_V24_GPU_CAPABILITY'   "$ROOT/scripts/mechscope-session-v20.sh"
grep -Fq 'Kernel driver in use: nvidia' "$ROOT/scripts/mechscope-session-v20.sh"
grep -Fq 'Kernel driver in use: nouveau' "$ROOT/scripts/mechscope-session-v20.sh"
grep -Fq 'Vulkan preflight failed GPU=' "$ROOT/scripts/mechscope-session-v20.sh"
grep -Fq 'MECHOS_INTEL_UMA_INTEGRATION_V36' "$ROOT/scripts/mechscope-session-v20.sh"
grep -Fq 'gt730-mixed-generation' "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh"

# GT 730 name alone must not force a single proprietary legacy branch.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/lspci" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK208B [GeForce GT 730] [10de:1287] (rev a1)
        Kernel driver in use: nouveau
        Kernel modules: nouveau
OUT
EOF
chmod 0755 "$tmp/bin/lspci"
branch_out="$(PATH="$tmp/bin:/usr/bin:/bin" bash "$ROOT/scripts/mechos-legacy-gpu-setup-v0311.sh" --branch)"
test "$branch_out" = gt730-mixed-generation

# Update Center must check helper health before invoking repair.
python3 - "$ROOT/scripts/mechos-update-center-reference-v8.py" <<'PY'
from pathlib import Path
import ast,sys
p=Path(sys.argv[1]); src=p.read_text(); tree=ast.parse(src)
cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='UpdateCenter')
helper=next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='helper_ok')
calls=[n.func.attr for n in ast.walk(helper) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute)]
assert 'helper_selftest' in calls
assert 'attempt_self_repair' in calls
text=ast.get_source_segment(src,helper)
assert text.index('helper_selftest') < text.index('attempt_self_repair')
load=next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='load_status')
load_text=ast.get_source_segment(src,load)
assert 'for attempt in (1, 2)' in load_text
assert 'feed/network/signature' in load_text
PY

echo 'MechOS 0.3.1 Hotfix 5 GT 730 and Update Center health-first contracts validated.'
