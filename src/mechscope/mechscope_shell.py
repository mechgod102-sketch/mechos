#!/usr/bin/env python3
"""Source-owned MechScope visual composition.

This module deliberately owns only visual composition. Runtime actions are
passed in from the MechScope backend so ISO integration scripts cannot keep
rebuilding the screen with competing QHBoxLayout/QVBoxLayout patches.
"""

from __future__ import annotations

from typing import Callable, Iterable

from PyQt6.QtCore import QRect, Qt
from PyQt6.QtGui import QColor, QFont, QPainter, QPen
from PyQt6.QtWidgets import QLabel, QPushButton, QWidget


class Gauge(QWidget):
    def __init__(self, title: str, accent: str, parent: QWidget | None = None):
        super().__init__(parent)
        self.title = title
        self.accent = QColor(accent)
        self.value: int | None = None

    def setValue(self, value):
        try:
            self.value = max(0, min(100, int(float(value))))
        except Exception:
            self.value = None
        self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        side = max(24, min(self.width(), self.height()) - 16)
        inset = max(0, (self.width() - side) // 2)
        rect = self.rect().adjusted(inset, 8, -inset, -8)
        arc = rect.adjusted(5, 5, -5, -5)
        pen_width = max(3, int(min(self.width(), self.height()) / 20))
        base = QPen(QColor('#1c2941'), pen_width)
        base.setCapStyle(Qt.PenCapStyle.RoundCap)
        p.setPen(base)
        p.drawArc(arc, 90 * 16, -360 * 16)
        if self.value is not None:
            active = QPen(self.accent, pen_width)
            active.setCapStyle(Qt.PenCapStyle.RoundCap)
            p.setPen(active)
            p.drawArc(arc, 90 * 16, -int(360 * 16 * self.value / 100))
        p.setPen(QColor('#dce7ff'))
        f = QFont('Sans Serif', max(7, int(self.height() / 16)), QFont.Weight.Bold)
        p.setFont(f)
        p.drawText(rect.adjusted(0, 10, 0, 0), Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignHCenter, self.title)
        f.setPointSize(max(11, int(self.height() / 8)))
        p.setFont(f)
        p.drawText(rect, Qt.AlignmentFlag.AlignCenter, '--' if self.value is None else f'{self.value}%')


class MechScopeShell(QWidget):
    """Stable 16:9 visual shell using explicit authored geometry.

    The shell scales from a 1920x1080 design canvas. Major surfaces keep their
    intended positions and proportions at any resolution instead of being
    redistributed by Qt layout stretch factors.
    """

    BASE_W = 1920
    BASE_H = 1080
    RECENT_W = 1112
    RECENT_H = 300

    def __init__(self, owner, actions: dict[str, Callable[[], None]], parent=None):
        super().__init__(parent)
        self.owner = owner
        self.actions = actions
        self.widgets: list[QWidget] = []
        self.design_rects: dict[QWidget, QRect] = {}
        self.recent_rects: dict[QWidget, QRect] = {}
        self._build()

    def _register(self, widget: QWidget, rect: QRect):
        widget.setParent(self)
        self.widgets.append(widget)
        self.design_rects[widget] = rect
        return widget

    def _label(self, text: str, rect: QRect, size=14, bold=False, role='normal'):
        label = self._register(QLabel(text), rect)
        label.setWordWrap(True)
        label.setAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft)
        label.setProperty('role', role)
        font = QFont('Sans Serif', size)
        font.setBold(bold)
        label.setFont(font)
        return label

    def _button(self, key: str, title: str, subtitle: str, rect: QRect, primary=False):
        button = self._register(QPushButton(f'{title}\n{subtitle}'), rect)
        button.setProperty('role', 'primary' if primary else 'action')
        button.setCursor(Qt.CursorShape.PointingHandCursor)
        if key in self.actions:
            button.clicked.connect(self.actions[key])
        if hasattr(self.owner, 'focus_button'):
            try:
                self.owner.focus_button(button)
            except Exception:
                pass
        return button

    def _build(self):
        self.setObjectName('mechscopeNativeShell')
        self.setStyleSheet('''
QWidget#mechscopeNativeShell { background:#050912; color:#edf4ff; }
QLabel[role="muted"] { color:#8da1bd; }
QLabel[role="accent"] { color:#8b65ff; }
QLabel[role="section"] { color:#6ddcff; letter-spacing:2px; }
QPushButton[role="action"], QPushButton[role="primary"] {
  color:#f4f8ff; text-align:left; padding:10px 14px; border-radius:14px;
  background:#0c1422; border:1px solid #273a59; font-weight:700;
}
QPushButton[role="action"]:hover, QPushButton[role="action"]:focus {
  border:2px solid #64dcff; background:#111d30;
}
QPushButton[role="primary"] {
  border:2px solid #8d6aff;
  background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #33205f,stop:1 #112a4b);
}
QPushButton[role="primary"]:hover, QPushButton[role="primary"]:focus { border:3px solid #b69aff; }
''')

        self._label('◉  MECHOS', QRect(42, 18, 320, 54), 20, True)
        self._label('MECHSCOPE 2.0', QRect(760, 18, 400, 54), 24, True, 'accent')
        self.net_label = self._label('NET  detecting', QRect(1510, 18, 190, 54), 12, True, 'muted')
        self.time_label = self._label('--:--', QRect(1715, 18, 150, 54), 14, True)

        self._label('WELCOME TO', QRect(74, 112, 420, 34), 13, True, 'accent')
        self._label('MechScope 2.0', QRect(72, 148, 620, 68), 38, True)
        self._label('Your unified command center for gaming, performance, and creation.', QRect(72, 218, 640, 58), 16, False, 'muted')
        self._button('steam', 'Steam Library', 'Browse your games', QRect(72, 308, 300, 86), True)
        self._button('store', 'Unified Store', 'All games, one place', QRect(388, 308, 300, 86))
        self._button('performance', 'Performance Center', 'Optimize. Monitor. Dominate.', QRect(704, 308, 340, 86))

        self._label('SYSTEM STATUS', QRect(1188, 112, 300, 34), 13, True, 'section')
        self.cpu_gauge = self._register(Gauge('CPU', '#49deff'), QRect(1178, 150, 160, 160))
        self.ram_gauge = self._register(Gauge('RAM', '#a85cff'), QRect(1348, 150, 160, 160))
        self.disk_gauge = self._register(Gauge('DISK', '#258cff'), QRect(1518, 150, 160, 160))
        self.gpu_status = self._label('GPU  detecting', QRect(1188, 318, 500, 42), 12, True, 'muted')
        self.temp_label = self._label('Temperature: sensor dependent', QRect(1188, 360, 390, 34), 12, True, 'accent')
        self._button('performance', 'Run Optimization', 'Open Performance Center', QRect(1588, 342, 250, 60))

        self._label('RECENT GAMES', QRect(72, 438, 350, 34), 13, True, 'section')
        self.recent_host = self._register(QWidget(), QRect(72, 478, self.RECENT_W, self.RECENT_H))
        self.recent_host.setStyleSheet('QWidget { background:#090f1b; border:1px solid #22334f; border-radius:16px; }')

        self._label('QUICK ACTIONS', QRect(1218, 438, 290, 34), 13, True, 'section')
        qa = [
            ('updates', 'Update Center', 'Check system updates'),
            ('drivers', 'Drivers & Firmware', 'GPU and device support'),
            ('systeminfo', 'System Info', 'Hardware details'),
            ('network', 'Network Manager', 'Connections and Wi‑Fi'),
            ('performance', 'Power Plan', 'Performance profiles'),
        ]
        y = 478
        for key, title, sub in qa:
            self._button(key, title, sub, QRect(1218, y, 620, 54))
            y += 62

        self._label('QUICK MODES', QRect(72, 814, 300, 34), 13, True, 'section')
        self._button('gaming', 'Gaming Mode', 'Maximum performance', QRect(72, 854, 320, 78), True)
        self._button('desktop', 'Desktop Mode', 'Productivity & browsing', QRect(408, 854, 320, 78))
        self._button('creator', 'Creator Mode', 'Build. Edit. Publish.', QRect(744, 854, 320, 78))
        self._button('vr', 'VR / SteamVR', 'Immersive experience', QRect(1080, 854, 320, 78))
        self._button('recovery', 'Recovery', 'Repair & restore', QRect(1416, 854, 200, 78))
        self._button('shutdown', 'Power', 'Restart / shut down', QRect(1632, 854, 206, 78))

        self.pad_label = self._label('Controller: detecting', QRect(1440, 992, 398, 38), 12, True, 'muted')
        self._label('Ⓐ Select     Ⓑ Back     ☰ Menu     ✥ D‑Pad / Arrows Navigate', QRect(72, 992, 940, 38), 12, False, 'muted')

    def set_recent_games(self, games: Iterable, launch_game: Callable):
        for child in self.recent_host.findChildren(QWidget, options=Qt.FindChildOption.FindDirectChildrenOnly):
            child.deleteLater()
        self.recent_rects.clear()
        games = list(games)[:5]
        if not games:
            label = QLabel('No installed Steam games detected yet. Open Steam Library to sign in or install games.', self.recent_host)
            label.setWordWrap(True)
            label.setStyleSheet('color:#8da1bd;padding:20px;background:transparent;border:0;')
            self.recent_rects[label] = QRect(20, 20, 1060, 80)
            self._scale_recent()
            return
        card_w = 204
        gap = 14
        for i, game in enumerate(games):
            title = getattr(game, 'name', None) or getattr(game, 'title', None) or str(game)
            btn = QPushButton(str(title), self.recent_host)
            self.recent_rects[btn] = QRect(18 + i * (card_w + gap), 18, card_w, 264)
            btn.setStyleSheet('''QPushButton{background:#111a2a;border:1px solid #293f61;border-radius:14px;color:white;font-weight:800;padding:14px;} QPushButton:hover,QPushButton:focus{border:2px solid #66dcff;}''')
            btn.clicked.connect(lambda _=False, g=game: launch_game(g))
            if hasattr(self.owner, 'focus_button'):
                try:
                    self.owner.focus_button(btn)
                except Exception:
                    pass
        self._scale_recent()

    def _scale_recent(self):
        if not self.recent_rects:
            return
        sx = self.recent_host.width() / self.RECENT_W if self.RECENT_W else 1.0
        sy = self.recent_host.height() / self.RECENT_H if self.RECENT_H else 1.0
        for widget, rect in self.recent_rects.items():
            widget.setGeometry(
                int(rect.x() * sx), int(rect.y() * sy),
                max(1, int(rect.width() * sx)), max(1, int(rect.height() * sy)),
            )

    def resizeEvent(self, event):
        # Preserve the authored 16:9 composition and letterbox instead of letting
        # independent layout stretch factors reshape the interface.
        scale = min(self.width() / self.BASE_W, self.height() / self.BASE_H)
        ox = int((self.width() - self.BASE_W * scale) / 2)
        oy = int((self.height() - self.BASE_H * scale) / 2)
        for widget, rect in self.design_rects.items():
            widget.setGeometry(
                ox + int(rect.x() * scale),
                oy + int(rect.y() * scale),
                max(1, int(rect.width() * scale)),
                max(1, int(rect.height() * scale)),
            )
        self._scale_recent()
        super().resizeEvent(event)

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        scale = min(self.width()/self.BASE_W, self.height()/self.BASE_H)
        ox = int((self.width() - self.BASE_W*scale)/2)
        oy = int((self.height() - self.BASE_H*scale)/2)
        hero = QRect(46, 92, 1810, 326)
        r = QRect(ox+int(hero.x()*scale), oy+int(hero.y()*scale), int(hero.width()*scale), int(hero.height()*scale))
        p.setBrush(QColor('#08111e'))
        p.setPen(QPen(QColor('#3b2d68'), max(1, int(2*scale))))
        p.drawRoundedRect(r, int(22*scale), int(22*scale))
        p.setBrush(QColor('#070d16'))
        p.setPen(QPen(QColor('#1f304a'), max(1, int(1*scale))))
        for design in (QRect(46, 420, 1158, 378), QRect(1194, 420, 662, 378), QRect(46, 796, 1810, 158)):
            dr = QRect(ox+int(design.x()*scale), oy+int(design.y()*scale), int(design.width()*scale), int(design.height()*scale))
            p.drawRoundedRect(dr, int(18*scale), int(18*scale))
