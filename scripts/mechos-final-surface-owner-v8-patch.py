#!/usr/bin/env python3
"""Attach current source-owned MechOS shells to installed GUI owners.

Used by Hotfix 8+ and the absolute-last ISO stage. The injected assignment is
intentionally late in each Python owner so older generated UI methods cannot
win after this patch.
"""
from __future__ import annotations

import sys
from pathlib import Path


def fail(msg: str) -> None:
    raise SystemExit(f"[MechOS Surface Owner v8] {msg}")


def startup_anchor(text: str, class_pos: int) -> int:
    candidates = []
    for token in ("\ndef main():", "\nif __name__", "\napp = QApplication", "\napp=QApplication"):
        pos = text.find(token, class_pos)
        if pos >= 0:
            candidates.append(pos)
    if not candidates:
        fail("startup anchor not found")
    return min(candidates)


LOADER = r'''
def _mechos_surface_v8_module(filename, module_name):
    import importlib.util as _ilu
    import sys as _sys
    from pathlib import Path as _Path
    current = _sys.modules.get(module_name)
    if current is not None:
        return current
    source = _Path('/usr/local/share/mechos/ui') / filename
    parent = str(source.parent)
    if parent not in _sys.path:
        _sys.path.insert(0, parent)
    spec = _ilu.spec_from_file_location(module_name, source)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'Unable to load MechOS GUI source: {source}')
    module = _ilu.module_from_spec(spec)
    _sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module
'''

OVERRIDES = {
    "recovery": r'''
# MECHOS_HOTFIX8_SURFACE_OWNER_RECOVERY
'''+LOADER+r'''
def _mechos_surface_v8_recovery_build(self):
    shell = _mechos_surface_v8_module('recovery_shell.py', 'mechos_recovery_shell_v8')
    def _spawn(args):
        try: subprocess.Popen(args)
        except Exception: pass
    actions = {
      'rescan': self.rescan,
      'hardware': self.hardware,
      'repair': self.repair_boot,
      'rollback': self.rollback,
      'logs': self.load_logs,
      'keep-home': lambda: _spawn(['/usr/local/bin/mechos-preserve-home']),
      'disk': self.hardware,
      'mechscope': lambda: _spawn(['/usr/local/bin/mechos-mode-launch','gaming']) if __import__('pathlib').Path('/usr/local/bin/mechos-mode-launch').exists() else _spawn(['/usr/local/bin/mechos-return-to-mechscope']),
    }
    ui = shell.RecoveryShell(self, actions, self)
    self.setCentralWidget(ui); self._mechos_source_ui = ui
    self.root_combo = ui.root_combo; self.esp_combo = ui.esp_combo; self.output = ui.output
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
    self.setWindowState(Qt.WindowState.WindowFullScreen)
Recovery.build_ui = _mechos_surface_v8_recovery_build
''',
    "quick": r'''
# MECHOS_HOTFIX8_SURFACE_OWNER_QUICK
# MECHOS_VISUAL_SURFACES_V9_QUICK_ACTIONS_WIRING
'''+LOADER+r'''
def _mechos_surface_v8_quick_build(self):
    shell = _mechos_surface_v8_module('quick_actions_shell.py', 'mechos_quick_shell_v8')
    def _spawn(args):
        try: spawn(args)
        except Exception: pass
    actions = {
      'close': self.close,
      'performance': lambda: self.profile('performance'),
      'balanced': lambda: self.profile('balanced'),
      'battery': lambda: self.profile('power-saver'),
      'performance-center': lambda: _spawn(['/usr/local/bin/mechos-performance-center']),
      'wifi': self.toggle_wifi,
      'bluetooth': self.toggle_bt,
      'display': lambda: _spawn(['systemsettings','kcm_kscreen']),
      'system-settings': lambda: _spawn(['systemsettings']),
      'system-info': lambda: _spawn(['systemsettings','kcm_about-distro']),
      'brightness-down': lambda: self.brightness('5%-'),
      'brightness-up': lambda: self.brightness('+5%'),
      'audio-settings': lambda: _spawn(['systemsettings','kcm_pulseaudio']),
      'vol-down': lambda: self.wpctl('5%-'),
      'mute': self.mute,
      'vol-up': lambda: self.wpctl('5%+'),
      'rgb-picker': lambda: _spawn(['/usr/local/bin/mechos-rgb-keyboard','picker']),
      'rgb-restore': lambda: _spawn(['/usr/local/bin/mechos-rgb-keyboard','restore']),
      'rgb-advanced': lambda: _spawn(['/usr/local/bin/mechos-rgb-keyboard','advanced']),
      'go-live': lambda: _spawn(['/usr/local/bin/mechos-stream-control','start-stream']),
      'end-stream': lambda: _spawn(['/usr/local/bin/mechos-stream-control','stop-stream']),
      'record': lambda: _spawn(['/usr/local/bin/mechos-stream-control','toggle-record']),
      'stream-center': lambda: _spawn(['/usr/local/bin/mechos-stream-center']),
      'updates': lambda: _spawn(['/usr/local/bin/mechos-update-center']),
      'creator': lambda: _spawn(['/usr/local/bin/mechos-mode-launch','creator']),
      'recovery': lambda: _spawn(['/usr/local/bin/mechos-recovery-center']),
    }
    ui = shell.QuickActionsShell(self, actions, self)
    self.setCentralWidget(ui); self._mechos_source_ui = ui
QuickActions.build = _mechos_surface_v8_quick_build
''',
    "creator": r'''
# MECHOS_HOTFIX8_SURFACE_OWNER_CREATOR
'''+LOADER+r'''
def _mechos_surface_v8_creator_build(self):
    from PyQt6.QtCore import QTimer as _QTimer
    shell = _mechos_surface_v8_module('creator_shell.py', 'mechos_creator_shell_v8')
    ui = shell.CreatorShell(self, self)
    self.setCentralWidget(ui); self._mechos_source_ui = ui
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
    self.setWindowState(Qt.WindowState.WindowFullScreen)
    _QTimer.singleShot(0, self.showFullScreen)
    _QTimer.singleShot(250, self.showFullScreen)
Creator.build = _mechos_surface_v8_creator_build
''',
}

