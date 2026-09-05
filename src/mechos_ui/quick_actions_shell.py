#!/usr/bin/env python3
"""MechOS Quick Actions responsive overlay — Hotfix 14 visual authority."""
from PyQt6.QtCore import QRect, Qt
from PyQt6.QtGui import QColor, QFont, QLinearGradient, QPainter, QPen
from PyQt6.QtWidgets import QLabel, QPushButton, QWidget


class QuickActionsShell(QWidget):
    # MECHOS_QUICK_ACTIONS_VISUAL_V14
    BASE_W = 700
    BASE_H = 1080

    def __init__(self, owner, actions, parent=None):
        super().__init__(parent)
        self.owner = owner
        self.actions = actions
        self.rects = {}
        self.font_sizes = {}
        self.setObjectName('mechosQuickActions')
        self.setAttribute(Qt.WidgetAttribute.WA_OpaquePaintEvent, True)
        self.setStyleSheet('''
QWidget#mechosQuickActions{background:#020611;color:#f4f7ff}
QLabel[role="muted"]{color:#8fa4c0}
QLabel[role="section"]{color:#65e8ff;letter-spacing:2px}
QLabel[role="accent"]{color:#c08cff}
QPushButton{color:#f7f9ff;text-align:left;padding:9px 13px;border-radius:13px;background:#0b1628;border:1px solid #2b4568;font-weight:750}
QPushButton:hover,QPushButton:focus{border:2px solid #73dcff;background:#142640}
QPushButton[role="primary"]{border:2px solid #a275ff;background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #4a287e,stop:1 #123552)}
QPushButton[role="primary"]:hover,QPushButton[role="primary"]:focus{border:3px solid #d2b0ff}
QPushButton[role="danger"]{border:1px solid #93415b;background:#2b121d}
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
        self.label('◉  MECHOS',QRect(26,16,190,40),18,True)
        self.label('QUICK ACTIONS',QRect(212,16,350,40),19,True,'section')
        self.button('✕','',QRect(624,14,48,44),'close',False,False,14)
        self.label('LIVE SYSTEM CONTROL  •  ESC TO CLOSE',QRect(26,58,420,24),9,True,'muted')

        self.label('PERFORMANCE',QRect(42,98,240,26),10,True,'section')
        self.button('⚡  Turbo','Maximum performance',QRect(42,130,190,60),'performance',True)
        self.button('◉  Balanced','Everyday profile',QRect(246,130,190,60),'balanced')
        self.button('☾  Quiet','Cooler / lower power',QRect(450,130,208,60),'battery')
        self.button('◔  Performance Center','Monitoring, profiles & optimization',QRect(42,200,616,54),'performance-center')

        self.label('CONNECTIVITY & DEVICE',QRect(42,284,300,26),10,True,'section')
        self.button('⌁  Wi-Fi','Toggle wireless',QRect(42,316,190,56),'wifi')
        self.button('◌  Bluetooth','Toggle devices',QRect(246,316,190,56),'bluetooth')
        self.button('▣  Display','Screen settings',QRect(450,316,208,56),'display')
        self.button('⚙  System Settings','All device settings',QRect(42,382,296,52),'system-settings')
        self.button('ⓘ  System Info','Hardware & OS details',QRect(350,382,308,52),'system-info')

        self.label('DISPLAY & AUDIO',QRect(42,464,240,26),10,True,'section')
        self.button('☀  Brightness −','',QRect(42,496,190,52),'brightness-down')
        self.button('☀  Brightness +','',QRect(246,496,190,52),'brightness-up')
        self.button('♫  Audio Settings','Inputs & outputs',QRect(450,496,208,52),'audio-settings')
        self.button('🔉  Volume −','',QRect(42,558,190,52),'vol-down')
        self.button('🔇  Mute','',QRect(246,558,190,52),'mute')
        self.button('🔊  Volume +','',QRect(450,558,208,52),'vol-up')

        self.label('KEYBOARD RGB',QRect(42,640,240,26),10,True,'section')
        self.button('◈  Choose Color','Open picker',QRect(42,672,190,54),'rgb-picker')
        self.button('↶  Restore','Saved color',QRect(246,672,190,54),'rgb-restore')
        self.button('✦  OpenRGB','Advanced control',QRect(450,672,208,54),'rgb-advanced')

        self.label('STREAMING & RECORDING',QRect(42,756,320,26),10,True,'section')
        self.button('●  Go Live','Start OBS stream',QRect(42,788,296,54),'go-live',True)
        self.button('■  End Stream','Stop OBS stream',QRect(350,788,308,54),'end-stream')
        self.button('◉  Toggle Recording','Start / stop capture',QRect(42,852,296,54),'record')
        self.button('▤  Stream Center','Scenes, OBS & live status',QRect(350,852,308,54),'stream-center')

        self.label('MECHOS TOOLS',QRect(42,934,240,26),10,True,'section')
        self.button('⇩  Update Center','System & hotfix updates',QRect(42,966,296,54),'updates')
        self.button('✦  Creator Mode','Creation workspace',QRect(350,966,308,54),'creator')
        self.button('↶  Recovery Center','Repair & restore',QRect(42,1030,296,42),'recovery')
        self.button('←  Close Panel','Return to current mode',QRect(350,1030,308,42),'close')

    def resizeEvent(self,event):
        s=self.scale_factor()
        for w,r in self.rects.items():
            w.setGeometry(self.scaled(r))
            base=self.font_sizes.get(w)
            if base is not None:
                f=w.font(); f.setPointSize(max(7,int(round(base*s)))); w.setFont(f)
        super().resizeEvent(event)

    def _card(self,p,r,fill='#07101e',border='#284766'):
        rr=self.scaled(r); s=self.scale_factor()
        p.setBrush(QColor(fill)); p.setPen(QPen(QColor(border),max(1,int(s))))
        p.drawRoundedRect(rr,int(17*s),int(17*s))

    def paintEvent(self,event):
        p=QPainter(self); p.setRenderHint(QPainter.RenderHint.Antialiasing,True)
        p.fillRect(self.rect(),QColor('#020611'))
        rr=self.scaled(QRect(10,8,680,1064)); s=self.scale_factor()
        grad=QLinearGradient(rr.topLeft(),rr.bottomRight()); grad.setColorAt(0,QColor('#06101e')); grad.setColorAt(1,QColor('#030712'))
        p.setBrush(grad); p.setPen(QPen(QColor('#304a6c'),max(1,int(s))))
        p.drawRoundedRect(rr,int(22*s),int(22*s))
        for rect in (
            QRect(28,88,644,176), QRect(28,274,644,170), QRect(28,454,644,166),
            QRect(28,630,644,106), QRect(28,746,644,170), QRect(28,924,644,154),
        ):
            self._card(p,rect)
