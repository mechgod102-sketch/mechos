#!/usr/bin/env python3
# MECHOS_HOTFIX15_RUNTIME_PATCH
from pathlib import Path
import sys


def class_bounds(text, cls):
    cp = text.find('class ' + cls + '(')
    if cp < 0:
        return None
    nxt = text.find('\nclass ', cp + 1)
    if nxt < 0:
        candidates = [p for p in (text.find('\ndef main(', cp), text.find('\nif __name__', cp)) if p >= 0]
        nxt = min(candidates) if candidates else len(text)
    return cp, nxt


def method_bounds(text, cls, name):
    cb = class_bounds(text, cls)
    if not cb:
        return None
    cp, ce = cb
    s = text.find('    def ' + name + '(', cp, ce)
    if s < 0:
        return None
    e = text.find('\n    def ', s + 8, ce)
    if e < 0:
        e = ce
    return s, e


def replace_method(text, cls, name, method):
    b = method_bounds(text, cls, name)
    if not b:
        raise SystemExit(f'{cls}.{name} missing')
    s, e = b
    return text[:s] + method.rstrip() + '\n' + text[e:]


def inject_method(text, cls, marker, method):
    if marker in text:
        return text
    cb = class_bounds(text, cls)
    if not cb:
        raise SystemExit(f'class {cls} missing')
    _, ce = cb
    return text[:ce] + '\n' + method.rstrip() + '\n' + text[ce:]


def patch_store(path: Path):
    if not path.is_file() and path.with_name(path.name + '.real').is_file():
        path = path.with_name(path.name + '.real')
    if not path.is_file():
        raise SystemExit(f'MechScope missing: {path}')

    text = path.read_text(encoding='utf-8')
    marker = 'MECHOS_HOTFIX15_NATIVE_UNIFIED_STORE'
    if marker in text:
        compile(text, str(path), 'exec')
        return

    helper = r'''    # MECHOS_HOTFIX15_NATIVE_UNIFIED_STORE
    def _mechos_open_native_store_v15(self, search=False):
        import shutil as _store_shutil
        import subprocess as _store_subprocess
        name, _desc, _url, _launcher = self.STORES[self.selected_store]
        q = self.query()

        if name == 'Steam':
            if not _store_shutil.which('steam'):
                QMessageBox.warning(self, 'Steam not installed', 'Steam is not installed. Install it from MechOS first, then reopen Unified Store.')
                return False
            # Keep browsing inside the Steam client instead of handing the URL
            # to the desktop web browser. Search uses Steam's own openurl route.
            if search and q:
                target = 'steam://openurl/https://store.steampowered.com/search/?term=' + q
            else:
                target = 'steam://store/'
            spawn(['steam', target])
            return True

        # Epic, GOG and Amazon entries are handled by the installed Heroic
        # launcher. Do not fall back to xdg-open: if Heroic is missing, tell the
        # user inside MechOS so Unified Store never unexpectedly opens a browser.
        if not _store_shutil.which('flatpak'):
            QMessageBox.warning(self, 'Heroic unavailable', 'Flatpak is unavailable, so Heroic cannot be opened from Unified Store.')
            return False
        try:
            probe = _store_subprocess.run(
                ['flatpak', 'info', 'com.heroicgameslauncher.hgl'],
                stdout=_store_subprocess.DEVNULL,
                stderr=_store_subprocess.DEVNULL,
                timeout=4,
                check=False,
            )
            if probe.returncode != 0:
                QMessageBox.warning(self, 'Heroic not installed', 'Heroic Games Launcher is not installed. Install it from MechOS, then reopen Unified Store.')
                return False
        except Exception:
            QMessageBox.warning(self, 'Heroic unavailable', 'MechOS could not verify the Heroic Games Launcher installation.')
            return False
        spawn(['flatpak', 'run', 'com.heroicgameslauncher.hgl'])
        return True
'''
    text = inject_method(text, 'UnifiedStore', marker, helper)

    text = replace_method(text, 'UnifiedStore', 'select_store', r'''    def select_store(self, index):
        self.selected_store = index
        name, desc, _url, _launcher = self.STORES[index]
        self.feature_name.setText(name)
        self.feature_desc.setText(desc)
        self.open_source.setText('Open ' + name + ' Store')
        for i, button in enumerate(self.source_buttons):
            button.setChecked(i == index)
''')
    text = replace_method(text, 'UnifiedStore', 'browse_selected', r'''    def browse_selected(self):
        self._mechos_open_native_store_v15(search=False)
''')
    text = replace_method(text, 'UnifiedStore', 'search_selected', r'''    def search_selected(self):
        self._mechos_open_native_store_v15(search=True)
''')
    text = replace_method(text, 'UnifiedStore', 'search_all', r'''    def search_all(self):
        # Open the two native provider clients used by MechOS. This deliberately
        # avoids xdg-open/browser tabs. Steam receives the typed query; Heroic
        # opens once for Epic/GOG/Amazon browsing.
        original = self.selected_store
        self.selected_store = 0
        self._mechos_open_native_store_v15(search=True)
        self.selected_store = 1
        self._mechos_open_native_store_v15(search=True)
        self.selected_store = original
''')
    text = replace_method(text, 'UnifiedStore', 'open_selected_launcher', r'''    def open_selected_launcher(self):
        self._mechos_open_native_store_v15(search=False)
''')

    text = text.replace(
        'Search official PC stores, open the authorized launcher, then return to MechScope. Purchases, accounts, licenses, downloads and anti-cheat remain with each official provider.',
        'Open official PC store clients without leaving MechOS for the desktop browser. Purchases, accounts, licenses, downloads and anti-cheat remain with each official provider.',
        1,
    )
    text = text.replace('Search Selected Store', 'Open Selected Store', 1)
    text = text.replace('Search All Stores', 'Open Store Launchers', 1)

    compile(text, str(path), 'exec')
    path.write_text(text, encoding='utf-8')


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: mechos-hotfix15-runtime-patch store FILE')
    kind = sys.argv[1]
    path = Path(sys.argv[2])
    if kind != 'store':
        raise SystemExit(f'unknown patch kind: {kind}')
    patch_store(path)


if __name__ == '__main__':
    main()
