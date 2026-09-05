#!/usr/bin/env python3
"""Make the Hotfix 10 graphical Creator shell the final Creator.build owner."""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "MECHOS_HOTFIX10_CREATOR_VISUAL_OWNER_V1"


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS Creator Visual Owner v10] {message}")


def startup_anchor(text: str, class_pos: int) -> int:
    hits = []
    for token in ("\ndef main():", "\nif __name__", "\napp = QApplication", "\napp=QApplication"):
        pos = text.find(token, class_pos)
        if pos >= 0:
            hits.append(pos)
    if not hits:
        fail("startup anchor not found")
    return min(hits)


OVERRIDE = r'''
# MECHOS_HOTFIX10_CREATOR_VISUAL_OWNER_V1
def _mechos_surface_v10_module(filename, module_name):
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
        raise RuntimeError(f'Unable to load MechOS Creator visual source: {source}')
    module = _ilu.module_from_spec(spec)
    _sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _mechos_surface_v10_creator_build(self):
    from PyQt6.QtCore import QTimer as _QTimer
    shell = _mechos_surface_v10_module('creator_visual_shell_v10.py', 'mechos_creator_visual_shell_v10')
    ui = shell.CreatorVisualShellV10(self, self)
    self.setCentralWidget(ui)
    self._mechos_source_ui = ui
    self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
    self.setWindowState(Qt.WindowState.WindowFullScreen)
    _QTimer.singleShot(0, self.showFullScreen)
    _QTimer.singleShot(250, self.showFullScreen)
Creator.build = _mechos_surface_v10_creator_build
'''


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: mechos-creator-visual-owner-v10-patch.py <creator-owner.py>")
    path = Path(sys.argv[1])
    if not path.is_file():
        fail(f"owner missing: {path}")
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        return 0
    class_pos = text.find("class Creator(")
    if class_pos < 0:
        fail("class Creator not found")
    anchor = startup_anchor(text, class_pos)
    patched = text[:anchor] + "\n" + OVERRIDE.rstrip() + "\n" + text[anchor:]
    compile(patched, str(path), "exec")
    path.write_text(patched, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
