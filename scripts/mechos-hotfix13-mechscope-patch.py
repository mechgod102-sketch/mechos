#!/usr/bin/env python3
# MECHOS_HOTFIX13_MECHSCOPE_PATCH
from pathlib import Path
import re, sys

path=Path(sys.argv[1] if len(sys.argv)>1 else '/usr/local/bin/mechscope')
if not path.is_file() and path.with_name(path.name+'.real').is_file(): path=path.with_name(path.name+'.real')
if not path.is_file(): raise SystemExit(f'MechScope implementation missing: {path}')
text=path.read_text(encoding='utf-8')
marker='# MECHOS_HOTFIX13_FULLSCREEN_STORE_V1'
if marker in text: raise SystemExit(0)

cls=text.find('class MechScope(QMainWindow):')
if cls<0: raise SystemExit('MechScope class missing')

def method_bounds(source,name):
    start=source.find('    def '+name+'(',cls)
    if start<0: return None
    end=source.find('\n    def ',start+8)
    if end<0: end=len(source)
    return start,end

# Make the actual MechScope window scale with the current screen and reassert
# fullscreen after Plasma/VirtualBox has finished mapping the window.
b=method_bounds(text,'build_ui')
if not b: raise SystemExit('MechScope.build_ui missing')
s,e=b
body=text[s:e]
if marker not in body:
    head=body.find('\n')+1
    inject="""        # MECHOS_HOTFIX13_FULLSCREEN_STORE_V1\n        from PyQt6.QtCore import QTimer as _MechTimer\n        _screen=QApplication.primaryScreen()\n        _height=_screen.availableGeometry().height() if _screen else 1080\n        _mech_scale=max(0.52,min(1.20,float(_height)/1080.0))\n        _h=lambda n:max(28,int(float(n)*_mech_scale))\n"""
    body=body[:head]+inject+body[head:]
    body=body.replace("self.setWindowFlag(Qt.WindowType.FramelessWindowHint,True)","self.setWindowFlags(Qt.WindowType.Window | Qt.WindowType.FramelessWindowHint)")
    body=body.replace("self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)","self.setWindowFlags(Qt.WindowType.Window | Qt.WindowType.FramelessWindowHint)")
    body=body.replace("self.setWindowState(Qt.WindowState.WindowFullScreen)","self.setWindowState(Qt.WindowState.WindowFullScreen)\n        _MechTimer.singleShot(0,self.showFullScreen)\n        _MechTimer.singleShot(250,self.showFullScreen)\n        _MechTimer.singleShot(900,self.showFullScreen)",1)
    body=re.sub(r'\.setMinimumHeight\((\d+)\)',lambda m:f'.setMinimumHeight(_h({m.group(1)}))',body)
    text=text[:s]+body+text[e:]

# Open the store in a separate MechScope process. A broken modal child used to
# look like the button did nothing. Separate-process launch gives it its own
# window and log while keeping the main MechScope alive.
b=method_bounds(text,'open_store')
if b:
    s,e=b
    replacement=r'''    def open_store(self):
        # MECHOS_HOTFIX13_STORE_PROCESS_V1
        from pathlib import Path as _Path
        import subprocess as _sp, sys as _sys, time as _time
        _log=_Path.home()/'.local/state/mechos/unified-store-launch.log'
        try:
            _log.parent.mkdir(parents=True,exist_ok=True)
            with _log.open('a',encoding='utf-8') as _f: _f.write(f'[{_time.strftime("%F %T")}] launch requested\n')
            _target=str(_Path(_sys.argv[0]).resolve())
            _sp.Popen([_sys.executable,_target,'--store'],stdout=_log.open('a'),stderr=_sp.STDOUT,start_new_session=True)
        except Exception as _exc:
            try:
                with _log.open('a',encoding='utf-8') as _f: _f.write(f'launch failed: {_exc}\n')
            except Exception: pass
            QMessageBox.critical(self,'MechOS Unified Store',f'Unified Store could not be started.\n\n{_exc}\n\nLog: {_log}')
'''
    text=text[:s]+replacement+text[e:]
else:
    raise SystemExit('MechScope.open_store missing')

# The direct --store route must itself be true fullscreen, not just maximized.
text=text.replace("dialog=UnifiedStore(); dialog.showMaximized(); sys.exit(app.exec())","dialog=UnifiedStore(); dialog.showFullScreen(); QTimer.singleShot(250,dialog.showFullScreen); sys.exit(app.exec())")
text=text.replace("dialog = UnifiedStore(); dialog.showMaximized(); sys.exit(app.exec())","dialog = UnifiedStore(); dialog.showFullScreen(); QTimer.singleShot(250,dialog.showFullScreen); sys.exit(app.exec())")

# Ensure QTimer exists for the top-level --store branch.
if 'QTimer.singleShot(250,dialog.showFullScreen)' in text and not re.search(r'from PyQt6\.QtCore import [^\n]*QTimer',text):
    m=re.search(r'from PyQt6\.QtCore import ([^\n]+)',text)
    if not m: raise SystemExit('QtCore import missing')
    names=m.group(1)
    if 'QTimer' not in names:
        text=text[:m.start(1)]+names+', QTimer'+text[m.end(1):]

compile(text,str(path),'exec')
path.write_text(text,encoding='utf-8')
print(f'patched {path}')
