#!/usr/bin/env python3
"""Shared source-owned visual primitives for MechOS system screens.

All system surfaces use one 1920x1080 authored canvas. Geometry and typography
scale together with a single aspect-preserving factor so 720p, 1080p, higher
resolutions and VM fallback sessions keep the same composition.
"""
from __future__ import annotations

from PyQt6.QtCore import QRect, QSize, Qt
from PyQt6.QtGui import QColor, QFont, QIcon, QPainter, QPen
from PyQt6.QtWidgets import QLabel, QPushButton, QStyle, QWidget

BASE_W = 1920
BASE_H = 1080

# MECHOS_CREATOR_BUTTON_ICONS_V1
# This map is source-owned so Update Center installs receive the same icon
# behavior as hardware ISO builds. App-specific Creator surfaces can replace
# these theme icons with application-owned icons through creator_real_icons_v22.
MECHOS_BUTTON_ICONS = {
    'Dashboard': (('view-dashboard', 'applications-system'), QStyle.StandardPixmap.SP_ComputerIcon),
    'Projects': (('folder-projects', 'folder-documents', 'folder'), QStyle.StandardPixmap.SP_DirIcon),
    'Engines': (('applications-development', 'system-run'), QStyle.StandardPixmap.SP_ComputerIcon),
    'Tools': (('configure', 'applications-utilities'), QStyle.StandardPixmap.SP_FileDialogDetailedView),
    'Assets': (('folder-images', 'applications-graphics'), QStyle.StandardPixmap.SP_DirIcon),
    'MechClip AI': (('camera-video', 'video-x-generic'), QStyle.StandardPixmap.SP_MediaPlay),
    'Learn': (('help-contents', 'documentation'), QStyle.StandardPixmap.SP_DialogHelpButton),
    'Community': (('system-users', 'im-user'), QStyle.StandardPixmap.SP_DirHomeIcon),
    'Settings': (('settings-configure', 'configure'), QStyle.StandardPixmap.SP_FileDialogDetailedView),
    'System Monitor': (('utilities-system-monitor', 'org.kde.plasma-systemmonitor'), QStyle.StandardPixmap.SP_ComputerIcon),
    'New Project': (('document-new',), QStyle.StandardPixmap.SP_FileIcon),
    'Open Project': (('document-open', 'folder-open'), QStyle.StandardPixmap.SP_DialogOpenButton),
    'Project Manager': (('folder-projects', 'folder-documents'), QStyle.StandardPixmap.SP_DirIcon),
    'Creator Store': (('store', 'system-software-install'), QStyle.StandardPixmap.SP_DriveNetIcon),
    'Asset Browser': (('folder-images', 'applications-graphics'), QStyle.StandardPixmap.SP_DirIcon),
    'Creator Settings': (('settings-configure', 'configure'), QStyle.StandardPixmap.SP_FileDialogDetailedView),
    'Performance': (('speedometer', 'utilities-system-monitor'), QStyle.StandardPixmap.SP_ComputerIcon),
    'Optimization': (('speedometer', 'utilities-system-monitor'), QStyle.StandardPixmap.SP_ComputerIcon),
    'Blender': (('blender', 'applications-graphics'), QStyle.StandardPixmap.SP_FileIcon),
    'Unity Hub': (('unityhub', 'unity-hub', 'applications-development'), QStyle.StandardPixmap.SP_ComputerIcon),
    'Unreal Engine': (('unreal-editor', 'unreal-engine', 'applications-development'), QStyle.StandardPixmap.SP_ComputerIcon),
    'VS Code': (('visual-studio-code', 'com.visualstudio.code', 'code', 'applications-development'), QStyle.StandardPixmap.SP_FileIcon),
    'GitKraken': (('gitkraken', 'git', 'applications-development'), QStyle.StandardPixmap.SP_FileIcon),
    'Krita': (('krita', 'applications-graphics'), QStyle.StandardPixmap.SP_FileIcon),
    'OBS Studio': (('com.obsproject.Studio', 'obs', 'camera-video'), QStyle.StandardPixmap.SP_MediaPlay),
    'Godot': (('godot', 'org.godotengine.Godot', 'applications-development'), QStyle.StandardPixmap.SP_ComputerIcon),
    'VRChat Creator': (('vrchat-creator-companion', 'applications-development'), QStyle.StandardPixmap.SP_ComputerIcon),
    'Kdenlive': (('kdenlive', 'video-x-generic'), QStyle.StandardPixmap.SP_MediaPlay),
    'Audacity': (('audacity', 'audio-x-generic'), QStyle.StandardPixmap.SP_MediaVolume),
    'All 3D Tools': (('applications-graphics',), QStyle.StandardPixmap.SP_FileDialogDetailedView),
    'Refresh Updates': (('view-refresh',), QStyle.StandardPixmap.SP_BrowserReload),
    'View Updates': (('system-software-update', 'system-software-install'), QStyle.StandardPixmap.SP_ArrowForward),
    'Gaming Mode': (('applications-games', 'input-gaming'), QStyle.StandardPixmap.SP_MediaPlay),
    'Creator Mode': (('applications-graphics', 'applications-development'), QStyle.StandardPixmap.SP_ComputerIcon),
    'Desktop Mode': (('user-desktop', 'computer'), QStyle.StandardPixmap.SP_DesktopIcon),
    'MechScope': (('applications-games', 'utilities-system-monitor'), QStyle.StandardPixmap.SP_ComputerIcon),
}


class FixedCanvas(QWidget):
    # MECHOS_VISUAL_SURFACES_V14_FIXED_CANVAS
    # MECHOS_VISUAL_SURFACES_V9_FIXED_CANVAS - compatibility marker for prior visual gates.
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
        spec = MECHOS_BUTTON_ICONS.get(title)
        if spec:
            icon_names, fallback = spec
            icon = QIcon()
            for icon_name in icon_names:
                candidate = QIcon.fromTheme(icon_name)
                if not candidate.isNull():
                    icon = candidate
                    break
            if icon.isNull() and fallback is not None:
                icon = self.style().standardIcon(fallback)
            if not icon.isNull():
                q.setIcon(icon)
                q.setIconSize(QSize(22, 22))
                q.setProperty('mechosIconBase', 22)
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
                icon_base = widget.property('mechosIconBase')
                if icon_base:
                    icon_px = max(12, int(round(int(icon_base) * s)))
                    widget.setIconSize(QSize(icon_px, icon_px))
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
        p.fillRect(self.rect(), QColor('#020611'))
        self.paint_background(p)

    def paint_background(self, painter):
        pass
