#!/usr/bin/env python3
# MECHOS_HOTFIX14_RUNTIME_PATCH
from pathlib import Path
import sys

def class_bounds(text, cls):
    cp=text.find('class '+cls+'(')
    if cp<0:return None
    nxt=text.find('\nclass ',cp+1)
    if nxt<0:
        candidates=[p for p in (text.find('\ndef main(',cp),text.find('\nif __name__',cp)) if p>=0]
        nxt=min(candidates) if candidates else len(text)
    return cp,nxt

def method_bounds(text, cls, name):
    cb=class_bounds(text,cls)
    if not cb:return None
    cp,ce=cb
    s=text.find('    def '+name+'(',cp,ce)
    if s<0:return None
    e=text.find('\n    def ',s+8,ce)
    if e<0:e=ce
    return s,e

def inject_method(text, cls, marker, method):
    if marker in text:return text
    cb=class_bounds(text,cls)
    if not cb:raise SystemExit(f'class {cls} missing')
    _,ce=cb
    return text[:ce]+'\n'+method.rstrip()+'\n'+text[ce:]

def escape_close_method(marker):
    return f'''    # {marker}\n    def keyPressEvent(self, event):\n        from PyQt6.QtCore import Qt as _MechBackQt\n        if event.key() == _MechBackQt.Key.Key_Escape:\n            self.close()\n            return\n        super().keyPressEvent(event)\n'''

def patch_quick(path: Path):
    if not path.is_file(): raise SystemExit(f'Quick Actions missing: {path}')
    text=path.read_text(encoding='utf-8')
    marker='# MECHOS_HOTFIX14_QUICK_WINDOW_V1'
    if marker not in text:
        old="""        self.setStyleSheet(STYLE)\n        self.setFixedWidth(470)\n        self.build()\n\n        screen = QApplication.primaryScreen().availableGeometry()\n        self.setGeometry(screen.right() - self.width() + 1, screen.top(), self.width(), screen.height())\n"""
        new="""        # MECHOS_HOTFIX14_QUICK_WINDOW_V1\n        self.setStyleSheet(STYLE + '\\nQMainWindow{background:#020611;color:#f4f7ff;}')\n        screen = QApplication.primaryScreen().availableGeometry()\n        target=max(620,min(760,int(screen.width()*0.38)))\n        self.setFixedWidth(min(target,screen.width()))\n        self.build()\n        self.setGeometry(screen.right() - self.width() + 1, screen.top(), self.width(), screen.height())\n"""
        if old not in text: raise SystemExit('Quick Actions geometry anchor missing')
        text=text.replace(old,new,1)
    text=inject_method(text,'QuickActions','MECHOS_HOTFIX14_ESCAPE_BACK_QUICK',escape_close_method('MECHOS_HOTFIX14_ESCAPE_BACK_QUICK'))
    compile(text,str(path),'exec');path.write_text(text,encoding='utf-8')

def patch_mechscope(path: Path):
    if not path.is_file() and path.with_name(path.name+'.real').is_file():path=path.with_name(path.name+'.real')
    if not path.is_file():raise SystemExit(f'MechScope missing: {path}')
    text=path.read_text(encoding='utf-8')
    marker='# MECHOS_HOTFIX14_UPDATE_CHECK_V1'
    if marker not in text:
        b=method_bounds(text,'MechScope','build_ui')
        if not b:raise SystemExit('MechScope.build_ui missing')
        s,e=b;body=text[s:e];head=body.find('\n')+1
        inject="""        # MECHOS_HOTFIX14_UPDATE_CHECK_V1\n        try:\n            from PyQt6.QtCore import QTimer as _MechUpdateTimer\n            import subprocess as _MechUpdateSubprocess\n            self.setStyleSheet((self.styleSheet() or '') + '\\nQMainWindow{background:#020611;color:#f4f7ff;}')\n            _MechUpdateTimer.singleShot(1800, lambda: _MechUpdateSubprocess.Popen(\n                ['/usr/local/bin/mechos-mechscope-update-check'],\n                stdout=_MechUpdateSubprocess.DEVNULL,\n                stderr=_MechUpdateSubprocess.DEVNULL,\n                start_new_session=True))\n        except Exception:\n            pass\n"""
        body=body[:head]+inject+body[head:]
        text=text[:s]+body+text[e:]
    # Unified Store is a child surface launched from MechScope. Escape closes
    # the Store process and reveals the still-running MechScope behind it.
    text=inject_method(text,'UnifiedStore','MECHOS_HOTFIX14_ESCAPE_BACK_STORE',escape_close_method('MECHOS_HOTFIX14_ESCAPE_BACK_STORE'))
    compile(text,str(path),'exec');path.write_text(text,encoding='utf-8')

