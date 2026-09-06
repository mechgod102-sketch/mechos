#!/usr/bin/env python3
# MECHOS_HOTFIX21_UNIFIED_STORE_PATCH
from pathlib import Path
import sys


def class_bounds(text: str, name: str):
    start = text.find(f'class {name}(')
    if start < 0:
        return None
    end = text.find('\nclass ', start + 1)
    if end < 0:
        candidates = [p for p in (text.find('\ndef main(', start), text.find('\nif __name__', start)) if p >= 0]
        end = min(candidates) if candidates else len(text)
    return start, end


def patch(path: Path):
    if not path.is_file() and path.with_name(path.name + '.real').is_file():
        path = path.with_name(path.name + '.real')
    if not path.is_file():
        raise SystemExit(f'MechScope implementation missing: {path}')

    text = path.read_text(encoding='utf-8')
    marker = 'MECHOS_HOTFIX21_UNIFIED_STORE_NATIVE_PAGE'
    if marker in text:
        compile(text, str(path), 'exec')
        return

    qt_import = (
        'from PyQt6.QtCore import Qt\n'
        'from PyQt6.QtWidgets import QDialog, QVBoxLayout, QHBoxLayout, QGridLayout, '
        'QScrollArea, QWidget, QLabel, QPushButton, QLineEdit, QFrame, QMessageBox, QApplication\n'
    )
    if 'from PyQt6.QtWidgets import QDialog, QVBoxLayout, QHBoxLayout, QGridLayout, QScrollArea' not in text:
        insert = 0
        lines = text.splitlines(True)
        if lines and lines[0].startswith('#!'):
            insert = 1
        lines.insert(insert, qt_import)
        text = ''.join(lines)

    bounds = class_bounds(text, 'UnifiedStore')
    if not bounds:
        raise SystemExit('UnifiedStore class not found')
    start, end = bounds

    replacement = r'''class UnifiedStore(QDialog):
    # MECHOS_HOTFIX21_UNIFIED_STORE_NATIVE_PAGE
    STORES = [
        ('All Stores', 'Search the MechOS catalog across supported providers.', 'all'),
        ('Steam', 'Native Steam client for purchases, downloads and play.', 'steam'),
        ('Epic Games', 'Epic library and installs are managed through Heroic.', 'epic'),
        ('GOG.com', 'GOG library and installs are managed through Heroic.', 'gog'),
        ('Amazon Games', 'Amazon game availability is surfaced in the catalog when available.', 'amazon'),
    ]

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle('MechOS Unified Store')
        self.selected_store = 0
        self.games = steam_games()
        self.result_widgets = []
        self.build_hotfix21_store()

    def panel(self, object_name='storePanel'):
        frame = QFrame()
        frame.setObjectName(object_name)
        return frame

    def muted(self, text):
        label = QLabel(text)
        label.setObjectName('storeMuted')
        label.setWordWrap(True)
        return label

    def section(self, text):
        label = QLabel(text)
        label.setObjectName('storeSection')
        return label

    def build_hotfix21_store(self):
        self.setStyleSheet(r'''