CLASSES = {"recovery": "Recovery", "quick": "QuickActions", "creator": "Creator"}


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[2] not in OVERRIDES:
        fail("usage: mechos-final-surface-owner-v8-patch.py <owner.py> {recovery|quick|creator}")
    path = Path(sys.argv[1]); kind = sys.argv[2]
    if not path.is_file():
        fail(f"owner missing: {path}")
    text = path.read_text(encoding="utf-8")
    marker = f"MECHOS_HOTFIX8_SURFACE_OWNER_{kind.upper()}"
    if marker in text:
        # Hotfix 9 needs to refresh the Quick Actions override even if the v8
        # marker already exists on an upgraded system. Replace the injected
        # block by stripping the old one only for quick actions.
        if kind != 'quick' or 'MECHOS_VISUAL_SURFACES_V9_QUICK_ACTIONS_WIRING' in text:
            return 0
        start = text.find('# MECHOS_HOTFIX8_SURFACE_OWNER_QUICK')
        end = text.find('\nQuickActions.build = _mechos_surface_v8_quick_build', start)
        if start >= 0 and end >= 0:
            end = text.find('\n', end + 1)
            if end < 0: end = len(text)
            text = text[:start] + text[end+1:]
    class_pos = text.find(f"class {CLASSES[kind]}(")
    if class_pos < 0:
        fail(f"class {CLASSES[kind]} not found in {path}")
    anchor = startup_anchor(text, class_pos)
    patched = text[:anchor] + "\n" + OVERRIDES[kind].rstrip() + "\n" + text[anchor:]
    compile(patched, str(path), "exec")
    path.write_text(patched, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
