#!/usr/bin/env python3
# MECHOS_LEGACY_GPU_CONTROL_PATCH_V0311
from pathlib import Path
import sys

p=Path(sys.argv[1])
text=p.read_text(encoding='utf-8')
marker='# MECHOS_LEGACY_GPU_CONTROL_V0311'
if marker in text:
    raise SystemExit(0)

anchor='def gpu_text():\n'
if anchor not in text:
    raise SystemExit('gpu_text anchor missing')
text=text.replace(anchor, marker+'\n'+anchor,1)

old='''    if not rows:
        rows=["No GPU/Vulkan details detected."]
    return "\\n\\n".join(rows)
'''
new='''    legacy="/usr/local/bin/mechos-legacy-gpu-setup"
    if os.path.exists(legacy) and os.access(legacy, os.X_OK):
        rc,out=run([legacy,"--report"],10)
        if out:
            rows.append("LEGACY GPU COMPATIBILITY\\n"+out)
    if not rows:
        rows=["No GPU/Vulkan details detected."]
    return "\\n\\n".join(rows)
'''
if old not in text:
    raise SystemExit('gpu_text body anchor missing')
text=text.replace(old,new,1)

old_gpu='''def gpu():
    w=Window("GPU Compatibility",gpu_text(),[("Refresh",lambda:refresh(w,gpu_text))]); return w
'''
new_gpu='''def gpu():
    def legacy_setup():
        first([
            ("konsole",["-e","/usr/local/bin/mechos-legacy-gpu-setup","--report"]),
            ("xterm",["-e","/usr/local/bin/mechos-legacy-gpu-setup","--report"]),
        ])
    w=Window("GPU Compatibility",gpu_text(),[
        ("Refresh",lambda:refresh(w,gpu_text)),
        ("Legacy GPU Report",legacy_setup),
    ]); return w
'''
if old_gpu not in text:
    raise SystemExit('gpu window anchor missing')
text=text.replace(old_gpu,new_gpu,1)
p.write_text(text,encoding='utf-8')
