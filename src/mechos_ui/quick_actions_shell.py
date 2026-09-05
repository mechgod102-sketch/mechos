#!/usr/bin/env python3
"""MechOS Quick Actions side panel with responsive v9 visual layout."""
from PyQt6.QtCore import QRect, Qt
from PyQt6.QtGui import QColor, QFont, QPainter, QPen
from PyQt6.QtWidgets import QLabel, QPushButton, QWidget


class QuickActionsShell(QWidget):
    # MECHOS_QUICK_ACTIONS_VISUAL_V9
    BASE_W = 620
    BASE_H = 1080

    def __init__(self, owner, actions, parent=None):
        super().__init__(parent)
        self.owner = owner
        self.actions = actions
        self.rects = {}
        self.font_sizes = {}
        self.setObjectName('mechosQuickActions')
        self.setStyleSheet('''
QWidget#mechosQuickActions{background:#040713;color:#f4f7ff}
QLabel[role="muted"]{color:#91a5c1}
QLabel[role="section"]{color:#5ee7ff;letter-spacing:2px}
QLabel[role="accent"]{color:#b96cff}
QPushButton{color:#f6f8ff;text-align:left;padding:8px 11px;border-radius:11px;background:#0d1a2d;border:1px solid #355176;font-weight:750}
QPushButton:hover,QPushButton:focus{border:2px solid #b68cff;background:#182748}
QPushButton[role="primary"]{border:2px solid #9a74ef;background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #4b267e,stop:1 #12314d)}
QPushButton[role="danger"]{border:1px solid #8e3852;background:#28111b}
''')
        self.build()

    def scale_factor(self):
        if not self.width() or not self.height():
            return 1.0
        return min(self.width()/self.BASE_W, self.height()/self.BASE_H)

    def origin(self):
        s = self.scale_factor()
        return int((self.width()-self.BASE_W*s)/2), int((self.height()-self.BASE_H*s)/2)

    def scaled(self, r):
        s = self.scale_factor(); ox, oy = self.origin()
        return QRect(ox+int(r.x()*s), oy+int(r.y()*s), max(1,int(r.width()*s)), max(1,int(r.height()*s)))

    def reg(self, w, r, size=None):
        w.setParent(self); self.rects[w] = r
        if size is not None: self.font_sizes[w] = size
        return w

    def label(self, t, r, size=12, bold=False, role='normal'):
        q = self.reg(QLabel(t), r, size); q.setProperty('role',role); q.setWordWrap(True)
        f = QFont('Sans Serif',size); f.setBold(bold); q.setFont(f); return q

    def button(self, title, sub, r, key, primary=False, danger=False, size=10):
        q = self.reg(QPushButton(title+(('\n'+sub) if sub else '')),r,size)
        q.setProperty('role','danger' if danger else ('primary' if primary else 'action'))
        q.setCursor(Qt.CursorShape.PointingHandCursor)
        f=QFont('Sans Serif',size); f.setBold(True); q.setFont(f)
        fn=self.actions.get(key)
        if fn: q.clicked.connect(fn)
        return q

    def build(self):
        # Header
        self.label('◉  MECHOS',QRect(24,18,170,38),17,True)
        self.label('QUICK ACTIONS',QRect(194,18,310,38),18,True,'section')
        self.button('✕','',QRect(546,16,50,42),'close',False,False,14)
        self.label('FAST SYSTEM CONTROL',QRect(24,58,300,22),9,True,'muted')

        # Performance
        self.label('PERFORMANCE',QRect(36,94,220,26),10,True,'section')
        self.button('Turbo','Maximum performance',QRect(36,126,168,58),'performance',True)
        self.button('Balanced','Everyday profile',QRect(216,126,168,58),'balanced')
        self.button('Quiet','Cooler / lower power',QRect(396,126,188,58),'battery')
        self.button('Performance Center','Monitoring, profiles and optimization',QRect(36,192,548,52),'performance-center',False,False,10)

        # Connectivity + system settings
        self.label('CONNECTIVITY & DEVICE',QRect(36,270,270,26),10,True,'section')
        self.button('Wi-Fi','Toggle wireless',QRect(36,302,168,54),'wifi')
        self.button('Bluetooth','Toggle devices',QRect(216,302,168,54),'bluetooth')
        self.button('Display','Screen settings',QRect(396,302,188,54),'display')
        self.button('System Settings','All KDE device settings',QRect(36,364,268,50),'system-settings')
        self.button('System Info','Hardware & OS details',QRect(316,364,268,50),'system-info')

        # Display + audio
        self.label('DISPLAY & AUDIO',QRect(36,440,220,26),10,True,'section')
        self.button('Brightness −','',QRect(36,472,168,52),'brightness-down')
        self.button('Brightness +','',QRect(216,472,168,52),'brightness-up')
        self.button('Audio Settings','Inputs & outputs',QRect(396,472,188,52),'audio-settings')
        self.button('Volume −','',QRect(36,532,168,52),'vol-down')
        self.button('Mute','',QRect(216,532,168,52),'mute')
        self.button('Volume +','',QRect(396,532,188,52),'vol-up')

        # RGB
        self.label('KEYBOARD RGB',QRect(36,610,220,26),10,True,'section')
        self.button('Choose Color','Open picker',QRect(36,642,168,52),'rgb-picker')
        self.button('Restore','Saved color',QRect(216,642,168,52),'rgb-restore')
        self.button('OpenRGB','Advanced',QRect(396,642,188,52),'rgb-advanced')

        # Streaming
        self.label('STREAMING & RECORDING',QRect(36,720,300,26),10,True,'section')
        self.button('Go Live','Start OBS stream',QRect(36,752,268,52),'go-live',True)
        self.button('End Stream','Stop OBS stream',QRect(316,752,268,52),'end-stream')
        self.button('Toggle Recording','Start / stop capture',QRect(36,812,268,52),'record')
        self.button('Stream Center','Scenes & OBS controls',QRect(316,812,268,52),'stream-center')

        # MechOS tools
        self.label('MECHOS TOOLS',QRect(36,890,220,26),10,True,'section')
        self.button('Update Center','System & hotfix updates',QRect(36,922,268,52),'updates')
        self.button('Creator Mode','Creation workspace',QRect(316,922,268,52),'creator')
        self.button('Recovery Center','Repair & restore',QRect(36,982,268,52),'recovery')
        self.button('Close Panel','Return to current mode',QRect(316,982,268,52),'close')

        self.label('Ctrl+Shift+M  •  Guide/Home + Y  •  Esc closes',QRect(36,1042,548,24),9,False,'muted')

    def resizeEvent(self,event):
        s=self.scale_factor()
        for w,r in self.rects.items():
            w.setGeometry(self.scaled(r))
            base=self.font_sizes.get(w)
            if base is not None:
                f=w.font(); f.setPointSize(max(7,int(round(base*s)))); w.setFont(f)
        super().resizeEvent(event)

    def _card(self,p,r):
        rr=self.scaled(r); s=self.scale_factor()
        p.setBrush(QColor('#07101d')); p.setPen(QPen(QColor('#294566'),max(1,int(s))))
        p.drawRoundedRect(rr,int(16*s),int(16*s))

    def paintEvent(self,event):
        p=QPainter(self); p.setRenderHint(QPainter.RenderHint.Antialiasing,True)
        p.fillRect(self.rect(),QColor('#040713'))
        rr=self.scaled(QRect(8,8,604,1064)); s=self.scale_factor()
        p.setBrush(QColor('#050a15')); p.setPen(QPen(QColor('#273b5a'),max(1,int(s))))
        p.drawRoundedRect(rr,int(20*s),int(20*s))
        for rect in (
            QRect(24,86,572,168),
            QRect(24,262,572,160),
            QRect(24,432,572,162),
            QRect(24,602,572,102),
            QRect(24,712,572,162),
            QRect(24,882,572,164),
        ):
            self._card(p,rect)
