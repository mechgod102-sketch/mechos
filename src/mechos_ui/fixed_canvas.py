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
    # MECHOS_VISUAL_SURFACES_V14_FIXED_CANVAS
    def __init__(self, parent=None):
        super().__init__(parent)
        self._rects = {}
        self._font_sizes = {}
        self.setObjectName('mechosFixedCanvas')
        self.setAttribute(Qt.WidgetAttribute.WA_OpaquePaintEvent, True)
        self.setStyleSheet('''
QWidget#mechosFixedCanvas{background:#020611;color:#f4f7ff}
QLabel[role="muted"]{color:#91a5c1}
QLabel[role="accent"]{color:#b96cff}
QLabel[role="section"]{color:#5ee7ff;letter-spacing:2px}
QPushButton[role="action"],QPushButton[role="primary"],QPushButton[role="danger"]{
 color:#f6f8ff;text-align:left;padding:6px 10px;border-radius:14px;
 background:#0d1a2d;border:1px solid #355176;font-weight:750
}
QPushButton[role="action"]:hover,QPushButton[role="action"]:focus{border:2px solid #5ee7ff;background:#182748}
QPushButton[role="primary"]{border:2px solid #9a74ef;background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #4b267e,stop:1 #12314d)}
QPushButton[role="primary"]:hover,QPushButton[role="primary"]:focus{border:3px solid #d0a6ff}
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
        # MECHOS_VM_RESPONSIVE_GEOMETRY_V2 - Build 118 late-stage compatibility marker.
        s = self.scale_factor()
        for widget, rect in self._rects.items():
            scaled = self.scale_rect(rect)
            widget.setGeometry(scaled)
            base = self._font_sizes.get(widget)
            if base is not None:
                f = widget.font(); f.setPointSize(max(5, int(round(base * s)))); widget.setFont(f)
            if isinstance(widget, QLabel):
                compact_label = s < 0.72 and rect.width() <= 220 and rect.height() <= 70
                widget.setWordWrap(not compact_label)
            if isinstance(widget, QPushButton) and widget.property('role') != 'hotspot':
                vpad = max(2, int(round(6 * s))); hpad = max(4, int(round(10 * s)))
                widget.setStyleSheet(f'padding:{vpad}px {hpad}px;')
                title_prop = widget.property('mechosTitle')
                if title_prop is not None:
                    title = str(title_prop); subtitle_prop = widget.property('mechosSubtitle')
                    subtitle = '' if subtitle_prop is None else str(subtitle_prop)
                    compact = bool(subtitle) and s < 0.72 and scaled.height() < 42
                    wanted = title if compact else title + (('\n' + subtitle) if subtitle else '')
                    if widget.text() != wanted: widget.setText(wanted)
        super().resizeEvent(event)

    def panel(self, painter, rect, fill='#08111e', border='#294566', radius=20, width=1):
        rr = self.scale_rect(rect); s = self.scale_factor()
        painter.setBrush(QColor(fill)); painter.setPen(QPen(QColor(border), max(1, int(width * s))))
        painter.drawRoundedRect(rr, int(radius * s), int(radius * s))

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        # Explicitly paint every pixel dark. This prevents Qt/Plasma/VM style
        # fallback from exposing a white backing surface in letterbox margins.
        p.fillRect(self.rect(), QColor('#020611'))
        self.paint_background(p)

    def paint_background(self, painter):
        pass
