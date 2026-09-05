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
    def _mechos_bootstrap_provider_v15(self, provider):
        import subprocess as _store_subprocess
        helper = '/usr/local/libexec/mechos-provider-bootstrap-v15'
        try:
            result = _store_subprocess.run(
                [helper, provider],
                stdout=_store_subprocess.DEVNULL,
                stderr=_store_subprocess.DEVNULL,
                timeout=900,
                check=False,
            )
        except Exception as exc:
            QMessageBox.warning(self, 'Store setup failed', f'MechOS could not install the required {provider} provider.\n\n{exc}')
            return False
        if result.returncode != 0:
            QMessageBox.warning(
                self,
                'Store setup failed',
                f'MechOS could not install the required {provider} provider (code {result.returncode}).\n\nCheck ~/.local/state/mechos/store/provider-bootstrap-v15.log for details.'
            )
            return False
        return True

    def _mechos_open_native_store_v15(self, search=False):
        import shutil as _store_shutil
        import subprocess as _store_subprocess
        name, _desc, _url, _launcher = self.STORES[self.selected_store]
        q = self.query()

        if name == 'Steam':
            if not _store_shutil.which('steam'):
                if not self._mechos_bootstrap_provider_v15('steam'):
                    return False
            if not _store_shutil.which('steam'):
                QMessageBox.warning(self, 'Steam setup failed', 'Steam installation completed but the Steam executable is still unavailable.')
                return False
            if search and q:
                target = 'steam://openurl/https://store.steampowered.com/search/?term=' + q
            else:
                target = 'steam://store/'
            spawn(['steam', target])
            return True

        if not _store_shutil.which('flatpak'):
            QMessageBox.warning(self, 'Heroic setup failed', 'Flatpak is unavailable, so MechOS cannot install Heroic Games Launcher automatically.')
            return False

        def heroic_installed():
            try:
                probe = _store_subprocess.run(
                    ['flatpak', 'info', 'com.heroicgameslauncher.hgl'],
                    stdout=_store_subprocess.DEVNULL,
                    stderr=_store_subprocess.DEVNULL,
                    timeout=8,
                    check=False,
                )
                return probe.returncode == 0
            except Exception:
                return False

        if not heroic_installed():
            if not self._mechos_bootstrap_provider_v15('heroic'):
                return False
        if not heroic_installed():
            QMessageBox.warning(self, 'Heroic setup failed', 'Heroic installation completed but MechOS could not verify it.')
            return False

        spawn(['flatpak', 'run', 'com.heroicgameslauncher.hgl'])
        return True
'''
    text = inject_method(text, 'UnifiedStore', marker, helper)

    text = replace_method(text, 'UnifiedStore', 'select_store', r'''    def select_store(self, index):
        self.selected_store = index
        name, desc, _url, _launcher = self.STORES[index]
        if hasattr(self, 'feature_name'):
            self.feature_name.setText(name)
        if hasattr(self, 'feature_desc'):
            self.feature_desc.setText(desc)
        if hasattr(self, 'open_source'):
            self.open_source.setText('Open ' + name + ' Store')
        for i, button in enumerate(getattr(self, 'source_buttons', [])):
            button.setChecked(i == index)
''')
    text = replace_method(text, 'UnifiedStore', 'browse_selected', r'''    def browse_selected(self):
        self._mechos_open_native_store_v15(search=False)
''')
    text = replace_method(text, 'UnifiedStore', 'search_selected', r'''    def search_selected(self):
        self._mechos_open_native_store_v15(search=True)
