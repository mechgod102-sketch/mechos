#!/usr/bin/env python3
"""Graphical Creator Mode visual layer for MechOS Hotfix 10.

Hotfix 9 unified the palette and geometry, but the Creator dashboard was still
mostly text buttons. This module keeps the live/functional Creator backend and
adds a real visual layer: generated vector badges, app/tool icons, project type
icons, a creator hero illustration, and graphical decoration across the
Creator stack. The graphics are generated locally with Qt, so they are always
available offline and never depend on third-party logo assets.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import creator_shell as _base
from PyQt6.QtCore import QRect, QSize, Qt
from PyQt6.QtGui import QColor, QFont, QIcon, QLinearGradient, QPainter, QPen, QPixmap
from PyQt6.QtWidgets import QLabel, QPushButton

# MECHOS_CREATOR_VISUALS_V10

ACCENTS = {
    "dashboard": ("#9b6cff", "#39dcff"),
    "projects": ("#7b78ff", "#45e7ff"),
    "engines": ("#ff6ac8", "#9d72ff"),
    "tools": ("#49dfff", "#7b8dff"),
    "assets": ("#48e0b4", "#48b8ff"),
    "clip": ("#ff6b9d", "#9f72ff"),
    "learn": ("#50ddff", "#4f8cff"),
    "community": ("#b777ff", "#5be4ff"),
    "settings": ("#8c78ff", "#5adfff"),
    "new-project": ("#a36dff", "#52e3ff"),
    "store": ("#ff72ca", "#7e79ff"),
    "performance": ("#55e2ff", "#8c6eff"),
    "system": ("#5ce1ff", "#4b8dff"),
    "blender": ("#ff9c4a", "#ff5d78"),
    "unityhub": ("#6ad8ff", "#8076ff"),
    "unreal": ("#d29cff", "#7d6cff"),
    "vscode": ("#49cfff", "#477dff"),
    "gitkraken": ("#59e0ca", "#7d79ff"),
    "krita": ("#ff69c7", "#8f72ff"),
    "obs": ("#9d8bff", "#5c75ff"),
    "godot": ("#55cfff", "#6d8bff"),
    "kdenlive": ("#52e2ff", "#7c70ff"),
    "audacity": ("#4ec8ff", "#ff6cab"),
    "vrchat": ("#62e5ff", "#a16fff"),
    "optimization": ("#4fe0ba", "#54b9ff"),
    "gaming": ("#a16dff", "#48dcff"),
    "desktop": ("#56d7ff", "#677cff"),
    "mechscope": ("#c26fff", "#45e1ff"),
    "project": ("#748bff", "#47ddff"),
}

MONOGRAM = {
    "dashboard": "◈",
    "projects": "▰",
    "engines": "⬡",
    "tools": "✦",
    "assets": "◆",
    "clip": "▶",
    "learn": "▤",
    "community": "●●",
    "settings": "⚙",
    "new-project": "+",
    "store": "◇",
    "performance": "↗",
    "system": "▦",
    "blender": "3D",
    "unityhub": "U",
    "unreal": "UE",
    "vscode": "<> ",
    "gitkraken": "⑂",
    "krita": "✎",
    "obs": "●",
    "godot": "G",
    "kdenlive": "▸",
    "audacity": "≋",
    "vrchat": "VR",
    "optimization": "⚡",
    "gaming": "G",
    "desktop": "▣",
    "mechscope": "M",
    "project": "P",
}

TITLE_KEYS = {
    "Dashboard": "dashboard",
    "Projects": "projects",
    "Engines": "engines",
    "Tools": "tools",
    "Assets": "assets",
    "MechClip AI": "clip",
    "Learn": "learn",
    "Community": "community",
    "Settings": "settings",
    "Creator Settings": "settings",
    "New Project": "new-project",
    "Open Project": "projects",
    "Project Manager": "projects",
    "Asset Browser": "assets",
    "Creator Store": "store",
    "Performance": "performance",
    "Open Performance Center": "performance",
    "System Monitor": "system",
    "System Settings": "settings",
    "Update Center": "system",
    "Quick Actions": "system",
    "Gaming Mode": "gaming",
    "Creator Mode": "new-project",
    "Desktop Mode": "desktop",
    "MechScope": "mechscope",
    "Blender": "blender",
    "Unity Hub": "unityhub",
    "Unreal Engine": "unreal",
    "VS Code": "vscode",
    "GitKraken": "gitkraken",
    "Krita": "krita",
    "OBS Studio": "obs",
    "Godot": "godot",
    "Kdenlive": "kdenlive",
    "Audacity": "audacity",
    "VRChat Creator": "vrchat",
    "Optimization": "optimization",
    "All 3D Tools": "blender",
}


def _key_for_title(title: str) -> str:
    title = " ".join((title or "").split())
    if title in TITLE_KEYS:
        return TITLE_KEYS[title]
    low = title.lower()
    for token, key in (
        ("blender", "blender"), ("unity", "unityhub"), ("unreal", "unreal"),
        ("visual studio", "vscode"), ("vs code", "vscode"), ("gitkraken", "gitkraken"),
        ("krita", "krita"), ("obs", "obs"), ("godot", "godot"),
        ("kdenlive", "kdenlive"), ("audacity", "audacity"), ("vrchat", "vrchat"),
        ("project", "projects"), ("store", "store"), ("setting", "settings"),
        ("performance", "performance"), ("asset", "assets"), ("engine", "engines"),
        ("tool", "tools"), ("mechscope", "mechscope"), ("desktop", "desktop"),
        ("gaming", "gaming"),
    ):
        if token in low:
            return key
    return "project"


def badge_pixmap(key: str, size: int = 64, installed: bool | None = None) -> QPixmap:
    key = key if key in ACCENTS else "project"
    a, b = ACCENTS[key]
    pix = QPixmap(size, size)
    pix.fill(Qt.GlobalColor.transparent)
    p = QPainter(pix)
    p.setRenderHint(QPainter.RenderHint.Antialiasing, True)

    r = pix.rect().adjusted(2, 2, -2, -2)
    grad = QLinearGradient(0, 0, size, size)
    grad.setColorAt(0.0, QColor(a))
    grad.setColorAt(1.0, QColor(b))
    p.setBrush(grad)
    p.setPen(QPen(QColor("#d9eeff"), max(1, size // 28)))
    p.drawRoundedRect(r, max(8, size // 5), max(8, size // 5))

    # Dark inner plate gives the badge the same layered-card look as MechOS.
    inner = r.adjusted(max(4, size // 10), max(4, size // 10), -max(4, size // 10), -max(4, size // 10))
    p.setBrush(QColor(5, 10, 24, 205))
    p.setPen(QPen(QColor(255, 255, 255, 70), 1))
    p.drawRoundedRect(inner, max(6, size // 7), max(6, size // 7))

    f = QFont("Sans Serif", max(8, int(size * 0.27)))
    f.setBold(True)
    p.setFont(f)
    p.setPen(QColor("#f5f8ff"))
    p.drawText(inner, Qt.AlignmentFlag.AlignCenter, MONOGRAM.get(key, "•"))

    if installed is not None:
        dot = max(6, size // 7)
        p.setBrush(QColor("#54f3b0") if installed else QColor("#61728d"))
        p.setPen(QPen(QColor("#07101d"), max(1, size // 32)))
        p.drawEllipse(size - dot - 4, size - dot - 4, dot, dot)
    p.end()
    return pix


def badge_icon(key: str, size: int = 64, installed: bool | None = None) -> QIcon:
    return QIcon(badge_pixmap(key, size, installed))


def hero_pixmap(width: int = 430, height: int = 225) -> QPixmap:
    pix = QPixmap(width, height)
    pix.fill(Qt.GlobalColor.transparent)
    p = QPainter(pix)
    p.setRenderHint(QPainter.RenderHint.Antialiasing, True)

    # Neon orbital creator emblem.
    cx, cy = int(width * 0.62), int(height * 0.48)
    glow = QLinearGradient(cx - 100, cy - 100, cx + 100, cy + 100)
    glow.setColorAt(0.0, QColor(157, 93, 255, 90))
    glow.setColorAt(1.0, QColor(61, 223, 255, 20))
    p.setBrush(glow)
    p.setPen(Qt.PenStyle.NoPen)
    p.drawEllipse(cx - 92, cy - 92, 184, 184)

    p.setBrush(QColor(4, 10, 24, 215))
    p.setPen(QPen(QColor("#71e7ff"), 3))
    p.drawRoundedRect(cx - 54, cy - 54, 108, 108, 22, 22)
    p.setPen(QPen(QColor("#c783ff"), 4))
    p.drawLine(cx - 27, cy + 21, cx + 31, cy - 31)
    p.drawLine(cx - 27, cy + 21, cx + 9, cy + 31)
    p.drawLine(cx + 31, cy - 31, cx + 20, cy + 8)

    p.setBrush(Qt.BrushStyle.NoBrush)
    p.setPen(QPen(QColor(111, 229, 255, 145), 2))
    p.drawEllipse(cx - 128, cy - 66, 256, 132)
    p.setPen(QPen(QColor(191, 111, 255, 125), 2))
    p.drawEllipse(cx - 83, cy - 106, 166, 212)

    p.setBrush(QColor("#67e4ff")); p.setPen(Qt.PenStyle.NoPen)
    for x, y, s in ((cx - 124, cy - 7, 9), (cx + 106, cy + 31, 7), (cx + 8, cy - 104, 8)):
        p.drawEllipse(x, y, s, s)

    # Left-side tool glyph cluster.
    for i, (key, x, y) in enumerate((("blender", 16, 34), ("engines", 82, 80), ("obs", 27, 133))):
        icon = badge_pixmap(key, 50)
        p.drawPixmap(x, y, icon)
        if i < 2:
            p.setPen(QPen(QColor(95, 210, 255, 90), 1))
            p.drawLine(x + 50, y + 25, cx - 65, cy)

    p.end()
    return pix


def decorate_button(button: QPushButton, key: str | None = None, size: int = 30, installed: bool | None = None) -> None:
    title_prop = button.property("mechosTitle")
    title = str(title_prop) if title_prop is not None else button.text().splitlines()[0]
    key = key or _key_for_title(title)
    button.setIcon(badge_icon(key, max(38, size * 2), installed))
    button.setIconSize(QSize(size, size))
    button.setProperty("mechosVisualV10", True)


class VisualCreatorHome(_base.LiveCreatorHome):
    """Hotfix 10 graphical replacement for the text-heavy Creator home."""

    def __init__(self, owner, parent=None):
        self._visual_v10_ready = False
        super().__init__(owner, parent)
        self._visual_v10_ready = True
        self._install_hero_art()
        self._decorate_existing_buttons()
        self.refresh_apps()
        self.refresh_projects()

    def _install_hero_art(self) -> None:
        art = self.reg(QLabel(), QRect(1155, 103, 380, 226))
        art.setPixmap(hero_pixmap(430, 225))
        art.setScaledContents(True)
        art.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)
        art.setToolTip("MechOS Creator visual workspace")
        art.lower()
        self._creator_hero_art = art

    def _decorate_existing_buttons(self) -> None:
        for button in self.findChildren(QPushButton):
            title_prop = button.property("mechosTitle")
            title = str(title_prop) if title_prop is not None else button.text().splitlines()[0]
            decorate_button(button, _key_for_title(title), 26 if button.height() < 55 else 30)

    def refresh_apps(self):
        super().refresh_apps()
        if not hasattr(self, "_app_buttons"):
            return
        for appid, pair in self._app_buttons.items():
            button = pair[0] if isinstance(pair, tuple) else pair
            if isinstance(button, QPushButton):
                decorate_button(button, appid if appid in ACCENTS else _key_for_title(button.text()), 30, _base._app_installed(appid))

    def refresh_projects(self):
        super().refresh_projects()
        if not hasattr(self, "project_buttons"):
            return
        for i, button in enumerate(self.project_buttons):
            if i < len(getattr(self, "_projects", [])):
                _, _, kind = self._projects[i]
                key = {"Unity": "unityhub", "Unreal": "unreal", "Godot": "godot", "Blender": "blender"}.get(kind, "project")
            else:
                key = "project"
            decorate_button(button, key, 24)

    def paint_background(self, painter: QPainter):
        super().paint_background(painter)
        # Thin graphical grid and circuit traces turn the dashboard into a
        # creator cockpit without masking real data or controls.
        s = self.scale_factor()
        hero = self.scale_rect(QRect(1110, 96, 430, 244))
        painter.save()
        painter.setClipRect(hero)
        painter.setPen(QPen(QColor(77, 190, 255, 32), max(1, int(s))))
        step = max(12, int(28 * s))
        for x in range(hero.left(), hero.right(), step):
            painter.drawLine(x, hero.top(), x, hero.bottom())
        for y in range(hero.top(), hero.bottom(), step):
            painter.drawLine(hero.left(), y, hero.right(), y)
        painter.restore()


class CreatorVisualShellV10(_base.CreatorShell):
    """Preserve all Creator pages/backends while replacing the dashboard visuals."""

    def __init__(self, owner, parent=None):
        super().__init__(owner, parent)
        old_home = self.home
        visual_home = VisualCreatorHome(owner)
        owner.stack.removeWidget(old_home)
        owner.stack.insertWidget(0, visual_home)
        old_home.deleteLater()
        self.home = visual_home
        self._decorate_other_pages()
        owner.stack.setCurrentIndex(0)

    def _decorate_other_pages(self) -> None:
        # Store, settings, projects and catalog pages also receive graphical
        # badges where their existing buttons expose recognizable labels.
        for index in range(self.owner.stack.count()):
            page = self.owner.stack.widget(index)
            if page is self.home:
                continue
            for button in page.findChildren(QPushButton):
                title_prop = button.property("mechosTitle")
                title = str(title_prop) if title_prop is not None else button.text().splitlines()[0]
                if not title:
                    continue
                decorate_button(button, _key_for_title(title), 26)
