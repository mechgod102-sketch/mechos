#!/usr/bin/env python3
# MECHOS_HOTFIX15_GAME_BROWSER_PATCH
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


def inject_method(text, cls, marker, method):
    if marker in text:
        return text
    cb = class_bounds(text, cls)
    if not cb:
        raise SystemExit(f'class {cls} missing')
    _, end = cb
    return text[:end] + '\n' + method.rstrip() + '\n' + text[end:]


def patch(path: Path):
    if not path.is_file() and path.with_name(path.name + '.real').is_file():
        path = path.with_name(path.name + '.real')
    if not path.is_file():
        raise SystemExit(f'MechScope missing: {path}')

    text = path.read_text(encoding='utf-8')
    marker = 'MECHOS_HOTFIX15_INTERNAL_GAME_BROWSER'
    if marker in text:
        compile(text, str(path), 'exec')
        return

    # The generated MechScope owner already imports most Qt widgets. These
    # imports are deliberately local/additive so the patch remains compatible
    # with the Hotfix 14 installed owner.
    qt_import = 'from PyQt6.QtWidgets import QDialog, QVBoxLayout, QHBoxLayout, QGridLayout, QScrollArea, QWidget, QLabel, QPushButton, QLineEdit, QFrame, QMessageBox, QApplication\n'
    if qt_import not in text:
        text = qt_import + text

    method = r'''    # MECHOS_HOTFIX15_INTERNAL_GAME_BROWSER
    def _mechos_show_game_browser_v15(self, provider='all'):
        import json as _game_json
        import subprocess as _game_subprocess

        query = self.search.text().strip()
        if not query:
            self.search.setFocus()
            QMessageBox.information(self, 'Game Browser', 'Type a game name first, then search.')
            return

        provider = (provider or 'all').lower()
        dialog = QDialog(self)
        dialog.setWindowTitle('MechOS Unified Store — Game Browser')
        dialog.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
        dialog.setWindowState(Qt.WindowState.WindowFullScreen)
        dialog.setStyleSheet(self.styleSheet())

        outer = QVBoxLayout(dialog)
        outer.setContentsMargins(28, 22, 28, 22)
        outer.setSpacing(12)

        header = QHBoxLayout()
        brand = QLabel('MECHOS  •  GAME BROWSER')
        brand.setStyleSheet('font-size:22px;font-weight:900;color:#d8b4fe')
        header.addWidget(brand)
        header.addStretch()
        scope = QLabel(('ALL STORES' if provider == 'all' else provider.upper()) + '  •  ' + query)
        scope.setStyleSheet('color:#9fb0c8;font-weight:800')
        header.addWidget(scope)
        back = QPushButton('Back to Unified Store')
        back.clicked.connect(dialog.accept)
        header.addWidget(back)
        outer.addLayout(header)

        search_row = QHBoxLayout()
        browser_search = QLineEdit(query)
        browser_search.setPlaceholderText('Search games…')
        search_row.addWidget(browser_search, 1)
        new_search = QPushButton('Search')
        search_row.addWidget(new_search)
        outer.addLayout(search_row)

        status = QLabel('Searching live game catalog…')
        status.setStyleSheet('color:#9fb0c8;padding:8px')
        outer.addWidget(status)
        QApplication.processEvents()

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        host = QWidget()
        grid = QGridLayout(host)
        grid.setHorizontalSpacing(12)
        grid.setVerticalSpacing(12)
        scroll.setWidget(host)
        outer.addWidget(scroll, 1)

        def run_search(term):
            term = term.strip()
            if not term:
                return
            self.search.setText(term)
            dialog.accept()
            self._mechos_show_game_browser_v15(provider)

        new_search.clicked.connect(lambda: run_search(browser_search.text()))
        browser_search.returnPressed.connect(lambda: run_search(browser_search.text()))

        try:
            result = _game_subprocess.run(
                ['/usr/local/libexec/mechos-game-catalog-v15', query, provider],
                text=True,
                capture_output=True,
                timeout=18,
                check=False,
            )
            data = _game_json.loads(result.stdout or '{}')
        except Exception as exc:
            data = {'results': [], 'error': str(exc)}

        rows = data.get('results') or []
        error = data.get('error')
        if error:
            status.setText('Game catalog is temporarily unavailable. Your installed store launchers still work.')
        elif not rows:
            status.setText('No matching games were found for this store filter.')
        else:
            status.setText(f'{len(rows)} game result(s) • results stay inside MechOS')

        def open_result(item):
            providers = [str(x).lower() for x in item.get('providers', [])]
            steam_id = str(item.get('steam_app_id') or '').strip()
            if steam_id and any('steam' in p for p in providers):
                old = self.selected_store
                self.selected_store = 0
                if self._mechos_bootstrap_provider_v15('steam'):
                    spawn(['steam', 'steam://store/' + steam_id])
                self.selected_store = old
                return

            # Non-Steam purchases/downloads remain owned by Heroic/provider
            # authentication. We only open the provider after the user selects
            # a result; game discovery itself never leaves Unified Store.
            old = self.selected_store
            if any('epic' in p for p in providers):
                self.selected_store = 1
            elif any('gog' in p for p in providers):
                self.selected_store = 2
            else:
                self.selected_store = max(1, old)
            self._mechos_open_native_store_v15(search=False)
            self.selected_store = old

        for i, item in enumerate(rows):
            card = QFrame()
            card.setObjectName('sourceCard')
            card.setMinimumHeight(150)
            layout = QVBoxLayout(card)
            title = QLabel(str(item.get('title') or 'Game'))
            title.setStyleSheet('font-size:18px;font-weight:900;color:white')
            title.setWordWrap(True)
            layout.addWidget(title)

            providers = ', '.join(item.get('providers') or ['Store'])
            try:
                price = float(item.get('best_price') or 0)
                price_text = 'Free / provider pricing' if price <= 0 else f'From ${price:.2f}'
            except Exception:
                price_text = 'Provider pricing'
            details = QLabel(price_text + '  •  ' + providers)
            details.setStyleSheet('color:#9fb0c8')
            details.setWordWrap(True)
            layout.addWidget(details)

            rating = str(item.get('rating') or '').strip()
            if rating:
                r = QLabel('Steam user rating: ' + rating + '%')
                r.setStyleSheet('color:#67e8f9')
                layout.addWidget(r)

            layout.addStretch()
            action = QPushButton('Open in Provider')
            action.setObjectName('primary')
            action.clicked.connect(lambda _=False, x=dict(item): open_result(x))
            layout.addWidget(action)
            grid.addWidget(card, i // 3, i % 3)

        dialog.exec()
'''
    text = inject_method(text, 'UnifiedStore', marker, method)

    text = replace_method(text, 'UnifiedStore', 'search_selected', r'''    def search_selected(self):
        name = self.STORES[self.selected_store][0].lower()
        if name.startswith('steam'):
            provider = 'steam'
        elif name.startswith('epic'):
            provider = 'epic'
        elif name.startswith('gog'):
            provider = 'gog'
        elif name.startswith('amazon'):
            provider = 'amazon'
        else:
            provider = 'all'
        self._mechos_show_game_browser_v15(provider)
''')
    text = replace_method(text, 'UnifiedStore', 'search_all', r'''    def search_all(self):
        self._mechos_show_game_browser_v15('all')
''')

    text = text.replace('Open Selected Store', 'Search Selected Store')
    text = text.replace('Open Store Launchers', 'Search All Stores')
    text = text.replace(
        'Open official PC store clients without leaving MechOS for the desktop browser. Missing store clients are installed automatically when selected. Purchases, accounts, licenses, downloads and anti-cheat remain with each official provider.',
        'Search games inside the MechOS Game Browser, compare store availability, then open the official provider only when you choose a game or store action. Missing provider clients are installed automatically. Purchases, accounts, licenses, downloads and anti-cheat remain with each official provider.'
    )

    compile(text, str(path), 'exec')
    path.write_text(text, encoding='utf-8')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: mechos-hotfix15-game-browser-patch FILE')
    patch(Path(sys.argv[1]))


if __name__ == '__main__':
    main()
