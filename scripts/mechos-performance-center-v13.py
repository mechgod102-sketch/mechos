#!/usr/bin/env python3
# MECHOS_PERFORMANCE_CENTER_V13
from __future__ import annotations
import os, shutil, subprocess, sys, time
from pathlib import Path
from PyQt6.QtCore import QTimer, Qt
from PyQt6.QtWidgets import QApplication, QMainWindow, QMessageBox

UI_DIR=Path('/usr/local/share/mechos/ui')
LOG=Path.home()/'.local/state/mechos/performance-center.log'

def log(msg):
    try:
        LOG.parent.mkdir(parents=True,exist_ok=True)
        with LOG.open('a',encoding='utf-8') as f: f.write(f'[{time.strftime("%F %T")}] {msg}\n')
    except Exception: pass

def spawn(args,parent=None):
    try:
        log('launch: '+' '.join(map(str,args)))
        subprocess.Popen(args,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
        return True
    except Exception as exc:
        log(f'launch failed: {exc}')
        QMessageBox.warning(parent,'MechOS Performance Center',str(exc)); return False

def output(args):
    try:return subprocess.check_output(args,text=True,stderr=subprocess.DEVNULL,timeout=4).strip()
    except Exception:return ''

def profile(name,parent):
    if not shutil.which('powerprofilesctl'):
        QMessageBox.information(parent,'MechOS Performance','Power profile controls are unavailable on this hardware.'); return
    available=output(['powerprofilesctl','list'])
    requested=name
    if name=='performance' and 'performance:' not in available:
        name='balanced' if 'balanced:' in available else name
    p=subprocess.run(['powerprofilesctl','set',name],text=True,capture_output=True)
    if p.returncode==0:
        QMessageBox.information(parent,'MechOS Performance',f'Profile: {name}'+(f' (requested {requested})' if name!=requested else ''))
    else:
        QMessageBox.information(parent,'MechOS Performance',(p.stderr or p.stdout or 'Profile is not supported on this hardware.').strip())

def percent_cpu():
    try:
        def snap():
            v=Path('/proc/stat').read_text().splitlines()[0].split()[1:]; nums=list(map(int,v)); return sum(nums),nums[3]+nums[4]
        t1,i1=snap(); time.sleep(.08); t2,i2=snap(); return round(100*(1-(i2-i1)/max(1,t2-t1)))
    except Exception:return 0

def mem_percent():
    try:
        d={k.rstrip(':'):int(v.split()[0]) for k,v in (line.split(':',1) for line in Path('/proc/meminfo').read_text().splitlines())}
        return round(100*(1-d.get('MemAvailable',0)/max(1,d.get('MemTotal',1))))
    except Exception:return 0

def disk_percent():
    try:
        u=shutil.disk_usage('/'); return round(100*u.used/max(1,u.total))
    except Exception:return 0

def zram_percent():
    try:
        out=output(['bash','-lc',"zramctl --bytes --noheadings -o DATA,DISKSIZE 2>/dev/null | head -n1"]); a,b=map(int,out.split()[:2]); return round(100*a/max(1,b))
    except Exception:return 0

if str(UI_DIR) not in sys.path: sys.path.insert(0,str(UI_DIR))
try:
    from performance_shell import PerformanceShell
except Exception as exc:
    log(f'UI import failed: {exc}')
    raise

class PerformanceCenter(QMainWindow):
    def __init__(self):
        super().__init__(); self.setWindowTitle('MechOS Performance Center')
        actions={
          'report':lambda:spawn(['/usr/local/bin/mechos-optimization-report'],self) if Path('/usr/local/bin/mechos-optimization-report').exists() else self.diagnostics(),
          'auto':lambda:profile('performance',self),'performance':lambda:profile('performance',self),'balanced':lambda:profile('balanced',self),'battery':lambda:profile('power-saver',self),
          'gpu':self.gpu,'diagnostics':self.diagnostics,'monitor':lambda:spawn(['konsole','-e','btop'],self),'storage':self.storage,
          'hud':self.hud,'recorder':self.recorder,'radarai':self.radarai,'updates':lambda:spawn(['/usr/local/bin/mechos-update-center'],self),
        }
        self.ui=PerformanceShell(self,actions,self); self.setCentralWidget(self.ui)
        self.setWindowFlags(Qt.WindowType.Window|Qt.WindowType.FramelessWindowHint)
        self.timer=QTimer(self); self.timer.timeout.connect(self.refresh); self.timer.start(2000); self.refresh()
        QTimer.singleShot(0,self.showFullScreen); QTimer.singleShot(300,self.showFullScreen)
    def refresh(self):
        self.ui.cpu_card.setValue(percent_cpu()); self.ui.ram_card.setValue(mem_percent()); self.ui.disk_card.setValue(disk_percent()); self.ui.zram_card.setValue(zram_percent())
        gpu=output(['bash','-lc',"lspci | grep -Ei 'VGA|3D|Display' | head -n2"] ) or 'GPU unavailable'; self.ui.gpu_label.setText(gpu); self.ui.gpu_summary.setText(gpu.splitlines()[0][:90])
        current=output(['powerprofilesctl','get']) or 'hardware default'; self.ui.profile_badge.setText('PROFILE  '+current.upper()); self.ui.health_label.setText('READY')
    def gpu(self): spawn(['konsole','-e','bash','-lc',"vulkaninfo --summary 2>/dev/null; echo; vainfo 2>/dev/null || true; echo; read -rp 'Press Enter...'"],self)
    def diagnostics(self):
        cmd='/usr/local/bin/mechos-hardware-scan' if Path('/usr/local/bin/mechos-hardware-scan').exists() else '/usr/local/bin/mechos-optimization-report'
        spawn(['konsole','-e','bash','-lc',f"{cmd}; echo; read -rp 'Press Enter...'"],self)
    def storage(self): spawn(['konsole','-e','bash','-lc',"nvme list 2>/dev/null || true; lsblk -d -o NAME,MODEL,SIZE,ROTA,TYPE; echo; read -rp 'Press Enter...'"],self)
    def hud(self): QMessageBox.information(self,'Performance Overlay','MangoHud is available per-game through MechOS game profiles.')
    def recorder(self):
        if shutil.which('gpu-screen-recorder-ui'): spawn(['gpu-screen-recorder-ui'],self)
        elif shutil.which('gsr-ui'): spawn(['gsr-ui'],self)
        else: QMessageBox.information(self,'Recording','GPU Screen Recorder UI is not installed.')
    def radarai(self):
        if shutil.which('flatpak') and subprocess.run(['flatpak','info','io.mechgod.RadarAI'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0: spawn(['flatpak','run','io.mechgod.RadarAI'],self)
        else: QMessageBox.information(self,'RadarAI','RadarAI is not installed yet.')

def main():
    app=QApplication(sys.argv); w=PerformanceCenter(); w.showFullScreen(); return app.exec()
if __name__=='__main__': raise SystemExit(main())
