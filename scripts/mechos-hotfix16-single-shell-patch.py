#!/usr/bin/env python3
# MECHOS_HOTFIX16_SINGLE_SHELL_PATCH
from pathlib import Path
import sys


def class_bounds(text, cls):
    start = text.find('class ' + cls + '(')
    if start < 0:
        return None
    end = text.find('\nclass ', start + 1)
    if end < 0:
        candidates = [p for p in (text.find('\ndef main(', start), text.find('\nif __name__', start)) if p >= 0]
        end = min(candidates) if candidates else len(text)
    return start, end


def method_bounds(text, cls, name):
    cb = class_bounds(text, cls)
    if not cb:
        return None
    cs, ce = cb
    start = text.find('    def ' + name + '(', cs, ce)
    if start < 0:
        return None
    end = text.find('\n    def ', start + 8, ce)
    if end < 0:
        end = ce
    return start, end


def replace_method(text, cls, name, replacement):
    bounds = method_bounds(text, cls, name)
    if not bounds:
        raise SystemExit(f'{cls}.{name} missing')
    start, end = bounds
    return text[:start] + replacement.rstrip() + '\n' + text[end:]


def inject_method(text, cls, method):
    cb = class_bounds(text, cls)
    if not cb:
        raise SystemExit(f'class {cls} missing')
    _, end = cb
    return text[:end] + '\n' + method.rstrip() + '\n' + text[end:]


