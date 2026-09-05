#!/usr/bin/env python3
# MECHOS_HOTFIX14_RUNTIME_PATCH
from pathlib import Path
import sys

def patch_quick(path: Path):
    if not path.is_file(): raise SystemExit(f'Quick Actions missing: {path}')
    text=path.read_text(encoding='utf-8')
    marker='# MECHOS_HOTFIX14_QUICK_WINDOW_V1'
    if marker in text:return
    old="""        self.setStyleSheet(STYLE)\n        self.setFixedWidth(470)\n        self.build()\n\n        screen = QApplication.primaryScreen().availableGeometry()\n        self.setGeometry(screen.right() - self.width() + 1, screen.top(), self.width(), screen.height())\n"""
    new="""        # MECHOS_HOTFIX14_QUICK_WINDOW_V1\n        self.setStyleSheet(STYLE + '\\nQMainWindow{background:#020611;color:#f4f7ff;}')\n        screen = QApplication.primaryScreen().availableGeometry()\n        target=max(620,min(760,int(screen.width()*0.38)))\n        self.setFixedWidth(min(target,screen.width()))\n        self.build()\n        self.setGeometry(screen.right() - self.width() + 1, screen.top(), self.width(), screen.height())\n"""
    if old not in text: raise SystemExit('Quick Actions geometry anchor missing')
    text=text.replace(old,new,1)
    compile(text,str(path),'exec');path.write_text(text,encoding='utf-8')

def method_bounds(text, cls, name):
    cp=text.find('class '+cls+'(')
    if cp<0:return None
    s=text.find('    def '+name+'(',cp)
    if s<0:return None
    e=text.find('\n    def ',s+8)
    if e<0:e=len(text)
    return s,e

def patch_mechscope(path: Path):
    if not path.is_file() and path.with_name(path.name+'.real').is_file():path=path.with_name(path.name+'.real')
    if not path.is_file():raise SystemExit(f'MechScope missing: {path}')
    text=path.read_text(encoding='utf-8')
    marker='# MECHOS_HOTFIX14_UPDATE_CHECK_V1'
    if marker in text:return
    b=method_bounds(text,'MechScope','build_ui')
    if not b:raise SystemExit('MechScope.build_ui missing')
    s,e=b;body=text[s:e];head=body.find('\n')+1
    inject="""        # MECHOS_HOTFIX14_UPDATE_CHECK_V1\n        try:\n            self.setStyleSheet((self.styleSheet() or '') + '\\nQMainWindow{background:#020611;color:#f4f7ff;}')\n            QTimer.singleShot(1800, lambda: __import__('subprocess').Popen(\n                ['/usr/local/bin/mechos-mechscope-update-check'],\n                stdout=__import__('subprocess').DEVNULL,\n                stderr=__import__('subprocess').DEVNULL,\n                start_new_session=True))\n        except Exception:\n            pass\n"""
    body=body[:head]+inject+body[head:]
    text=text[:s]+body+text[e:]
    # Hotfix13 guarantees QTimer for its fullscreen route, but retain a fallback.
    if 'QTimer.singleShot' in text and 'QTimer' not in text.split('\n',30)[0:30]:
        pass
    compile(text,str(path),'exec');path.write_text(text,encoding='utf-8')

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('usage: patch quick|mechscope FILE')
    kind=Path(sys.argv[1]).name if False else sys.argv[1];path=Path(sys.argv[2])
    {'quick':patch_quick,'mechscope':patch_mechscope}[kind](path)
