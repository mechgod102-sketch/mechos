#!/usr/bin/env python3
# MECHOS_UNIFIED_STORE_V35
"""MechOS source-owned Unified Store.

The Unified Store keeps game discovery, provider/launcher status, and launcher
installation controls inside MechOS. Official provider clients still own user
accounts, purchases, licenses, downloads and game files.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from PyQt6.QtCore import QProcess
from PyQt6.QtWidgets import (
    QApplication,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

CATALOG = "/usr/local/libexec/mechos-game-catalog-v15"
BOOTSTRAP = "/usr/local/libexec/mechos-launcher-bootstrap-v35"
STATE_DIR = Path.home() / ".local/state/mechos"
LOG = STATE_DIR / "unified-store-v35.log"
HEROIC_APP = "com.heroicgameslauncher.hgl"


def log(message: str) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        with LOG.open("a", encoding="utf-8") as fh:
            fh.write(f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] {message.rstrip()}\n")
    except Exception:
        pass


def detached(program: str, args: list[str] | None = None) -> bool:
    args = list(args or [])
    candidate = shutil.which(program) if "/" not in program else program
    if not candidate or not os.path.exists(candidate):
        log(f"launch target missing: {program}")
        return False
    result = QProcess.startDetached(candidate, args)
    started = result[0] if isinstance(result, tuple) else bool(result)
    log(f"launch program={candidate} args={args!r} started={started}")
    return bool(started)


def heroic_installed() -> bool:
    flatpak = shutil.which("flatpak")
    if not flatpak:
        return False
    try:
        probe = subprocess.run(
            [flatpak, "info", HEROIC_APP],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=4,
            check=False,
        )
        return probe.returncode == 0
    except Exception:
        return False


def launcher_installed(key: str) -> bool:
    if key == "steam":
        return shutil.which("steam") is not None
    if key == "heroic":
        return heroic_installed()
    if key == "lutris":
        return shutil.which("lutris") is not None
    return False


LAUNCHERS = {
    "steam": {
        "name": "Steam",
        "description": "Native Steam client for purchases, downloads and your Steam library.",
        "install": "System package",
    },
    "heroic": {
        "name": "Heroic Games Launcher",
        "description": "MechOS launcher for Epic Games, GOG.com and Amazon Games libraries.",
        "install": "User Flatpak",
    },
    "lutris": {
        "name": "Lutris",
        "description": "Library/import manager for supported Linux and Windows game sources.",
        "install": "System package",
    },
}

STORES = [
    {
        "name": "Steam",
        "key": "steam",
        "launcher": "steam",
        "description": "Steam storefront, purchases, downloads and library.",
    },
    {
        "name": "Epic Games",
        "key": "epic",
        "launcher": "heroic",
        "description": "Browse Epic results in MechOS and open your Epic library through Heroic.",
    },
    {
        "name": "GOG.com",
        "key": "gog",
        "launcher": "heroic",
        "description": "Browse GOG results in MechOS and manage your DRM-free library through Heroic.",
    },
    {
        "name": "Amazon Games",
        "key": "amazon",
        "launcher": "heroic",
        "description": "Browse supported Amazon results and open your Amazon library through Heroic.",
    },
]


class StoreCard(QFrame):
    def __init__(self, window: "UnifiedStore", store: dict):
        super().__init__()
        self.window = window
        self.store = store
        self.setObjectName("storeCard")
        self.setMinimumHeight(155)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 13, 14, 13)
        layout.setSpacing(7)

        name = QLabel(store["name"])
        name.setObjectName("cardTitle")
        layout.addWidget(name)
        desc = QLabel(store["description"])
        desc.setObjectName("muted")
        desc.setWordWrap(True)
        layout.addWidget(desc)
        layout.addStretch(1)

        self.status = QLabel()
        self.status.setObjectName("status")
        layout.addWidget(self.status)
        row = QHBoxLayout()
        browse = QPushButton("View in Unified Store")
        browse.clicked.connect(lambda: window.select_store(store["key"]))
        row.addWidget(browse)
        self.action = QPushButton()
        self.action.setObjectName("primary")
        self.action.clicked.connect(self.do_action)
        row.addWidget(self.action)
        layout.addLayout(row)
        self.refresh()

    def refresh(self) -> None:
        launcher = self.store["launcher"]
        ready = launcher_installed(launcher)
        launcher_name = LAUNCHERS[launcher]["name"]
        self.status.setText(("●  " if ready else "○  ") + launcher_name + (" ready" if ready else " not installed"))
        self.status.setProperty("ready", ready)
        self.status.style().unpolish(self.status)
        self.status.style().polish(self.status)
        self.action.setText("Launch" if ready else "Install Launcher")
        self.action.setEnabled(not self.window.installing.get(launcher, False))
        if self.window.installing.get(launcher, False):
            self.action.setText("Installing…")

    def do_action(self) -> None:
        launcher = self.store["launcher"]
        if launcher_installed(launcher):
            self.window.launch_launcher(launcher)
        else:
            self.window.install_launcher(launcher)


class LauncherCard(QFrame):
    def __init__(self, window: "UnifiedStore", key: str):
        super().__init__()
        self.window = window
        self.key = key
        info = LAUNCHERS[key]
        self.setObjectName("launcherCard")
        self.setMinimumHeight(150)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 13, 14, 13)
        layout.setSpacing(7)
        name = QLabel(info["name"])
        name.setObjectName("cardTitle")
        layout.addWidget(name)
        desc = QLabel(info["description"])
        desc.setObjectName("muted")
        desc.setWordWrap(True)
        layout.addWidget(desc)
        layout.addStretch(1)
        self.status = QLabel()
        self.status.setObjectName("status")
        layout.addWidget(self.status)
        self.button = QPushButton()
        self.button.setObjectName("primary")
        self.button.clicked.connect(self.do_action)
        layout.addWidget(self.button)
        self.refresh()

    def refresh(self) -> None:
        ready = launcher_installed(self.key)
        if self.window.installing.get(self.key, False):
            self.status.setText("Installing…")
            self.button.setText("Installing…")
            self.button.setEnabled(False)
            return
        install_type = LAUNCHERS[self.key]["install"]
        self.status.setText(("●  Installed" if ready else f"○  Not installed • {install_type}"))
        self.status.setProperty("ready", ready)
        self.status.style().unpolish(self.status)
        self.status.style().polish(self.status)
        self.button.setText("Launch" if ready else "Install")
        self.button.setEnabled(True)

    def do_action(self) -> None:
        if launcher_installed(self.key):
            self.window.launch_launcher(self.key)
        else:
            self.window.install_launcher(self.key)


class UnifiedStore(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS Unified Store")
        self.setMinimumSize(980, 640)
        self.selected_store = "all"
        self.installing: dict[str, bool] = {}
        self.processes: dict[str, QProcess] = {}
        self.store_cards: list[StoreCard] = []
        self.launcher_cards: list[LauncherCard] = []
        self.result_cards: list[QFrame] = []
        self._build()
        self.refresh_status()

    def _build(self) -> None:
        self.setStyleSheet(r"""
