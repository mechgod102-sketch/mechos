#!/usr/bin/env python3
"""Reference-authored MechScope 2.0 visual composition.

The approved MechScope reference is 1672x941. This source uses the same authored
coordinate system and keeps a single aspect-preserving scale so the installed
system, Gamescope and VM fallback all retain the same composition.
"""
from __future__ import annotations

from pathlib import Path
from typing import Callable, Iterable

from PyQt6.QtCore import QRect, Qt
from PyQt6.QtGui import QColor, QFont, QLinearGradient, QPainter, QPen, QPixmap, QRadialGradient
from PyQt6.QtWidgets import QLabel, QPushButton, QWidget

BASE_W = 1672
BASE_H = 941


class Gauge(QWidget):
    def __init__(self, title: str, accent: str, parent=None):
        super().__init__(parent)
        self.title = title
        self.accent = QColor(accent)
        self.value = None
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)

    def setValue(self, value):
        try:
            self.value = max(0, min(100, int(float(value))))
        except Exception:
            self.value = None
        self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        side = min(self.width(), self.height()) - 12
        x = (self.width() - side) // 2
        arc = QRect(x + 6, 8, side - 12, side - 12)
        width = max(5, int(side * .075))
        base = QPen(QColor('#202a37'), width)
        base.setCapStyle(Qt.PenCapStyle.RoundCap)
        p.setPen(base)
        p.drawArc(arc, 90 * 16, -360 * 16)
        if self.value is not None:
            active = QPen(self.accent, width)
            active.setCapStyle(Qt.PenCapStyle.RoundCap)
            p.setPen(active)
            p.drawArc(arc, 90 * 16, -int(360 * 16 * self.value / 100))
        p.setPen(QColor('#eef5ff'))
        f = QFont('Sans Serif', max(8, int(self.height() * .095)))
        p.setFont(f)
        p.drawText(QRect(0, int(self.height()*.28), self.width(), 24), Qt.AlignmentFlag.AlignCenter, self.title)
        f.setPointSize(max(13, int(self.height() * .18)))
        f.setBold(True)
        p.setFont(f)
        p.drawText(QRect(0, int(self.height()*.43), self.width(), 40), Qt.AlignmentFlag.AlignCenter,
                   '--' if self.value is None else f'{self.value}%')


