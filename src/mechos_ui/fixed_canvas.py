#!/usr/bin/env python3
"""Shared source-owned visual primitives for MechOS system screens.

All system surfaces use one 1920x1080 authored canvas. Geometry and typography
scale together with a single aspect-preserving factor so 720p, 1080p, higher
resolutions and VM fallback sessions keep the same composition.
"""
from __future__ import annotations

from PyQt6.QtCore import QRect, Qt
from PyQt6.QtGui import QColor, QFont, QPainter, QPen
from PyQt6.QtWidgets import QLabel, QPushButton, QWidget

BASE_W = 1920
BASE_H = 1080


class FixedCanvas(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._rects = {}
        self._font_sizes = {}
        self.setObjectName('mechosFixedCanvas')
        self.setStyleSheet('''
QWidget#mechosFixedCanvas{background:#050912;color:#eef5ff}
QLabel[role="muted"]{color:#8da1bd}
QLabel[role="accent"]{color:#a176ff}
QLabel[role="section"]{color:#66dbff;letter-spacing:2px}
QPushButton[role="action"],QPushButton[role="primary"],QPushButton[role="danger"]{
 color:#f5f8ff;text-align:left;padding:6px 10px;border-radius:14px;
 background:#0c1422;border:1px solid #273a59;font-weight:750
}
QPushButton[role="action"]:hover,QPushButton[role="action"]:focus{border:2px solid #66dcff;background:#111d30}
QPushButton[role="primary"]{border:2px solid #936cff;background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #382164,stop:1 #10294a)}
QPushButton[role="primary"]:hover,QPushButton[role="primary"]:focus{border:3px solid #c3a7ff}
QPushButton[role="danger"]{border:1px solid #8e3852;background:#28111b}
''')

    def scale_factor(self):
        if not self.width() or not self.height():
            return 1.0
        return min(self.width() / BASE_W, self.height() / BASE_H)

    def origin(self):
        s = self.scale_factor()
        return int((self.width() - BASE_W * s) / 2), int((self.height() - BASE_H * s) / 2)

    def reg(self, widget, rect, font_size=None):
        widget.setParent(self)
        self._rects[widget] = rect
        if font_size is not None:
            self.track_font(widget, font_size)
        return widget

    def track_font(self, widget, point_size):
        self._font_sizes[widget] = max(1, int(point_size))
        f = widget.font()
        f.setPointSize(max(1, int(point_size)))
        widget.setFont(f)
        return widget

    def label(self, text, rect, size=14, bold=False, role='normal', align=None):
        q = self.reg(QLabel(text), rect, size)
        q.setWordWrap(True)
        q.setProperty('role', role)
        q.setAlignment(align or (Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft))
        f = QFont('Sans Serif', size)
        f.setBold(bold)
        q.setFont(f)
        self._font_sizes[q] = size
        return q

    def button(self, title, subtitle, rect, fn=None, primary=False, danger=False, size=13):
        q = self.reg(QPushButton(title + (('\n' + subtitle) if subtitle else '')), rect, size)
        q.setProperty('role', 'danger' if danger else ('primary' if primary else 'action'))
        q.setProperty('mechosTitle', title)
        q.setProperty('mechosSubtitle', subtitle)
        q.setCursor(Qt.CursorShape.PointingHandCursor)
        f = QFont('Sans Serif', size)
        f.setBold(True)
        q.setFont(f)
        self._font_sizes[q] = size
        if fn:
            q.clicked.connect(fn)
        return q

    def scale_rect(self, rect):
        s = self.scale_factor()
        ox, oy = self.origin()
        return QRect(
            ox + int(rect.x() * s),
            oy + int(rect.y() * s),
            max(1, int(rect.width() * s)),
            max(1, int(rect.height() * s)),
        )

    def resizeEvent(self, event):
        # MECHOS_VM_RESPONSIVE_GEOMETRY_V3
        # Scale geometry, typography and button padding together. On small VM
        # desktops, short controls also drop their secondary line when the
        # scaled height cannot safely hold two lines. This keeps click targets,
        # labels and text inside the same rectangle instead of visually stacking
        # controls over one another.
        s = self.scale_factor()
        for widget, rect in self._rects.items():
            scaled = self.scale_rect(rect)
            widget.setGeometry(scaled)
            base = self._font_sizes.get(widget)
            if base is not None:
                f = widget.font()
                f.setPointSize(max(5, int(round(base * s))))
                widget.setFont(f)
            if isinstance(widget, QPushButton) and widget.property('role') != 'hotspot':
                vpad = max(2, int(round(6 * s)))
                hpad = max(4, int(round(10 * s)))
                widget.setStyleSheet(f'padding:{vpad}px {hpad}px;')
                title = widget.property('mechosTitle') or ''
                subtitle = widget.property('mechosSubtitle') or ''
                # A two-line label needs roughly 42 rendered pixels after
                # borders/padding. Compact only short controls; larger cards
                # retain their explanatory subtitle even at VM resolutions.
                compact = bool(subtitle) and s < 0.72 and scaled.height() < 42
                wanted = title if compact else title + (('\n' + subtitle) if subtitle else '')
                if widget.text() != wanted:
                    widget.setText(wanted)
        super().resizeEvent(event)

    def panel(self, painter, rect, fill='#08111e', border='#263a59', radius=20, width=1):
        rr = self.scale_rect(rect)
        s = self.scale_factor()
        painter.setBrush(QColor(fill))
        painter.setPen(QPen(QColor(border), max(1, int(width * s))))
        painter.drawRoundedRect(rr, int(radius * s), int(radius * s))

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        self.paint_background(p)

    def paint_background(self, painter):
        pass
