#!/usr/bin/env python3
# MECHOS_031_CONTROL_SUITE_V1
from __future__ import annotations
import json, os, shutil, subprocess, sys, time, webbrowser
from pathlib import Path

from PyQt6.QtCore import QProcess, Qt
from PyQt6.QtWidgets import (
    QApplication, QCheckBox, QHBoxLayout, QLabel, QMainWindow, QMessageBox,
    QPushButton, QPlainTextEdit, QScrollArea, QVBoxLayout, QWidget
)

STATE = Path.home()/".local/state/mechos"
CONFIG = Path.home()/".config/mechos"
DATA = Path("/usr/share/mechos/0.3.1")
STATE.mkdir(parents=True, exist_ok=True)
CONFIG.mkdir(parents=True, exist_ok=True)

def run(args, timeout=6):
    try:
        p=subprocess.run(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                         timeout=timeout,check=False)
        return p.returncode,p.stdout.strip()
    except Exception as exc:
        return 127,str(exc)

def detached(program,args=None):
    args=list(args or [])
    p=program if "/" in program else shutil.which(program)
    if not p or not os.path.exists(p):
        return False
    result=QProcess.startDetached(p,args)
    return bool(result[0] if isinstance(result,tuple) else result)

def first(candidates):
    for p,a in candidates:
        if detached(p,a):
            return True
    return False

def update_status():
    helper="/usr/local/bin/mechos-update-helper"
    if not os.path.exists(helper):
        return "Update helper is not installed."
    _,out=run([helper,"status"],8)
    return out or "No update status returned."

def gpu_text():
    rows=[]
    _,pci=run(["lspci"],3)
    for line in pci.splitlines():
        low=line.lower()
        if any(x in low for x in ("vga compatible","3d controller","display controller")):
            rows.append(line)
    for cmd in (["vulkaninfo","--summary"],["pacman","-Q","mesa"],["pacman","-Q","vulkan-radeon"],
                ["pacman","-Q","vulkan-intel"],["pacman","-Q","nvidia-utils"]):
        if shutil.which(cmd[0]):
            rc,out=run(cmd,5)
            if rc==0 and out:
                rows.append(out)
    if not rows:
        rows=["No GPU/Vulkan details detected."]
    return "\n\n".join(rows)

def network_text():
    if not shutil.which("nmcli"):
        return "NetworkManager nmcli is not installed."
    _,dev=run(["nmcli","-f","DEVICE,TYPE,STATE,CONNECTION","device","status"],5)
    _,wifi=run(["nmcli","-f","IN-USE,SSID,SIGNAL,SECURITY","device","wifi","list","--rescan","auto"],8)
    return "DEVICES\n"+dev+"\n\nWI-FI\n"+wifi

def input_text():
    rows=[]
    p=Path("/proc/bus/input/devices")
    if p.exists():
        rows.append("INPUT DEVICES\n"+p.read_text(errors="ignore")[:12000])
    if shutil.which("boltctl"):
        _,out=run(["boltctl","list"],5); rows.append("USB4 / THUNDERBOLT\n"+out)
    else:
        tb=Path("/sys/bus/thunderbolt/devices")
        found=[x.name for x in tb.glob("*")] if tb.exists() else []
        rows.append("USB4 / THUNDERBOLT\n"+("\n".join(found) if found else "No boltctl data or Thunderbolt devices detected."))
    if shutil.which("lsusb"):
        _,out=run(["lsusb"],5); rows.append("USB\n"+out)
    return "\n\n".join(rows)

def crash_text():
    p=STATE/"game-crashes-v031.jsonl"
    if not p.exists():
        return "No MechOS-managed game crashes recorded."
    lines=p.read_text(errors="ignore").splitlines()[-30:]
    return "\n".join(lines)

def compat_text():
    p=DATA/"game-compatibility.json"
    if not p.exists(): return "Compatibility database missing."
    data=json.loads(p.read_text())
    out=[]
    for g in data.get("games",[]):
        out.append(f"{g['name']} — {g['status']}\n{g['notes']}")
    return "\n\n".join(out)

def creator_text():
    p=DATA/"creator-tools.json"
    if not p.exists(): return "Creator catalog missing."
    data=json.loads(p.read_text())
    return "\n".join(f"• {x['name']} — {x['type']} — {x['status']}" for x in data.get("tools",[]))

def bridge_config():
    p=CONFIG/"bridge.json"
    data={"enabled":False,"lan_enabled":False}
    if p.exists():
        try:data.update(json.loads(p.read_text()))
        except Exception:pass
    return p,data

def bridge_status():
    _,out=run(["systemctl","--user","is-active","mechos-bridge.service"],4)
    code=Path.home()/".local/share/mechos/bridge/pair-code"
    pair=code.read_text().strip() if code.exists() else "Generated when bridge starts"
    p,cfg=bridge_config()
    return f"Service: {out or 'inactive'}\nLAN pairing: {'enabled' if cfg.get('lan_enabled') else 'disabled'}\nPair code: {pair}"

class Window(QMainWindow):
    def __init__(self,title,body="",buttons=None,check=None):
        super().__init__(); self.setWindowTitle(title); self.resize(920,650)
        root=QWidget(); lay=QVBoxLayout(root)
        h=QLabel(title); h.setStyleSheet("font-size: 24px; font-weight: 700;"); lay.addWidget(h)
        self.text=QPlainTextEdit(); self.text.setReadOnly(True); self.text.setPlainText(body); lay.addWidget(self.text,1)
        if check:
            self.chk=QCheckBox(check[0]); self.chk.setChecked(check[1]); lay.addWidget(self.chk)
        row=QHBoxLayout()
        for label,fn in buttons or []:
            b=QPushButton(label); b.clicked.connect(fn); row.addWidget(b)
        lay.addLayout(row); self.setCentralWidget(root)