class MechScopeShell(QWidget):
    BASE_W = BASE_W
    BASE_H = BASE_H

    def __init__(self, owner, actions: dict[str, Callable[[], None]], parent=None):
        super().__init__(parent)
        self.owner = owner
        self.actions = actions
        self.design_rects = {}
        self.font_sizes = {}
        self.recent_widgets = []
        self.setObjectName('mechscopeReferenceShell')
        self.setStyleSheet('''
QWidget#mechscopeReferenceShell{background:#020711;color:#f4f7ff}
QLabel[role="muted"]{color:#9aa9bf}
QLabel[role="blue"]{color:#4b9cff}
QLabel[role="purple"]{color:#a783ff}
QPushButton[role="hero-blue"]{background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #123b77,stop:1 #0e2b59);border:2px solid #2e8bff;border-radius:13px;color:white;text-align:left;padding:10px 18px;font-weight:800}
QPushButton[role="hero-purple"]{background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #34205e,stop:1 #4a216c);border:2px solid #9d58ee;border-radius:13px;color:white;text-align:left;padding:10px 18px;font-weight:800}
QPushButton[role="hero-teal"]{background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #113948,stop:1 #0d2634);border:2px solid #2bbab0;border-radius:13px;color:white;text-align:left;padding:10px 18px;font-weight:800}
QPushButton[role="action"]{background:#111a29;border:1px solid #2a3b52;border-radius:10px;color:#f4f7ff;text-align:left;padding:7px 13px;font-weight:700}
QPushButton[role="mode"]{background:#0d1727;border:1px solid #33445e;border-radius:12px;color:#f7f9ff;font-weight:800}
QPushButton[role="mode-blue"]{background:#10284d;border:2px solid #318cff;border-radius:12px;color:white;font-weight:800}
QPushButton[role="mode-purple"]{background:#281937;border:1px solid #7e3a91;border-radius:12px;color:white;font-weight:800}
QPushButton[role="mode-teal"]{background:#0d2b2e;border:1px solid #247d7f;border-radius:12px;color:white;font-weight:800}
QPushButton[role="mode-gold"]{background:#2a2115;border:1px solid #8d6324;border-radius:12px;color:white;font-weight:800}
QPushButton[role="mode-red"]{background:#321519;border:1px solid #a13039;border-radius:12px;color:white;font-weight:800}
QPushButton:hover,QPushButton:focus{border:3px solid #bba4ff}
''')
        self._build()

    def _scale(self):
        if not self.width() or not self.height():
            return 1.0
        return min(self.width()/BASE_W, self.height()/BASE_H)

    def _origin(self):
        s = self._scale()
        return int((self.width()-BASE_W*s)/2), int((self.height()-BASE_H*s)/2)

    def _rect(self, r):
        s = self._scale(); ox, oy = self._origin()
        return QRect(ox+int(r.x()*s), oy+int(r.y()*s), max(1,int(r.width()*s)), max(1,int(r.height()*s)))

    def _reg(self, widget, rect, font_size=None):
        widget.setParent(self); self.design_rects[widget] = rect
        if font_size is not None: self.font_sizes[widget] = font_size
        return widget

    def _label(self, text, rect, size=14, bold=False, role='normal', align=None):
        q = self._reg(QLabel(text), rect, size)
        q.setWordWrap(True); q.setProperty('role', role)
        q.setAlignment(align or (Qt.AlignmentFlag.AlignVCenter|Qt.AlignmentFlag.AlignLeft))
        f = QFont('Sans Serif', size); f.setBold(bold); q.setFont(f)
        return q

    def _button(self, key, title, subtitle, rect, role='action', size=13):
        text = title + (('\n'+subtitle) if subtitle else '')
        q = self._reg(QPushButton(text), rect, size)
        q.setProperty('role', role)
        q.setCursor(Qt.CursorShape.PointingHandCursor)
        f = QFont('Sans Serif', size); f.setBold(True); q.setFont(f)
        fn = self.actions.get(key)
        if fn: q.clicked.connect(fn)
        if hasattr(self.owner, 'focus_button'):
            try: self.owner.focus_button(q)
            except Exception: pass
        return q

    def _build(self):
        # Header exactly follows the approved reference structure.
        self._label('◉  MECHOS', QRect(22,14,260,42), 20, True)
        self._label('MECHSCOPE 2.0', QRect(660,13,370,44), 22, True, 'purple', Qt.AlignmentFlag.AlignCenter)
        self.net_label = self._label('▥  NET detecting', QRect(1360,14,185,40), 12, False, 'muted', Qt.AlignmentFlag.AlignRight|Qt.AlignmentFlag.AlignVCenter)
        self.time_label = self._label('--:--', QRect(1553,14,96,40), 14, True, 'normal', Qt.AlignmentFlag.AlignRight|Qt.AlignmentFlag.AlignVCenter)

        # Hero copy / primary actions.
        self._label('WELCOME TO', QRect(63,86,260,28), 12, True, 'blue')
        self._label('MechScope 2.0', QRect(62,112,620,74), 36, True)
        self._label('Your unified command center for gaming, performance, and creation.', QRect(63,190,650,44), 14, False)
        self._button('steam','◉   Steam Library','Browse your games     ›',QRect(62,265,309,98),'hero-blue',14)
        self._button('store','▰   Unified Store','All games, one place     ›',QRect(387,265,299,98),'hero-purple',14)
        self._button('performance','◔   Performance Center','Optimize. Monitor. Dominate.     ›',QRect(703,265,314,98),'hero-teal',14)

        # Live system status replaces the static values shown in the concept.
        self._label('SYSTEM STATUS', QRect(1093,82,280,30), 12, True, 'blue')
        self.cpu_gauge = self._reg(Gauge('CPU','#3e85ff'), QRect(1100,119,128,128))
        self.ram_gauge = self._reg(Gauge('RAM','#9b58f0'), QRect(1236,119,128,128))
        self.disk_gauge = self._reg(Gauge('DISK','#31bbaa'), QRect(1372,119,128,128))
        self.gpu_status = self._label('▣  GPU detecting', QRect(1104,264,300,28), 12, False, 'muted')
        self.temp_label = self._label('♨  Temperature: sensor dependent', QRect(1104,291,310,28), 11, False, 'muted')
        self._button('performance','⌁   Run Optimization','Open Performance Center     ›',QRect(1091,337,518,62),'action',12)

        # Recent games and quick actions.
        self._label('RECENT GAMES', QRect(46,438,250,28), 12, True, 'blue')
        self.recent_host = self._reg(QWidget(), QRect(43,474,1001,218))
        self.recent_host.setStyleSheet('background:transparent')
        self._label('QUICK ACTIONS', QRect(1116,438,250,28), 12, True, 'blue')
        quick = [
            ('updates','⇩   Update Center'),('drivers','▣   Drivers & Firmware'),
            ('systeminfo','ⓘ   System Info'),('network','⌁   Network Manager'),
            ('performance','ϟ   Power Plan')]
        y = 470
        for key,title in quick:
            self._button(key,title,'›',QRect(1110,y,500,43),'action',11); y += 46

        # Bottom quick modes.
        self._label('QUICK MODES', QRect(46,719,250,28), 12, True, 'blue')
        modes = [
            ('gaming','🎮  Gaming Mode',QRect(46,756,244,75),'mode-blue'),
            ('desktop','▣  Desktop Mode',QRect(306,756,244,75),'mode'),
            ('creator','✦  Creator Mode',QRect(566,756,244,75),'mode-purple'),
            ('vr','◉  VR / SteamVR',QRect(826,756,244,75),'mode-teal'),
            ('recovery','↶  Recovery',QRect(1086,756,244,75),'mode-gold'),
            ('shutdown','⏻  Power',QRect(1350,756,244,75),'mode-red'),
        ]
        for key,title,rect,role in modes:
            self._button(key,title,'',rect,role,13)

        self._label('Ⓐ  Select     Ⓑ  Back     ☰  Menu     ✥  D-Pad / Arrows  Navigate', QRect(22,875,890,42), 11, False, 'muted')
        self.pad_label = self._label('🎮  Controller: detecting', QRect(1350,875,295,42), 11, False, 'muted', Qt.AlignmentFlag.AlignRight|Qt.AlignmentFlag.AlignVCenter)

    def _recent_card_style(self, scale: float, artwork: str = '') -> str:
        scale = max(.05, float(scale))
        radius = max(4, int(round(10 * scale)))
        border = max(1, int(round(scale)))
        focus_border = max(2, int(round(3 * scale)))
        top = max(10, int(round(142 * scale)))
        hpad = max(4, int(round(10 * scale)))
        bottom = max(4, int(round(10 * scale)))
        style = (
            'QPushButton{'
            'background:qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #17273b,stop:.68 #0e1724,stop:1 #09111d);'
            f'border:{border}px solid #2b405d;border-radius:{radius}px;color:#f5f8ff;'
            f'text-align:left;padding:{top}px {hpad}px {bottom}px {hpad}px;font-weight:800'
            '}'
            f' QPushButton:hover,QPushButton:focus{{border:{focus_border}px solid #6da7ff}}'
        )
        if artwork:
            crop = max(18, int(round(54 * scale)))
            style += f' QPushButton{{border-image:url("{artwork}") 0 0 {crop} 0 stretch stretch;}}'
        return style

    def _layout_recent_widgets(self):
        # MECHOS_RESPONSIVE_RECENT_GAMES_V1
        # recent_widgets are children of a scaled host, so their local geometry
        # must be scaled as well. Without this second-stage layout the host
        # shrank at 720p/VM resolutions while 190x210 cards stayed full-size and
        # clipped into adjacent panels.
        if not self.recent_widgets or not hasattr(self, 'recent_host'):
            return
        host_w = max(1, self.recent_host.width())
        host_h = max(1, self.recent_host.height())
        sx = host_w / 1001.0
        sy = host_h / 218.0
        scale = min(sx, sy)

        for child in self.recent_widgets:
            if bool(child.property('mechosRecentEmpty')):
                child.setGeometry(0, 0, host_w, max(1, int(round(210 * sy))))
                pad = max(6, int(round(16 * scale)))
                radius = max(4, int(round(10 * scale)))
                child.setStyleSheet(
                    f'color:#95a6be;background:#0b1320;border:1px solid #24364f;'
                    f'border-radius:{radius}px;padding:{pad}px'
                )
                f = child.font(); f.setPointSize(max(7, int(round(11 * scale)))); child.setFont(f)
                continue

            index = child.property('mechosRecentIndex')
            try:
                index = int(index)
            except Exception:
                index = 0
            child.setGeometry(
                int(round(index * (190 + 12) * sx)),
                0,
                max(1, int(round(190 * sx))),
                max(1, int(round(210 * sy))),
            )
            f = child.font(); f.setPointSize(max(7, int(round(11 * scale)))); f.setBold(True); child.setFont(f)
            artwork = child.property('mechosArtwork') or ''
            child.setStyleSheet(self._recent_card_style(scale, str(artwork)))

    def set_recent_games(self, games: Iterable, launch_game: Callable):
        for child in list(self.recent_widgets):
            child.deleteLater()
        self.recent_widgets.clear()
        games = list(games)[:5]
        if not games:
            q = QLabel('No installed Steam games detected yet. Open Steam Library to sign in or install games.', self.recent_host)
            q.setWordWrap(True)
            q.setProperty('mechosRecentEmpty', True)
            self.recent_widgets.append(q)
            self._layout_recent_widgets()
            return

        for i, game in enumerate(games):
            title = getattr(game,'name',None) or getattr(game,'title',None) or str(game)
            btn = QPushButton(str(title), self.recent_host)
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            btn.setProperty('mechosRecentIndex', i)
            btn.setProperty('mechosArtwork', '')
            btn.clicked.connect(lambda _=False,g=game: launch_game(g))
            # Use a local Steam artwork path when the backend supplies one.
            for attr in ('grid_path','cover_path','artwork','image','header_image'):
                p = getattr(game,attr,None)
                if p and Path(str(p)).is_file():
                    btn.setProperty('mechosArtwork', str(p))
                    break
            self.recent_widgets.append(btn)
            if hasattr(self.owner,'focus_button'):
                try:self.owner.focus_button(btn)
                except Exception:pass
        self._layout_recent_widgets()

    def resizeEvent(self, event):
        s = self._scale()
        for widget, rect in self.design_rects.items():
            widget.setGeometry(self._rect(rect))
            base = self.font_sizes.get(widget)
            if base is not None:
                f = widget.font(); f.setPointSize(max(7,int(round(base*s)))); widget.setFont(f)
        self._layout_recent_widgets()
        super().resizeEvent(event)

    def _panel(self, p, rect, fill='#07101b', border='#26374d', radius=14, width=1):
        rr = self._rect(rect); s = self._scale()
        p.setBrush(QColor(fill)); p.setPen(QPen(QColor(border),max(1,int(width*s))))
        p.drawRoundedRect(rr,int(radius*s),int(radius*s))

    def paintEvent(self, event):
        p = QPainter(self); p.setRenderHint(QPainter.RenderHint.Antialiasing,True)
        p.fillRect(self.rect(),QColor('#020711'))
        self._panel(p,QRect(23,64,1033,350),'#050c18','#24344c',14,1)
        self._panel(p,QRect(1070,64,577,350),'#07101a','#263a50',14,1)
        self._panel(p,QRect(23,427,1064,277),'#07101a','#26384e',14,1)
        self._panel(p,QRect(1096,427,551,277),'#07101a','#26384e',14,1)
        self._panel(p,QRect(23,716,1624,142),'#07101a','#26384e',14,1)

        # Reference hero planet / space glow. It is decorative and intentionally
        # drawn behind live controls so the same composition survives any GPU.
        hero = self._rect(QRect(590,70,470,338))
        grad = QRadialGradient(hero.right()-20,hero.center().y()+80,max(hero.width(),hero.height())*.72)
        grad.setColorAt(0,QColor(65,105,255,130)); grad.setColorAt(.38,QColor(27,54,150,90)); grad.setColorAt(.72,QColor(9,17,45,30)); grad.setColorAt(1,QColor(0,0,0,0))
        p.setPen(Qt.PenStyle.NoPen); p.setBrush(grad); p.drawEllipse(hero)
        ring = QPen(QColor(92,125,255,190),max(1,int(3*self._scale()))); p.setPen(ring); p.setBrush(Qt.BrushStyle.NoBrush); p.drawArc(hero.adjusted(35,35,-20,-20),15*16,145*16)