QDialog { background:#050813; color:#f8fafc; }
QFrame#storeSidebar { background:#070d18; border:1px solid #1f2d47; border-radius:16px; }
QFrame#storeHero { background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #0b1222,stop:.55 #181039,stop:1 #07283a); border:1px solid #6d3cff; border-radius:18px; }
QFrame#storePanel { background:#09111f; border:1px solid #223452; border-radius:15px; }
QFrame#gameCard { background:#0c1627; border:1px solid #2d4162; border-radius:14px; }
QLabel#storeTitle { color:white; font-size:34px; font-weight:900; }
QLabel#storeEyebrow { color:#c084fc; font-size:13px; font-weight:900; }
QLabel#storeSection { color:#67e8f9; font-size:13px; font-weight:900; }
QLabel#storeMuted { color:#9fb0c8; }
QPushButton { background:#101b2e; border:1px solid #334766; border-radius:10px; padding:10px 13px; font-weight:800; color:#f8fafc; }
QPushButton:hover { border:1px solid #8b5cf6; background:#15213a; }
QPushButton:checked, QPushButton#primary { background:#6d35e8; border:1px solid #a78bfa; }
QLineEdit { background:#080f1d; border:1px solid #314766; border-radius:12px; padding:12px 15px; font-size:15px; color:white; }
QLineEdit:focus { border:2px solid #8b5cf6; }
QScrollArea { border:0; background:transparent; }
QScrollArea > QWidget > QWidget { background:transparent; }
''')
        outer = QVBoxLayout(self)
        outer.setContentsMargins(18, 14, 18, 14)
        outer.setSpacing(12)

        top = QHBoxLayout()
        brand = QLabel('MECHOS  •  UNIFIED STORE')
        brand.setStyleSheet('font-size:21px;font-weight:900;color:#e9d5ff')
        top.addWidget(brand)
        top.addSpacing(18)
        self.search = QLineEdit()
        self.search.setPlaceholderText('Search games inside MechOS…')
        self.search.returnPressed.connect(self.search_selected)
        top.addWidget(self.search, 1)
        search_button = QPushButton('Search')
        search_button.setObjectName('primary')
        search_button.clicked.connect(self.search_selected)
        top.addWidget(search_button)
        back = QPushButton('Back')
        back.clicked.connect(self.accept)
        top.addWidget(back)
        outer.addLayout(top)

        body = QHBoxLayout()
        body.setSpacing(12)

        sidebar = self.panel('storeSidebar')
        sidebar.setFixedWidth(205)
        side = QVBoxLayout(sidebar)
        side.setContentsMargins(12, 14, 12, 14)
        side.addWidget(self.section('BROWSE'))
        self.source_buttons = []
        for i, (name, _desc, _key) in enumerate(self.STORES):
            button = QPushButton(name)
            button.setCheckable(True)
            button.clicked.connect(lambda _=False, index=i: self.select_store(index))
            self.source_buttons.append(button)
            side.addWidget(button)
        side.addSpacing(8)
        side.addWidget(self.section('LIBRARY'))
        library = QPushButton('My Library')
        library.clicked.connect(self.show_library)
        side.addWidget(library)
        downloads = QPushButton('Open Downloads')
        downloads.clicked.connect(self.open_selected_launcher)
        side.addWidget(downloads)
        compat = QPushButton('Compatibility Guide')
        compat.clicked.connect(self.show_compatibility_guide)
        side.addWidget(compat)
        side.addStretch(1)
        self.provider_state = QLabel('Provider: All Stores')
        self.provider_state.setObjectName('storeMuted')
        self.provider_state.setWordWrap(True)
        side.addWidget(self.provider_state)
        online = QLabel('●  GAME BROWSER READY')
        online.setStyleSheet('color:#31e981;font-weight:900')
        side.addWidget(online)
        body.addWidget(sidebar)

        main = QVBoxLayout()
        main.setSpacing(12)

        hero = self.panel('storeHero')
        hero_layout = QHBoxLayout(hero)
        hero_layout.setContentsMargins(24, 20, 24, 20)
        copy = QVBoxLayout()
        eyebrow = QLabel('SEARCH HERE • INSTALL THROUGH OFFICIAL PROVIDERS')
        eyebrow.setObjectName('storeEyebrow')
        copy.addWidget(eyebrow)
        title = QLabel('ONE STORE. NO BROWSER HANDOFF.')
        title.setObjectName('storeTitle')
        title.setWordWrap(True)
        copy.addWidget(title)
        copy.addWidget(self.muted(
            'Game discovery stays inside MechOS. When you choose a provider action, MechOS opens the native Steam or Heroic client and installs that provider automatically if it is missing.'
        ))
        actions = QHBoxLayout()
        all_games = QPushButton('Search All Stores')
        all_games.setObjectName('primary')
        all_games.clicked.connect(self.search_all)
        actions.addWidget(all_games)
        self.open_source = QPushButton('Open Provider')
        self.open_source.clicked.connect(self.browse_selected)
        actions.addWidget(self.open_source)
        refresh = QPushButton('Refresh Library')
        refresh.clicked.connect(self.show_library)
        actions.addWidget(refresh)
        actions.addStretch(1)
        copy.addLayout(actions)
        hero_layout.addLayout(copy, 1)
        main.addWidget(hero)

        header = QHBoxLayout()
        self.results_heading = self.section('INSTALLED GAMES')
        header.addWidget(self.results_heading)
        header.addStretch(1)
        self.results_status = QLabel('Your local Steam library is shown below.')
        self.results_status.setObjectName('storeMuted')
        header.addWidget(self.results_status)
        main.addLayout(header)

        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.results_host = QWidget()
        self.results_grid = QGridLayout(self.results_host)
        self.results_grid.setContentsMargins(2, 2, 2, 2)
        self.results_grid.setHorizontalSpacing(12)
        self.results_grid.setVerticalSpacing(12)
        self.scroll.setWidget(self.results_host)
        main.addWidget(self.scroll, 1)

        body.addLayout(main, 1)
        outer.addLayout(body, 1)
        self.select_store(0)
        self.show_library()

    def _clear_results(self):
        while self.results_grid.count():
            item = self.results_grid.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.deleteLater()
        self.result_widgets = []

    def _provider_key(self):
        try:
            return self.STORES[self.selected_store][2]
        except Exception:
            return 'all'

    def select_store(self, index):
        self.selected_store = max(0, min(int(index), len(self.STORES) - 1))
        name, desc, key = self.STORES[self.selected_store]
        for i, button in enumerate(self.source_buttons):
            button.setChecked(i == self.selected_store)
        self.provider_state.setText('Provider: ' + name + '\n' + desc)
        self.open_source.setText('Open ' + ('Provider' if key == 'all' else name))

    def _catalog_search(self, query, provider):
        import json as _json
        import subprocess as _subprocess
        try:
            result = _subprocess.run(
                ['/usr/local/libexec/mechos-game-catalog-v15', query, provider],
                text=True,
                capture_output=True,
                timeout=20,
                check=False,
            )
            payload = _json.loads(result.stdout or '{}')
            return payload.get('results') or [], payload.get('error')
        except Exception as exc:
            return [], str(exc)

    def search_selected(self):
        query = self.search.text().strip()
        if not query:
            self.search.setFocus()
            QMessageBox.information(self, 'Unified Store', 'Type a game name first.')
            return
        provider = self._provider_key()
        self.results_heading.setText('SEARCH RESULTS')
        self.results_status.setText('Searching the MechOS catalog…')
        QApplication.processEvents()
        rows, error = self._catalog_search(query, provider)
        self._render_catalog_results(rows, error, provider)

    def search_all(self):
        self.selected_store = 0
        self.select_store(0)
        self.search_selected()

    def _render_catalog_results(self, rows, error=None, provider='all'):
        self._clear_results()
        if error:
            self.results_status.setText('Catalog temporarily unavailable: ' + str(error))
            self._add_empty_card('The in-app catalog could not be reached. No external browser was opened.')
            return
        if not rows:
            self.results_status.setText('No matching games found for this provider filter.')
            self._add_empty_card('Try All Stores or a different game title.')
            return
        self.results_status.setText(f'{len(rows)} result(s) • discovery stays inside MechOS')
        for i, row in enumerate(rows):
            self.results_grid.addWidget(self._catalog_card(dict(row)), i // 3, i % 3)

    def _catalog_card(self, item):
        card = self.panel('gameCard')
        card.setMinimumHeight(180)
        layout = QVBoxLayout(card)
        title = QLabel(str(item.get('title') or 'Game'))
        title.setStyleSheet('font-size:17px;font-weight:900;color:white')
        title.setWordWrap(True)
        layout.addWidget(title)
        providers = ', '.join(item.get('providers') or ['Provider'])
        layout.addWidget(self.muted(providers))
        try:
            price = float(item.get('best_price') or 0)
            price_text = 'Provider pricing' if price <= 0 else f'From ${price:.2f}'
        except Exception:
            price_text = 'Provider pricing'
        price = QLabel(price_text)
        price.setStyleSheet('color:#67e8f9;font-weight:900')
        layout.addWidget(price)
        rating = str(item.get('rating') or '').strip()
        if rating:
            layout.addWidget(self.muted('Steam user rating: ' + rating + '%'))
        layout.addStretch(1)
        action = QPushButton('Open in Native Provider')
        action.setObjectName('primary')
        action.clicked.connect(lambda _=False, value=dict(item): self.open_result(value))
        layout.addWidget(action)
        self.result_widgets.append(card)
        return card

    def _add_empty_card(self, message):
        card = self.panel('gameCard')
        layout = QVBoxLayout(card)
        title = QLabel('Nothing to show yet')
        title.setStyleSheet('font-size:18px;font-weight:900')
        layout.addWidget(title)
        layout.addWidget(self.muted(message))
        layout.addStretch(1)
        self.results_grid.addWidget(card, 0, 0)

    def _bootstrap_provider(self, provider):
        import subprocess as _subprocess
        try:
            result = _subprocess.run(
                ['/usr/local/libexec/mechos-provider-bootstrap-v15', provider],
                timeout=900,
                check=False,
            )
        except Exception as exc:
            QMessageBox.warning(self, 'Provider setup failed', str(exc))
            return False
        if result.returncode != 0:
            QMessageBox.warning(self, 'Provider setup failed', f'MechOS could not prepare {provider} (code {result.returncode}).')
            return False
        return True

    def _open_steam(self, target='steam://store/'):
        import shutil as _shutil
        if not _shutil.which('steam') and not self._bootstrap_provider('steam'):
            return False
        if not _shutil.which('steam'):
            QMessageBox.warning(self, 'Steam unavailable', 'Steam is still unavailable after installation.')
            return False
        spawn(['steam', target])
        return True

    def _open_heroic(self):
        import shutil as _shutil
        import subprocess as _subprocess
        if not _shutil.which('flatpak'):
            QMessageBox.warning(self, 'Heroic unavailable', 'Flatpak is not installed.')
            return False
        probe = _subprocess.run(['flatpak', 'info', 'com.heroicgameslauncher.hgl'], stdout=_subprocess.DEVNULL, stderr=_subprocess.DEVNULL, check=False)
        if probe.returncode != 0 and not self._bootstrap_provider('heroic'):
            return False
        spawn(['flatpak', 'run', 'com.heroicgameslauncher.hgl'])
        return True

    def browse_selected(self):
        key = self._provider_key()
        if key == 'all':
            QMessageBox.information(self, 'Unified Store', 'Choose Steam, Epic Games, GOG.com or Amazon Games first. Search itself always stays inside MechOS.')
            return False
        if key == 'steam':
            return self._open_steam()
        return self._open_heroic()

    def open_selected_launcher(self):
        return self.browse_selected()

    def open_result(self, item):
        providers = [str(value).lower() for value in item.get('providers', [])]
        steam_id = str(item.get('steam_app_id') or '').strip()
        if steam_id and any('steam' in provider for provider in providers):
            return self._open_steam('steam://store/' + steam_id)
        return self._open_heroic()

    def show_library(self):
        self.games = steam_games()
        self._clear_results()
        self.results_heading.setText('INSTALLED GAMES')
        if not self.games:
            self.results_status.setText('No installed Steam games detected yet.')
            self._add_empty_card('Search above to find games without leaving MechOS.')
            return
        self.results_status.setText(f'{len(self.games)} installed Steam game(s) detected.')
        for i, game in enumerate(self.games[:24]):
            self.results_grid.addWidget(self._installed_card(dict(game)), i // 4, i % 4)

    def refresh_library(self):
        self.show_library()

    def _installed_card(self, game):
        card = self.panel('gameCard')
        card.setMinimumHeight(150)
        layout = QVBoxLayout(card)
        title = QLabel(str(game.get('name') or 'Game'))
        title.setWordWrap(True)
        title.setStyleSheet('font-size:16px;font-weight:900')
        layout.addWidget(title)
        appid = str(game.get('appid') or '').strip()
        layout.addWidget(self.muted('Steam App ' + appid if appid else 'Installed game'))
        layout.addStretch(1)
        play = QPushButton('Play')
        play.setObjectName('primary')
        play.clicked.connect(lambda _=False, value=appid: self.launch_game({'appid': value}))
        layout.addWidget(play)
        return card

    def launch_game(self, game):
        appid = str(game.get('appid') or '').strip()
        if appid:
            return self._open_steam('steam://rungameid/' + appid)
        return False

    def show_compatibility_guide(self):
        QMessageBox.information(
            self,
            'MechOS Compatibility Guide',
            'Verified — tested MechOS profile.\n\nPlayable — works with minor setup.\n\nNeeds Setup — compatibility profile or Proton configuration required.\n\nUnsupported — known blocker such as unsupported anti-cheat.\n\nUnknown — not tested yet.\n\nThe guide stays inside MechOS; it does not launch a web browser.'
        )
'''

    text = text[:start] + replacement + text[end:]
    compile(text, str(path), 'exec')

    section = text[class_bounds(text, 'UnifiedStore')[0]:class_bounds(text, 'UnifiedStore')[1]]
    if "spawn(['xdg-open'" in section or 'webbrowser.' in section:
        raise SystemExit('external browser handoff remains inside UnifiedStore')
    for required in (
        marker,
        'def build_hotfix21_store',
        'def _catalog_search',
        'mechos-game-catalog-v15',
        'mechos-provider-bootstrap-v15',
        'ONE STORE. NO BROWSER HANDOFF.',
    ):
        if required not in section:
            raise SystemExit(f'Hotfix 21 Unified Store marker missing: {required}')

    path.write_text(text, encoding='utf-8')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: mechos-hotfix21-unified-store-patch FILE')
    patch(Path(sys.argv[1]))


if __name__ == '__main__':
    main()