def refresh(win,fn): win.text.setPlainText(fn())

def downloads():
    w=Window("MechOS Downloads & Updates",update_status(),[
        ("Refresh",lambda:refresh(w,update_status)),
        ("Open Update Center",lambda:first([("/usr/local/bin/mechos-update-center",[])])),
        ("Steam Downloads",lambda:first([("steam",["steam://open/downloads"])])),
    ]); return w

def network():
    w=Window("MechOS Network Setup",network_text(),[
        ("Refresh",lambda:refresh(w,network_text)),
        ("Open NetworkManager",lambda:first([("systemsettings",["kcm_networkmanagement"]),("systemsettings",[])])),
    ]); return w

def browser():
    body="MechBrowser uses the maintained Firefox backend and returns to MechScope when Firefox closes.\n\nQuick links:\n• ProtonDB\n• PCGamingWiki\n• Twitch\n• YouTube\n• Discord"
    urls=[("ProtonDB","https://www.protondb.com/"),("PCGamingWiki","https://www.pcgamingwiki.com/"),
          ("Twitch","https://www.twitch.tv/"),("YouTube","https://www.youtube.com/")]
    buttons=[("Open Firefox",lambda:first([("firefox",[])]))]
    for name,url in urls:
        buttons.append((name,lambda _=False,u=url:first([("firefox",[u])])))
    return Window("MechBrowser",body,buttons)

def gpu():
    w=Window("GPU Compatibility",gpu_text(),[("Refresh",lambda:refresh(w,gpu_text))]); return w

def inputs():
    w=Window("USB4 / HOTAS / Controller Setup",input_text(),[
        ("Refresh",lambda:refresh(w,input_text)),
        ("Bluetooth",lambda:first([("systemsettings",["kcm_bluetooth"]),("systemsettings",[])])),
        ("Game Controllers",lambda:first([("systemsettings",["kcm_joystick"]),("systemsettings",[])])),
    ]); return w

def compat():
    w=Window("Windows Game Compatibility",compat_text(),[
        ("Unified Store",lambda:first([("/usr/local/bin/mechos-unified-store",[])])),
        ("Refresh",lambda:refresh(w,compat_text)),
    ]); return w

def creator():
    w=Window("Creator Mode Store",creator_text(),[
        ("Creator Mode",lambda:first([("/usr/local/bin/mechos-creator-mode",[])])),
        ("Bottles",lambda:first([("flatpak",["run","com.usebottles.bottles"]),("bottles",[])])),
        ("Lutris",lambda:first([("lutris",[])])),
    ]); return w

def power():
    _,cur=run(["powerprofilesctl","get"],4) if shutil.which("powerprofilesctl") else (1,"unavailable")
    w=Window("Per-game Power Profiles",f"Current platform profile: {cur}\n\nUse mechos-game-run --id GAME --profile efficiency|balanced|performance -- COMMAND to apply a temporary profile and automatically restore it after exit or crash.",[])
    def setp(p):
        if not shutil.which("powerprofilesctl"): QMessageBox.warning(w,"Power Profiles","powerprofilesctl is unavailable."); return
        rc,out=run(["powerprofilesctl","set",p],5)
        if rc: QMessageBox.warning(w,"Power Profiles",out)
        else: w.text.appendPlainText(f"\nSet platform profile: {p}")
    row=w.centralWidget().layout().itemAt(w.centralWidget().layout().count()-1).layout()
    for label,p in [("Efficiency","power-saver"),("Balanced","balanced"),("Performance","performance")]:
        b=QPushButton(label); b.clicked.connect(lambda _=False,x=p:setp(x)); row.addWidget(b)
    return w

def crashes():
    w=Window("Game Crash Protection",crash_text(),[
        ("Refresh",lambda:refresh(w,crash_text)),
        ("Clear Crash Data",lambda:(STATE/"game-crashes-v031.jsonl").unlink(missing_ok=True) or refresh(w,crash_text)),
    ]); return w

def bridge():
    p,cfg=bridge_config()
    w=Window("Companion & Bridge",bridge_status(),[],("Allow encrypted LAN pairing",bool(cfg.get("lan_enabled"))))
    def save(enable):
        _,d=bridge_config(); d["enabled"]=enable; d["lan_enabled"]=w.chk.isChecked()
        p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(d,indent=2)+"\n")
        if enable: run(["systemctl","--user","enable","--now","mechos-bridge.service"],8)
        else: run(["systemctl","--user","disable","--now","mechos-bridge.service"],8)
        refresh(w,bridge_status)
    row=w.centralWidget().layout().itemAt(w.centralWidget().layout().count()-1).layout()
    for label,val in [("Enable Bridge",True),("Disable Bridge",False)]:
        b=QPushButton(label); b.clicked.connect(lambda _=False,x=val:save(x)); row.addWidget(b)
    return w

MODES={"downloads":downloads,"network":network,"browser":browser,"gpu":gpu,"inputs":inputs,
       "compat":compat,"creator":creator,"power":power,"crashes":crashes,"bridge":bridge}

def main():
    mode=Path(sys.argv[0]).name.removeprefix("mechos-")
    if len(sys.argv)>1 and sys.argv[1] in MODES: mode=sys.argv[1]
    if mode not in MODES: mode="downloads"
    app=QApplication(sys.argv); app.setApplicationName("MechOS 0.3.1")
    w=MODES[mode](); w.show(); raise SystemExit(app.exec())

if __name__=="__main__": main()