''')
    text = replace_method(text, 'UnifiedStore', 'search_all', r'''    def search_all(self):
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

    visual = r"""    def build_reference_store(self):
        # MECHOS_HOTFIX15_UNIFIED_STORE_VISUAL
        self.setStyleSheet(r'''
QDialog { background:#050913; color:#f7f8ff; }
QFrame#storeSidebar { background:#070d18; border:1px solid #18243b; border-radius:16px; }
QFrame#storeHero { background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #0b1122,stop:.52 #171038,stop:1 #08243a); border:1px solid #6d3cff; border-radius:18px; }
QFrame#storePanel { background:#09111f; border:1px solid #223452; border-radius:15px; }
QFrame#sourceCard { background:#0d1627; border:1px solid #303f62; border-radius:14px; }
QFrame#gameCard { background:#0b1424; border:1px solid #283957; border-radius:14px; }
QLabel#storeTitle { color:white; font-size:34px; font-weight:900; }
QLabel#storeEyebrow { color:#c084fc; font-size:13px; font-weight:900; }
QLabel#storeSection { color:#67e8f9; font-size:13px; font-weight:900; }
QLabel#storeMuted { color:#9fb0c8; }
QPushButton { background:#101b2e; border:1px solid #334766; border-radius:10px; padding:10px 13px; font-weight:800; color:#f8fafc; }
QPushButton:hover { border:1px solid #8b5cf6; background:#15213a; }
QPushButton:checked, QPushButton#primary { background:#6d35e8; border:1px solid #a78bfa; }
QLineEdit { background:#080f1d; border:1px solid #314766; border-radius:12px; padding:12px 15px; font-size:15px; color:white; }
QLineEdit:focus { border:2px solid #8b5cf6; }
''')
        outer = QVBoxLayout(self)
        outer.setContentsMargins(18, 16, 18, 16)
        outer.setSpacing(12)

        top = QHBoxLayout()
        brand = QLabel('MECHOS')
        brand.setStyleSheet('font-size:22px;font-weight:900;color:#e9d5ff')
        top.addWidget(brand)
        top.addSpacing(20)
        self.search = QLineEdit()
        self.search.setPlaceholderText('Search for games across all stores…')
        self.search.returnPressed.connect(self.search_all)
        top.addWidget(self.search, 1)
        search_all = QPushButton('Search All Stores')
        search_all.setObjectName('primary')
        search_all.clicked.connect(self.search_all)
        top.addWidget(search_all)
        back = QPushButton('Back to MechScope')
        back.clicked.connect(self.accept)
        top.addWidget(back)
        outer.addLayout(top)

        body = QHBoxLayout()
        body.setSpacing(12)
        sidebar = QFrame()
        sidebar.setObjectName('storeSidebar')
        sidebar.setFixedWidth(185)
        sl = QVBoxLayout(sidebar)
        sl.setContentsMargins(12, 14, 12, 14)
        nav_title = QLabel('UNIFIED STORE')
        nav_title.setObjectName('storeEyebrow')
        sl.addWidget(nav_title)
        for label, action in [
            ('Home', lambda: self.search.setFocus()),
            ('Games', lambda: self.search.setFocus()),
            ('My Library', self.refresh_library),
            ('Downloads', self.open_selected_launcher),
            ('Creator Mode', lambda: spawn(['mechos-mode-launch','creator'])),
        ]:
            b = QPushButton(label)
            if label == 'Games':
                b.setObjectName('primary')
            b.clicked.connect(action)
            sl.addWidget(b)
        sl.addStretch()
        status = QLabel('●  MECHOS ONLINE')
        status.setStyleSheet('color:#31e981;font-weight:900')
        sl.addWidget(status)
        body.addWidget(sidebar)

        main = QVBoxLayout()
        main.setSpacing(12)
        hero = QFrame()
        hero.setObjectName('storeHero')
        hl = QHBoxLayout(hero)
        hl.setContentsMargins(24, 20, 24, 20)
        copy = QVBoxLayout()
        eye = QLabel('ONE STORE • ALL YOUR GAMES')
        eye.setObjectName('storeEyebrow')
        copy.addWidget(eye)
        title = QLabel('PLAY ANYWHERE')
        title.setObjectName('storeTitle')
        copy.addWidget(title)
        sub = QLabel('Search games inside MechOS, compare available providers, and only open Steam or Heroic when you choose an install or provider action.')
        sub.setObjectName('storeMuted')
        sub.setWordWrap(True)
        copy.addWidget(sub)
        chips = QHBoxLayout()
        self.source_buttons = []
        for i, (name, _desc, _url, _launcher) in enumerate(self.STORES):
            b = QPushButton(name)
            b.setCheckable(True)
            b.clicked.connect(lambda _=False, x=i: self.select_store(x))
            chips.addWidget(b)
            self.source_buttons.append(b)
        copy.addLayout(chips)
        actions = QHBoxLayout()
        selected_search = QPushButton('Search Selected Store')
        selected_search.clicked.connect(self.search_selected)
        actions.addWidget(selected_search)
        self.open_source = QPushButton('Open Steam Store')
        self.open_source.setObjectName('primary')
        self.open_source.clicked.connect(self.browse_selected)
        actions.addWidget(self.open_source)
        copy.addLayout(actions)
        hl.addLayout(copy, 3)

        selected = QFrame()
        selected.setObjectName('sourceCard')
        sel = QVBoxLayout(selected)
        st = QLabel('SELECTED PROVIDER')
        st.setObjectName('storeSection')
        sel.addWidget(st)
        self.feature_name = QLabel('Steam')
        self.feature_name.setStyleSheet('font-size:24px;font-weight:900')
        sel.addWidget(self.feature_name)
        self.feature_desc = QLabel(self.STORES[0][1])
        self.feature_desc.setObjectName('storeMuted')
        self.feature_desc.setWordWrap(True)
        sel.addWidget(self.feature_desc)
        sel.addStretch()
        hl.addWidget(selected, 1)
        main.addWidget(hero)

        section_row = QHBoxLayout()
        heading = QLabel('FEATURED / INSTALLED GAMES')
        heading.setObjectName('storeSection')
        section_row.addWidget(heading)
        section_row.addStretch()
        view = QPushButton('Refresh Library')
        view.clicked.connect(self.refresh_library)
        section_row.addWidget(view)
        main.addLayout(section_row)

        games_panel = QFrame()
        games_panel.setObjectName('storePanel')
        gl = QHBoxLayout(games_panel)
        gl.setContentsMargins(12, 12, 12, 12)
        games = steam_games()[:6]
        if games:
            for game in games:
                card = QFrame()
                card.setObjectName('gameCard')
                card.setMinimumWidth(150)
                cl = QVBoxLayout(card)
                name = QLabel(game.get('name','Game'))
                name.setWordWrap(True)
                name.setStyleSheet('font-size:16px;font-weight:900')
                cl.addWidget(name)
                appid = str(game.get('appid','')).strip()
                meta = QLabel('Steam App ' + appid if appid else 'Installed')
                meta.setObjectName('storeMuted')
                cl.addWidget(meta)
                cl.addStretch()
                play = QPushButton('Play')
                play.setObjectName('primary')
                play.clicked.connect(lambda _=False, a=appid: spawn(['steam','steam://rungameid/' + a]) if a else None)
                cl.addWidget(play)
                gl.addWidget(card, 1)
        else:
            empty = QLabel('No installed games detected yet. Search above to browse the unified catalog.')
            empty.setObjectName('storeMuted')
            empty.setWordWrap(True)
            gl.addWidget(empty)
        main.addWidget(games_panel)

        footer_panel = QFrame()
        footer_panel.setObjectName('storePanel')
        fl = QHBoxLayout(footer_panel)
        info = QLabel('SEARCH  →  VIEW DETAILS  →  AUTO-INSTALL PROVIDER IF NEEDED  →  INSTALL / PLAY')
        info.setObjectName('storeMuted')
        info.setWordWrap(True)
        fl.addWidget(info)
        main.addWidget(footer_panel)
        body.addLayout(main, 1)
        outer.addLayout(body, 1)
        self.select_store(0)
"""
    if method_bounds(text, 'UnifiedStore', 'build_reference_store'):
        text = replace_method(text, 'UnifiedStore', 'build_reference_store', visual)

    text = text.replace(
        'Search official PC stores, open the authorized launcher, then return to MechScope. Purchases, accounts, licenses, downloads and anti-cheat remain with each official provider.',
        'Search games inside the MechOS Game Browser, compare providers, and open the official provider only when you choose a game or store action. Missing provider clients are installed automatically.',
        1,
    )

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
