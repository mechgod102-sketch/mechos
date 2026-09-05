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
    inject="""        # MECHOS_HOTFIX14_UPDATE_CHECK_V1\n        try:\n            from PyQt6.QtCore import QTimer as _MechUpdateTimer\n            import subprocess as _MechUpdateSubprocess\n            self.setStyleSheet((self.styleSheet() or '') + '\\nQMainWindow{background:#020611;color:#f4f7ff;}')\n            _MechUpdateTimer.singleShot(1800, lambda: _MechUpdateSubprocess.Popen(\n                ['/usr/local/bin/mechos-mechscope-update-check'],\n                stdout=_MechUpdateSubprocess.DEVNULL,\n                stderr=_MechUpdateSubprocess.DEVNULL,\n                start_new_session=True))\n        except Exception:\n            pass\n"""
    body=body[:head]+inject+body[head:]
    text=text[:s]+body+text[e:]
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
# Creator Mode is a graphical MechOS surface, not a request to expose Plasma.
# Start it first and verify that it remains alive before closing MechScope. If
# Creator fails, MechScope is left untouched and the user sees a real error.
if [ "$MODE" = creator ]; then
  CREATOR=/usr/local/bin/mechos-creator-mode
  CREATOR_LOG="$STATE_DIR/creator-mode-launch-v14.log"
  [ -x "$CREATOR" ] || { notify_error 'Creator Mode is missing.'; exit 1; }
  log 'Hotfix14 direct Creator transition requested'
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
  # Creator is now visibly established. Only now retire the MechScope process.
  pkill -u "$(id -u)" -f '/usr/local/bin/mechscope(\.real)?([[:space:]]|$)' >/dev/null 2>&1 || true
  log "Creator Mode healthy pid=$creator_pid; MechScope retired after handoff"
  exit 0
fi
'''
    text=text.replace(anchor,anchor+inject,1)
    path.write_text(text,encoding='utf-8')

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('usage: patch quick|mechscope|mode-launch FILE')
    kind=sys.argv[1];path=Path(sys.argv[2])
    {'quick':patch_quick,'mechscope':patch_mechscope,'mode-launch':patch_mode_launcher}[kind](path)
