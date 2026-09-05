#!/usr/bin/env python3
"""Teach the legacy Build 118 launcher patch about the current Hotfix 5 router."""
from pathlib import Path

path = Path('/workspace/scripts/mechos-build118-six-regression-final.sh')
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_BUILD125_BUILD118_HOTFIX5_COMPAT'
if marker in text:
    raise SystemExit(0)

old = """if old not in t: raise SystemExit('MechScope launcher fallback anchor missing')
p.write_text(t.replace(old,new,1),encoding='utf-8')
"""
new = r'''# MECHOS_BUILD125_BUILD118_HOTFIX5_COMPAT
if old in t:
    t=t.replace(old,new,1)
else:
    current='''case "$MODE" in\n  gaming|mechscope) "$CONTROL" start >>"$LOG" 2>&1 ;;\n  creator) "$CONTROL" creator >>"$LOG" 2>&1 ;;\n  desktop) "$CONTROL" desktop >>"$LOG" 2>&1 ;;\nesac || { notify_error "${MODE^} could not be started."; exit 1; }\n'''
    current_new='''case "$MODE" in\n  gaming|mechscope) "$CONTROL" start >>"$LOG" 2>&1 ;;\n  creator) "$CONTROL" creator >>"$LOG" 2>&1 ;;\n  desktop) "$CONTROL" desktop >>"$LOG" 2>&1 ;;\nesac || {\n  # MECHOS_BUILD118_DIRECT_MECHSCOPE_FALLBACK\n  if { [ "$MODE" = gaming ] || [ "$MODE" = mechscope ]; } && [ -e /var/lib/mechos/oobe-complete ] && [ -x /usr/local/bin/mechscope ]; then\n    nohup /usr/local/bin/mechscope >>"$LOG" 2>&1 &\n    _pid=$!; sleep 0.8\n    if kill -0 "$_pid" >/dev/null 2>&1; then exit 0; fi\n  fi\n  notify_error "${MODE^} could not be started."\n  exit 1\n}\n'''
    if current not in t:
        raise SystemExit('MechScope launcher fallback anchor missing: neither legacy nor Hotfix 5 launcher layout matched')
    t=t.replace(current,current_new,1)
p.write_text(t,encoding='utf-8')
'''

if old not in text:
    raise SystemExit('[Build 125 compat] Build 118 embedded patch anchor changed unexpectedly')
text = text.replace(old, new, 1)
compile(text, str(path), 'exec')
path.write_text(text, encoding='utf-8')
print('[MechOS Build 125 Compat] Build 118 MechScope patch supports legacy and Hotfix 5 launcher layouts')