def patch_mechscope(path: Path):
    if not path.is_file() and path.with_name(path.name + '.real').is_file():
        path = path.with_name(path.name + '.real')
    if not path.is_file():
        raise SystemExit(f'MechScope missing: {path}')

    text = path.read_text(encoding='utf-8')
    target_marker = '# MECHOS_HOTFIX16_SINGLE_WINDOW_SHELL'
    done_marker = 'def _mechos_shell_install_v16('
    if done_marker in text:
        if target_marker not in text:
            lines = text.splitlines(True)
            at = 1 if lines and lines[0].startswith('#!') else 0
            lines.insert(at, target_marker + '\n')
            text = ''.join(lines)
            compile(text, str(path), 'exec')
            path.write_text(text, encoding='utf-8')
        else:
            compile(text, str(path), 'exec')
        return

    helper = r'''    def _mechos_shell_install_v16(self):
        import os as _shell_os
        from pathlib import Path as _ShellPath
        from PyQt6.QtCore import QTimer as _ShellTimer
        from PyQt6.QtWidgets import QFrame as _ShellFrame, QHBoxLayout as _ShellHBox, QLabel as _ShellLabel, QPushButton as _ShellButton, QStackedWidget as _ShellStack, QVBoxLayout as _ShellVBox, QWidget as _ShellWidget
        if hasattr(self, '_mechos_shell_stack_v16'):
            return
        home = self.takeCentralWidget()
        if home is None:
            return
        wrapper = _ShellWidget(self)
        layout = _ShellVBox(wrapper)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        nav = _ShellFrame(wrapper)
        nav.setObjectName('mechosUnifiedNavV16')
        nav.setStyleSheet(
            'QFrame#mechosUnifiedNavV16{background:#050914;border-bottom:1px solid #24324d}'
            'QPushButton{background:#0b1424;border:1px solid #2b3e5d;border-radius:9px;padding:9px 13px;color:#eef4ff;font-weight:800}'
            'QPushButton:hover{border:1px solid #8b5cf6;background:#111d33}'
            'QPushButton:checked{background:#5f35d5;border:1px solid #c084fc;color:white}'
            'QLabel{color:#9fb0c8;font-weight:800}'
        )
        row = _ShellHBox(nav)
        row.setContentsMargins(14, 8, 14, 8)
        row.setSpacing(8)
        brand = _ShellLabel('MECHOS  •  UNIFIED SHELL')
        brand.setStyleSheet('color:#e9d5ff;font-size:14px;font-weight:900;letter-spacing:1px')
        row.addWidget(brand)
        row.addSpacing(10)
        self._mechos_shell_nav_buttons_v16 = {}
        for key, label in [('gaming','Gaming'),('store','Unified Store'),('creator','Creator Mode'),('performance','Performance'),('updates','Updates'),('recovery','Recovery')]:
            button = _ShellButton(label)
            button.setCheckable(True)
            button.clicked.connect(lambda _=False, k=key: self._mechos_shell_route_v16(k))
            row.addWidget(button)
            self._mechos_shell_nav_buttons_v16[key] = button
        row.addStretch(1)
        back = _ShellButton('Back')
        back.clicked.connect(self._mechos_shell_back_v16)
        row.addWidget(back)
        layout.addWidget(nav)
        stack = _ShellStack(wrapper)
        stack.setObjectName('mechosUnifiedStackV16')
        layout.addWidget(stack, 1)
        stack.addWidget(home)
        self._mechos_shell_stack_v16 = stack
        self._mechos_shell_pages_v16 = {'gaming': home}
        self._mechos_shell_current_v16 = 'gaming'
        self._mechos_shell_history_v16 = []
        self.setCentralWidget(wrapper)
        self._mechos_shell_nav_buttons_v16['gaming'].setChecked(True)
        runtime = _shell_os.environ.get('XDG_RUNTIME_DIR') or f'/tmp/mechos-{_shell_os.getuid()}'
        self._mechos_shell_route_file_v16 = _ShellPath(runtime) / 'mechos-shell-route-v16'
        try:
            self._mechos_shell_route_file_v16.parent.mkdir(parents=True, exist_ok=True)
        except Exception:
            pass
        self._mechos_shell_route_timer_v16 = _ShellTimer(self)
        self._mechos_shell_route_timer_v16.timeout.connect(self._mechos_shell_poll_route_v16)
        self._mechos_shell_route_timer_v16.start(180)

    def _mechos_shell_poll_route_v16(self):
        route_file = getattr(self, '_mechos_shell_route_file_v16', None)
        if route_file is None or not route_file.is_file():
            return
        try:
            value = route_file.read_text(encoding='utf-8', errors='ignore').strip().lower()
            route_file.unlink(missing_ok=True)
        except Exception:
            return
        aliases = {'mechscope':'gaming','update':'updates','performance-center':'performance','recovery-center':'recovery'}
        value = aliases.get(value, value)
        if value in {'gaming','store','creator','performance','updates','recovery'}:
            self._mechos_shell_route_v16(value)

    def _mechos_shell_embed_class_v16(self, cls, parent_arg=False):
        from PyQt6.QtCore import Qt as _ShellQt
        host = self
        cls.showFullScreen = lambda _page: None
        cls.showMaximized = lambda _page: None
        cls.setWindowState = lambda _page, *_args: None
        cls.close = lambda _page: host._mechos_shell_back_v16()
        if hasattr(cls, 'accept'):
            cls.accept = lambda _page: host._mechos_shell_back_v16()
        if hasattr(cls, 'reject'):
            cls.reject = lambda _page: host._mechos_shell_back_v16()
        page = cls(self) if parent_arg else cls()
        try:
            page.setWindowFlags(_ShellQt.WindowType.Widget)
        except Exception:
            pass
        page.setParent(self._mechos_shell_stack_v16)
        self._mechos_shell_rewire_page_v16(page)
        return page

    def _mechos_shell_load_external_v16(self, key):
        from importlib.machinery import SourceFileLoader as _ShellLoader
        from importlib.util import module_from_spec as _module_from_spec, spec_from_loader as _spec_from_loader
        from pathlib import Path as _ShellPath
        mapping = {
            'creator': (['/usr/local/bin/mechos-creator-mode.real','/usr/local/bin/mechos-creator-mode'], 'Creator'),
            'performance': (['/usr/local/bin/mechos-performance-center.real','/usr/local/bin/mechos-performance-center'], 'PerformanceCenter'),
            'updates': (['/usr/local/libexec/mechos-update-center-v8.py','/usr/local/libexec/mechos-update-center-v7.py','/usr/local/bin/mechos-update-center.real'], 'UpdateCenter'),
            'recovery': (['/usr/local/bin/mechos-recovery-center.real','/usr/local/bin/mechos-recovery-center'], 'Recovery'),
        }
        paths, class_name = mapping[key]
        source = next((_ShellPath(p) for p in paths if _ShellPath(p).is_file()), None)
        if source is None:
            raise RuntimeError(f'{key} surface is not installed')
        name = f'_mechos_shell_v16_{key}_{abs(hash(str(source)))}'
        loader = _ShellLoader(name, str(source))
        spec = _spec_from_loader(name, loader)
        module = _module_from_spec(spec)
        loader.exec_module(module)
        return self._mechos_shell_embed_class_v16(getattr(module, class_name), False)

    def _mechos_shell_rewire_page_v16(self, page):
        from PyQt6.QtWidgets import QPushButton as _ShellButton
        nav = {'performance center':'performance','performance':'performance','update center':'updates','updates':'updates','recovery center':'recovery','recovery':'recovery','creator mode':'creator','unified store':'store','return to mechscope':'gaming','back to mechscope':'gaming','gaming mode':'gaming','close':'gaming'}
        for button in page.findChildren(_ShellButton):
            label = (button.text() or '').split('\n', 1)[0].strip().lower()
            key = nav.get(label)
            if key is None:
                continue
            try:
                button.clicked.disconnect()
            except Exception:
                pass
            button.clicked.connect(lambda _=False, k=key: self._mechos_shell_route_v16(k))

    def _mechos_shell_route_v16(self, key):
        from PyQt6.QtWidgets import QMessageBox as _ShellMessageBox
        key = str(key).strip().lower()
        aliases = {'mechscope':'gaming','update':'updates','performance-center':'performance','recovery-center':'recovery'}
        key = aliases.get(key, key)
        if key not in {'gaming','store','creator','performance','updates','recovery'}:
            return False
        current = getattr(self, '_mechos_shell_current_v16', 'gaming')
        if key == current:
            return True
        page = self._mechos_shell_pages_v16.get(key)
        if page is None:
            try:
                if key == 'store':
                    cls = globals().get('UnifiedStore')
                    if cls is None:
                        raise RuntimeError('Unified Store class is unavailable')
                    page = self._mechos_shell_embed_class_v16(cls, True)
                else:
                    page = self._mechos_shell_load_external_v16(key)
                self._mechos_shell_pages_v16[key] = page
                self._mechos_shell_stack_v16.addWidget(page)
            except Exception as exc:
                _ShellMessageBox.warning(self, 'MechOS Unified Shell', f'Could not load {key.title()} inside the MechOS shell.\n\n{exc}')
                return False
        history = self._mechos_shell_history_v16
        if current != key and (not history or history[-1] != current):
            history.append(current)
            if len(history) > 16:
                del history[:-16]
        self._mechos_shell_current_v16 = key
        self._mechos_shell_stack_v16.setCurrentWidget(page)
        for name, button in self._mechos_shell_nav_buttons_v16.items():
            button.setChecked(name == key)
        try:
            page.show()
            page.setFocus()
        except Exception:
            pass
        return True

    def _mechos_shell_back_v16(self):
        history = getattr(self, '_mechos_shell_history_v16', [])
        target = history.pop() if history else 'gaming'
        page = self._mechos_shell_pages_v16.get(target)
        if page is None:
            return self._mechos_shell_route_v16(target)
        self._mechos_shell_current_v16 = target
        self._mechos_shell_stack_v16.setCurrentWidget(page)
        for name, button in self._mechos_shell_nav_buttons_v16.items():
            button.setChecked(name == target)
        return True

    def _mechos_shell_dispatch_v16(self, command):
        if not command:
            return False
        try:
            program = str(command[0])
        except Exception:
            return False
        routes = {'/usr/local/bin/mechos-performance-center':'performance','/usr/local/bin/mechos-update-center':'updates','/usr/local/bin/mechos-recovery-center':'recovery','/usr/local/bin/mechos-creator-mode':'creator'}
        route = routes.get(program)
        if route:
            return self._mechos_shell_route_v16(route)
        spawn(command)
        return True
'''
    text = inject_method(text, 'MechScope', helper)

    bounds = method_bounds(text, 'MechScope', 'build_ui')
    if not bounds:
        raise SystemExit('MechScope.build_ui missing')
    start, end = bounds
    body = text[start:end]
    if 'self._mechos_shell_install_v16()' not in body:
        body = body.rstrip() + '\n        self._mechos_shell_install_v16()\n'
        text = text[:start] + body + text[end:]

    if method_bounds(text, 'MechScope', 'open_store'):
        text = replace_method(text, 'MechScope', 'open_store', r'''    def open_store(self):
        return self._mechos_shell_route_v16('store')
''')
    if method_bounds(text, 'MechScope', 'switch_mode'):
        text = replace_method(text, 'MechScope', 'switch_mode', r'''    def switch_mode(self, mode):
        mode = str(mode).strip().lower()
        if mode in {'gaming', 'mechscope'}:
            return self._mechos_shell_route_v16('gaming')
        if mode == 'creator':
            return self._mechos_shell_route_v16('creator')
        if mode == 'desktop':
            spawn(['/usr/local/bin/mechos-mode-launch', 'desktop'])
            return True
        return False
''')

    text = text.replace("lambda:spawn(['/usr/local/bin/mechos-performance-center'])", "lambda:self._mechos_shell_route_v16('performance')")
    text = text.replace("lambda:spawn(['/usr/local/bin/mechos-update-center'])", "lambda:self._mechos_shell_route_v16('updates')")
    text = text.replace("lambda:spawn(['/usr/local/bin/mechos-recovery-center'])", "lambda:self._mechos_shell_route_v16('recovery')")
    text = text.replace("b.clicked.connect(lambda _=False,c=cmd:spawn(c))", "b.clicked.connect(lambda _=False,c=cmd:self._mechos_shell_dispatch_v16(c))")
    text = text.replace("button.clicked.connect(lambda _=False,c=cmd:spawn(c))", "button.clicked.connect(lambda _=False,c=cmd:self._mechos_shell_dispatch_v16(c))")

    if target_marker not in text:
        lines = text.splitlines(True)
        at = 1 if lines and lines[0].startswith('#!') else 0
        lines.insert(at, target_marker + '\n')
        text = ''.join(lines)

    compile(text, str(path), 'exec')
    path.write_text(text, encoding='utf-8')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: mechos-hotfix16-single-shell-patch FILE')
    patch_mechscope(Path(sys.argv[1]))


if __name__ == '__main__':
    main()
