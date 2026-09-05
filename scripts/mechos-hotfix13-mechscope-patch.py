#!/usr/bin/env python3
# MECHOS_HOTFIX13_MECHSCOPE_PATCH
from pathlib import Path
import re, sys

path=Path(sys.argv[1] if len(sys.argv)>1 else '/usr/local/bin/mechscope')
if not path.is_file() and path.with_name(path.name+'.real').is_file(): path=path.with_name(path.name+'.real')
if not path.is_file(): raise SystemExit(f'MechScope implementation missing: {path}')
text=path.read_text(encoding='utf-8')
marker='# MECHOS_HOTFIX13_FULLSCREEN_STORE_V1'

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
cls=text.find('class MechScope(QMainWindow):')
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

# Add a real provider-install handoff to Unified Store. MechOS routes the job
# to Steam, Lutris, Legendary/Nile when available, or Heroic for Epic/GOG/Amazon.
# Provider authentication, ownership and download bytes remain provider-owned.
store=text.find('class UnifiedStore(')
mech=text.find('\nclass MechScope(QMainWindow):',store)
if store < 0 or mech < 0: raise SystemExit('UnifiedStore class missing')
store_text=text[store:mech]
if 'MECHOS_HOTFIX13_PROVIDER_INSTALL_V1' not in store_text:
    store_text=store_text.replace(
        "ll.addWidget(self.info_button('Install Queue','Managed by Steam / Heroic / Lutris',self.open_selected_launcher))",
        "ll.addWidget(self.info_button('Install Queue','MechOS provider handoffs',self.open_install_queue))"
    )
    store_text=store_text.replace(
        "ll.addWidget(self.info_button('Downloads','Open selected launcher',self.open_selected_launcher))",
        "ll.addWidget(self.info_button('Install / Manage','Route install to selected provider',self.install_selected))"
    )
    methods=r'''
    # MECHOS_HOTFIX13_PROVIDER_INSTALL_V1
    def provider_key(self):
        name=self.STORES[self.selected_store][0].strip().lower()
        return {
            'steam':'steam','epic games':'epic','gog.com':'gog',
            'amazon games':'amazon','heroic':'heroic','lutris':'lutris'
        }.get(name,name.replace(' ',''))

    def install_selected(self):
        controller='/usr/local/bin/mechos-game-install'
        if not Path(controller).is_file():
            QMessageBox.critical(self,'MechOS Unified Store','Provider install controller is missing.\n\nExpected: '+controller)
            return
        provider=self.provider_key()
        value=self.search.text().strip()
        if not value:
            QMessageBox.information(
                self,'Install / Manage',
                'Enter a provider game ID, supported store URL, or game identifier in the search field first.\n\n'
                'Steam accepts an AppID or Steam /app/ URL. Lutris accepts an installer slug. Epic can use an Epic app name when Legendary is available. GOG/Amazon are handed to Heroic when their provider backend is not directly exposed.'
            )
            self.search.setFocus(); return
        try:
            result=subprocess.run([controller,'install',provider,value],text=True,capture_output=True,timeout=8)
        except Exception as exc:
            QMessageBox.critical(self,'Install / Manage',f'Install handoff failed.\n\n{exc}')
            return
        detail=(result.stdout or result.stderr or '').strip()
        if result.returncode==0:
            QMessageBox.information(
                self,'Install / Manage',
                f'Install request handed to {self.STORES[self.selected_store][0]}.\n\n'
                'The official provider client owns authentication, licenses, download location and game files.' +
                (f'\n\n{detail}' if detail else '')
            )
        else:
            QMessageBox.warning(self,'Install / Manage',detail or f'Provider handoff failed with code {result.returncode}.')

    def open_install_queue(self):
        controller='/usr/local/bin/mechos-game-install'
        try:
            out=subprocess.check_output([controller,'status'],text=True,stderr=subprocess.STDOUT,timeout=5)
        except Exception as exc:
            out=f'Install queue unavailable: {exc}'
        QMessageBox.information(self,'MechOS Install Queue',out[-6000:])
'''
    store_text=store_text.rstrip()+methods+'\n'
    text=text[:store]+store_text+text[mech:]

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