def patch_creator(path: Path):
    if not path.is_file():raise SystemExit(f'Creator Mode missing: {path}')
    text=path.read_text(encoding='utf-8')
    marker='MECHOS_HOTFIX14_ESCAPE_BACK_CREATOR'
    if marker in text:return
    method=r'''    # MECHOS_HOTFIX14_ESCAPE_BACK_CREATOR
    def keyPressEvent(self, event):
        from PyQt6.QtCore import Qt as _MechBackQt
        if event.key() == _MechBackQt.Key.Key_Escape:
            try:
                if hasattr(self,'stack') and self.stack.currentIndex() != 0:
                    self.select(0)
                    return
            except Exception:
                pass
            self.close()
            return
        super().keyPressEvent(event)
'''
    text=inject_method(text,'Creator',marker,method)
    compile(text,str(path),'exec');path.write_text(text,encoding='utf-8')

def patch_generic_escape(path: Path, cls: str, marker: str):
    if not path.is_file():raise SystemExit(f'{cls} owner missing: {path}')
    text=path.read_text(encoding='utf-8')
    text=inject_method(text,cls,marker,escape_close_method(marker))
    compile(text,str(path),'exec');path.write_text(text,encoding='utf-8')

def patch_mode_launcher(path: Path):
    if not path.is_file():raise SystemExit(f'Mode launcher missing: {path}')
    text=path.read_text(encoding='utf-8')
    marker='# MECHOS_HOTFIX14_CREATOR_DIRECT_V1'
    if marker in text:return
    anchor="case \"$MODE\" in gaming|mechscope|creator|desktop) ;; *) echo 'Usage: mechos-mode-launch {gaming|mechscope|creator|desktop}' >&2; exit 2 ;; esac\n"
    if anchor not in text:raise SystemExit('Mode launcher validation anchor missing')
    inject=r'''
# MECHOS_HOTFIX14_CREATOR_DIRECT_V1
# Creator Mode is a foreground MechOS surface layered over MechScope. Launch
# and health-check Creator first, then leave MechScope alive underneath it so
# Escape can return to the previous MechScope page without exposing Plasma.
if [ "$MODE" = creator ]; then
  CREATOR=/usr/local/bin/mechos-creator-mode
  CREATOR_LOG="$STATE_DIR/creator-mode-launch-v14.log"
  [ -x "$CREATOR" ] || { notify_error 'Creator Mode is missing.'; exit 1; }
  if pgrep -u "$(id -u)" -f '/usr/local/bin/mechos-creator-mode([[:space:]]|$)' >/dev/null 2>&1; then
    log 'Creator Mode already running; leaving MechScope active behind it'
    exit 0
  fi
  log 'Hotfix14 layered Creator transition requested'
  nohup "$CREATOR" >>"$CREATOR_LOG" 2>&1 </dev/null &
  creator_pid=$!
  for i in $(seq 1 30); do
    sleep 0.1
    if ! kill -0 "$creator_pid" >/dev/null 2>&1; then
      wait "$creator_pid" >/dev/null 2>&1 || rc=$?
      notify_error "Creator Mode exited during startup (rc=${rc:-1})."
      exit 1
    fi
  done
  log "Creator Mode healthy pid=$creator_pid; MechScope preserved for Escape/back navigation"
  exit 0
fi
'''
    text=text.replace(anchor,anchor+inject,1)
    path.write_text(text,encoding='utf-8')

if __name__=='__main__':
    if len(sys.argv)<3:raise SystemExit('usage: patch KIND FILE [CLASS]')
    kind=sys.argv[1];path=Path(sys.argv[2])
    if kind=='quick':patch_quick(path)
    elif kind=='mechscope':patch_mechscope(path)
    elif kind=='mode-launch':patch_mode_launcher(path)
    elif kind=='creator':patch_creator(path)
    elif kind=='escape':
        if len(sys.argv)!=4:raise SystemExit('usage: patch escape FILE CLASS')
        cls=sys.argv[3];patch_generic_escape(path,cls,f'MECHOS_HOTFIX14_ESCAPE_BACK_{cls.upper()}')
    else:raise SystemExit(f'unknown patch kind: {kind}')
