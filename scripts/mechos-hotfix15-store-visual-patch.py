#!/usr/bin/env python3
# MECHOS_HOTFIX15_UNIFIED_STORE_VISUAL
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
    b = method_bounds(text, cls, name)
    if not b:
        raise SystemExit(f'{cls}.{name} missing')
    s, e = b
    return text[:s] + replacement.rstrip() + '\n' + text[e:]


def patch(path: Path):
    if not path.is_file() and path.with_name(path.name + '.real').is_file():
        path = path.with_name(path.name + '.real')
    if not path.is_file():
        raise SystemExit(f'MechScope missing: {path}')

    text = path.read_text(encoding='utf-8')
    marker = 'MECHOS_HOTFIX15_UNIFIED_STORE_VISUAL'
    if marker in text:
        compile(text, str(path), 'exec')
        return

    method = r'''    def build_reference_store(self):
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
            ('⌂  Home', lambda: self.search.setFocus()),
            ('🎮  Games', lambda: self.search.setFocus()),
            ('▦  My Library', self.refresh_library),
            ('⇩  Downloads', self.open_selected_launcher),
            ('🛠  Creator Mode', lambda: spawn(['mechos-mode-launch','creator'])),
        ]:
            b = QPushButton(label)
            if label.startswith('🎮'):
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
        info = QLabel('SEARCH → VIEW DETAILS → AUTO-INSTALL PROVIDER IF NEEDED → INSTALL / PLAY')
        info.setObjectName('storeMuted')
        info.setWordWrap(True)
        fl.addWidget(info)
        main.addWidget(footer_panel)
        body.addLayout(main, 1)
        outer.addLayout(body, 1)
        self.select_store(0)
'''

    text = replace_method(text, 'UnifiedStore', 'build_reference_store', method)
    compile(text, str(path), 'exec')
    path.write_text(text, encoding='utf-8')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: mechos-hotfix15-store-visual-patch FILE')
    patch(Path(sys.argv[1]))


if __name__ == '__main__':
    main()