QMainWindow, QWidget#root { background:#050813; color:#eef4ff; }
QFrame#hero { background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #0b1222,stop:.55 #181039,stop:1 #07283a); border:1px solid #6d3cff; border-radius:18px; }
QFrame#storeCard, QFrame#launcherCard, QFrame#resultCard { background:#0b1424; border:1px solid #293d5d; border-radius:14px; }
QLabel#brand { color:#d8b4fe; font-size:20px; font-weight:900; }
QLabel#title { color:#ffffff; font-size:32px; font-weight:900; }
QLabel#section { color:#67e8f9; font-size:13px; font-weight:900; }
QLabel#cardTitle { color:#ffffff; font-size:18px; font-weight:900; }
QLabel#muted { color:#9fb0c8; }
QLabel#status { color:#aab8cc; font-weight:800; }
QLabel#status[ready="true"] { color:#31e981; }
QPushButton { background:#101b2e; border:1px solid #334766; border-radius:10px; padding:9px 12px; color:#f8fafc; font-weight:800; }
QPushButton:hover { border-color:#8b5cf6; background:#15213a; }
QPushButton:disabled { color:#718096; border-color:#27354a; }
QPushButton#primary { background:#6d35e8; border-color:#a78bfa; }
QLineEdit { background:#080f1d; border:1px solid #314766; border-radius:12px; padding:11px 14px; color:white; font-size:15px; }
QLineEdit:focus { border:2px solid #8b5cf6; }
QScrollArea { border:0; background:transparent; }
QScrollArea > QWidget > QWidget { background:transparent; }
""")
        root = QWidget()
        root.setObjectName("root")
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(18, 14, 18, 14)
        outer.setSpacing(12)

        header = QHBoxLayout()
        brand = QLabel("MECHOS  •  UNIFIED STORE")
        brand.setObjectName("brand")
        header.addWidget(brand)
        header.addStretch(1)
        self.summary = QLabel("Stores and launchers in one MechOS page")
        self.summary.setObjectName("muted")
        header.addWidget(self.summary)
        refresh = QPushButton("Refresh")
        refresh.clicked.connect(self.refresh_status)
        header.addWidget(refresh)
        close = QPushButton("Back to MechScope")
        close.clicked.connect(self.close)
        header.addWidget(close)
        outer.addLayout(header)

        hero = QFrame()
        hero.setObjectName("hero")
        hl = QVBoxLayout(hero)
        hl.setContentsMargins(22, 18, 22, 18)
        eye = QLabel("SEARCH INSIDE MECHOS • INSTALL LAUNCHERS HERE")
        eye.setObjectName("section")
        hl.addWidget(eye)
        title = QLabel("Every supported game store. One Unified Store.")
        title.setObjectName("title")
        title.setWordWrap(True)
        hl.addWidget(title)
        intro = QLabel(
            "Search supported providers without leaving this page. Missing launchers can be installed here, then launched directly from the same card. "
            "Official provider clients still handle sign-in, purchases, licenses and downloads."
        )
        intro.setObjectName("muted")
        intro.setWordWrap(True)
        hl.addWidget(intro)
        search_row = QHBoxLayout()
        self.search = QLineEdit()
        self.search.setPlaceholderText("Search games across Steam, Epic, GOG and Amazon…")
        self.search.returnPressed.connect(self.search_catalog)
        search_row.addWidget(self.search, 1)
        self.provider_button = QPushButton("All Stores")
        self.provider_button.clicked.connect(self.cycle_store)
        search_row.addWidget(self.provider_button)
        go = QPushButton("Search")
        go.setObjectName("primary")
        go.clicked.connect(self.search_catalog)
        search_row.addWidget(go)
        hl.addLayout(search_row)
        outer.addWidget(hero)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        content = QWidget()
        body = QVBoxLayout(content)
        body.setContentsMargins(1, 1, 1, 8)
        body.setSpacing(12)

        body.addWidget(self.section_label("STORES"))
        store_grid = QGridLayout()
        store_grid.setHorizontalSpacing(10)
        store_grid.setVerticalSpacing(10)
        for i, store in enumerate(STORES):
            card = StoreCard(self, store)
            self.store_cards.append(card)
            store_grid.addWidget(card, i // 2, i % 2)
        body.addLayout(store_grid)

        body.addWidget(self.section_label("LAUNCHERS"))
        launcher_grid = QGridLayout()
        launcher_grid.setHorizontalSpacing(10)
        launcher_grid.setVerticalSpacing(10)
        for i, key in enumerate(("steam", "heroic", "lutris")):
            card = LauncherCard(self, key)
            self.launcher_cards.append(card)
            launcher_grid.addWidget(card, 0, i)
        body.addLayout(launcher_grid)

        result_head = QHBoxLayout()
        self.results_title = self.section_label("GAME RESULTS")
        result_head.addWidget(self.results_title)
        result_head.addStretch(1)
        self.results_status = QLabel("Search above to browse the in-app catalog.")
        self.results_status.setObjectName("muted")
        result_head.addWidget(self.results_status)
        body.addLayout(result_head)

        self.results_host = QWidget()
        self.results_grid = QGridLayout(self.results_host)
        self.results_grid.setContentsMargins(0, 0, 0, 0)
        self.results_grid.setHorizontalSpacing(10)
        self.results_grid.setVerticalSpacing(10)
        body.addWidget(self.results_host)
        body.addStretch(1)
        scroll.setWidget(content)
        outer.addWidget(scroll, 1)

    def section_label(self, text: str) -> QLabel:
        label = QLabel(text)
        label.setObjectName("section")
        return label

    def refresh_status(self) -> None:
        for card in self.store_cards:
            card.refresh()
        for card in self.launcher_cards:
            card.refresh()
        installed = sum(1 for key in LAUNCHERS if launcher_installed(key))
        self.summary.setText(f"{installed}/{len(LAUNCHERS)} launchers ready • stores stay inside MechOS")

    def select_store(self, key: str) -> None:
        self.selected_store = key if key in {s["key"] for s in STORES} else "all"
        names = {s["key"]: s["name"] for s in STORES}
        self.provider_button.setText(names.get(self.selected_store, "All Stores"))
        self.search.setFocus()
        if self.search.text().strip():
            self.search_catalog()

    def cycle_store(self) -> None:
        order = ["all"] + [s["key"] for s in STORES]
        try:
            i = order.index(self.selected_store)
        except ValueError:
            i = 0
        self.select_store(order[(i + 1) % len(order)])

    def install_launcher(self, key: str) -> None:
        if key not in LAUNCHERS or self.installing.get(key):
            return
        if launcher_installed(key):
            self.launch_launcher(key)
            return
        if not os.path.isfile(BOOTSTRAP):
            QMessageBox.warning(self, "Unified Store", "The MechOS launcher installer is missing. Run Update Center and retry.")
            return
        self.installing[key] = True
        self.refresh_status()
        proc = QProcess(self)
        proc.setProgram(BOOTSTRAP)
        proc.setArguments([key])
        proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        proc.readyReadStandardOutput.connect(lambda k=key, p=proc: self._installer_output(k, p))
        proc.finished.connect(lambda code, status, k=key: self._installer_finished(k, int(code)))
        proc.errorOccurred.connect(lambda _error, k=key: log(f"installer process error for {k}"))
        self.processes[key] = proc
        log(f"starting fixed launcher installer id={key}")
        proc.start()

    def _installer_output(self, key: str, proc: QProcess) -> None:
        raw = bytes(proc.readAllStandardOutput()).decode("utf-8", errors="replace").strip()
        if raw:
            log(f"installer[{key}]: {raw}")

    def _installer_finished(self, key: str, code: int) -> None:
        self.installing[key] = False
        self.processes.pop(key, None)
        self.refresh_status()
        if code == 0 and launcher_installed(key):
            QMessageBox.information(self, "Unified Store", f"{LAUNCHERS[key]['name']} is installed and ready to launch.")
            return
        QMessageBox.warning(self, "Unified Store", f"{LAUNCHERS[key]['name']} installation did not complete (code {code}). Check {LOG} and retry.")

    def launch_launcher(self, key: str) -> bool:
        if key == "steam":
            if detached("steam", ["steam://store/"]):
                return True
        elif key == "heroic":
            if heroic_installed() and detached("flatpak", ["run", HEROIC_APP]):
                return True
        elif key == "lutris":
            if detached("lutris", []):
                return True
        else:
            return False
        name = LAUNCHERS.get(key, {"name": key})["name"]
        QMessageBox.warning(self, "Unified Store", f"{name} could not be launched.")
        return False

    def _clear_results(self) -> None:
        while self.results_grid.count():
            item = self.results_grid.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.deleteLater()
        self.result_cards.clear()

    def search_catalog(self) -> None:
        query = self.search.text().strip()
        if not query:
            self.search.setFocus()
            return
        if not os.path.isfile(CATALOG):
            QMessageBox.warning(self, "Unified Store", "The MechOS game catalog backend is missing. Run Update Center and retry.")
            return
        self.results_status.setText("Searching inside MechOS…")
        QApplication.processEvents()
        try:
            result = subprocess.run(
                [CATALOG, query, self.selected_store],
                text=True,
                capture_output=True,
                timeout=20,
                check=False,
            )
            payload = json.loads(result.stdout or "{}")
            rows = list(payload.get("results") or [])
            error = payload.get("error")
        except Exception as exc:
            rows, error = [], str(exc)
        self.render_results(rows, error)

    def render_results(self, rows: list[dict], error: str | None = None) -> None:
        self._clear_results()
        if error:
            self.results_status.setText("Catalog unavailable: " + str(error))
            self._empty_result("The in-app catalog could not be reached. No browser was opened.")
            return
        if not rows:
            self.results_status.setText("No matching games found for this store filter.")
            self._empty_result("Try All Stores or a different title.")
            return
        self.results_status.setText(f"{len(rows)} result(s) • displayed inside Unified Store")
        for i, item in enumerate(rows):
            card = self.result_card(dict(item))
            self.result_cards.append(card)
            self.results_grid.addWidget(card, i // 3, i % 3)

    def _empty_result(self, message: str) -> None:
        card = QFrame()
        card.setObjectName("resultCard")
        layout = QVBoxLayout(card)
        title = QLabel("Nothing to show yet")
        title.setObjectName("cardTitle")
        layout.addWidget(title)
        text = QLabel(message)
        text.setObjectName("muted")
        text.setWordWrap(True)
        layout.addWidget(text)
        self.results_grid.addWidget(card, 0, 0)

    def result_card(self, item: dict) -> QFrame:
        card = QFrame()
        card.setObjectName("resultCard")
        card.setMinimumHeight(175)
        layout = QVBoxLayout(card)
        title = QLabel(str(item.get("title") or "Game"))
        title.setObjectName("cardTitle")
        title.setWordWrap(True)
        layout.addWidget(title)
        providers = ", ".join(str(x) for x in (item.get("providers") or ["Provider"]))
        provider = QLabel(providers)
        provider.setObjectName("muted")
        provider.setWordWrap(True)
        layout.addWidget(provider)
        try:
            price = float(item.get("best_price") or 0)
            price_text = "Provider pricing" if price <= 0 else f"From ${price:.2f}"
        except Exception:
            price_text = "Provider pricing"
        price_label = QLabel(price_text)
        price_label.setObjectName("section")
        layout.addWidget(price_label)
        layout.addStretch(1)
        action = QPushButton("Open in Installed Provider")
        action.setObjectName("primary")
        action.clicked.connect(lambda _=False, value=item: self.open_result(value))
        layout.addWidget(action)
        return card

    def open_result(self, item: dict) -> None:
        providers = [str(value).casefold() for value in item.get("providers", [])]
        steam_id = str(item.get("steam_app_id") or "").strip()
        if steam_id and any("steam" in provider for provider in providers):
            if not launcher_installed("steam"):
                self.install_launcher("steam")
                return
            detached("steam", ["steam://store/" + steam_id])
            return
        if any(any(token in provider for token in ("epic", "gog", "amazon")) for provider in providers):
            if not launcher_installed("heroic"):
                self.install_launcher("heroic")
                return
            self.launch_launcher("heroic")
            return
        QMessageBox.information(self, "Unified Store", "That result is not mapped to an installed MechOS provider yet.")


def main() -> int:
    app = QApplication.instance() or QApplication(sys.argv)
    app.setApplicationName("MechOS Unified Store")
    window = UnifiedStore()
    window.showMaximized()
    log("Unified Store V35 started")
    rc = int(app.exec())
    log(f"Unified Store V35 exited rc={rc}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
