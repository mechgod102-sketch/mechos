#!/usr/bin/env python3
"""Source-owned first-boot/OOBE visual shell for MechOS."""
from PyQt6.QtCore import QRect, Qt
from PyQt6.QtGui import QColor, QFont, QPainter, QPen
from PyQt6.QtWidgets import QComboBox, QLabel, QLineEdit, QPushButton, QStackedWidget, QWidget

from fixed_canvas import BASE_H, BASE_W, FixedCanvas


class OOBEPage(QWidget):
    BASE_W=1540
    BASE_H=700
    def __init__(self,parent=None):
        super().__init__(parent); self.rects={}; self.fonts={}
        self.setStyleSheet('''QWidget{background:#07101b;color:#eef5ff} QLabel[role="muted"]{color:#9aabc1} QLabel[role="section"]{color:#62d8ff} QLineEdit,QComboBox{background:#0d1727;border:1px solid #36516f;border-radius:12px;padding:10px;color:#eef5ff} QLineEdit:focus,QComboBox:focus{border:3px solid #a88cff}''')
    def reg(self,w,r,size=None): w.setParent(self); self.rects[w]=r; size is not None and self.fonts.__setitem__(w,size); return w
    def label(self,text,r,size=14,bold=False,role='normal'):
        q=self.reg(QLabel(text),r,size); q.setWordWrap(True); q.setProperty('role',role); f=QFont('Sans Serif',size); f.setBold(bold); q.setFont(f); return q
    def scale(self): return min(self.width()/self.BASE_W,self.height()/self.BASE_H) if self.width() and self.height() else 1.0
    def resizeEvent(self,event):
        s=self.scale(); ox=int((self.width()-self.BASE_W*s)/2); oy=int((self.height()-self.BASE_H*s)/2)
        for w,r in self.rects.items():
            w.setGeometry(ox+int(r.x()*s),oy+int(r.y()*s),max(1,int(r.width()*s)),max(1,int(r.height()*s)))
            if w in self.fonts:
                f=w.font(); f.setPointSize(max(8,int(round(self.fonts[w]*s)))); w.setFont(f)
        super().resizeEvent(event)


class OOBEShell(FixedCanvas):
    def __init__(self,owner,zones,locales,keymaps,parent=None):
        super().__init__(parent); self.owner=owner; self.zones=zones; self.locales=locales; self.keymaps=keymaps; self.build()
        self.setStyleSheet(self.styleSheet()+'''QPushButton[role="nav"]{background:#0d1727;border:1px solid #36516f;border-radius:13px;color:#eef5ff;font-weight:800} QPushButton[role="primary"]{background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #1a64c7,stop:1 #7a42c7);border:2px solid #a88cff;border-radius:13px;color:white;font-weight:900} QPushButton:focus{border:3px solid #c6b5ff}''')

    def page_base(self,kicker,title,body):
        p=OOBEPage(); p.label(kicker,QRect(70,52,700,34),13,True,'section'); p.label(title,QRect(68,90,1280,78),34,True); p.label(body,QRect(70,174,1280,68),14,False,'muted'); return p

    def build(self):
        self.label('◉  MECHOS',QRect(42,22,320,52),20,True)
        self.label('FIRST SYSTEM SETUP',QRect(690,22,540,52),23,True,'accent',Qt.AlignmentFlag.AlignCenter)
        self.label('1  WELCOME   •   2  ACCOUNT   •   3  REGION   •   4  DEVICE   •   5  REVIEW',QRect(1230,22,640,52),10,True,'muted',Qt.AlignmentFlag.AlignRight|Qt.AlignmentFlag.AlignVCenter)
        self.stack=self.reg(QStackedWidget(),QRect(190,118,1540,700))

        welcome=self.page_base('WELCOME TO MECHOS','Ready the system for your pilot profile.','Configure the permanent account, region and device identity used by the installed system. MechScope starts after setup is complete.')
        welcome.label('Gaming Mode • Creator Mode • Performance Center • Update Center',QRect(70,310,1320,64),19,True)
        welcome.label('The temporary setup account is removed when setup finishes. Your real password is used only for local administrator actions.',QRect(70,392,1320,80),14,False,'muted')
        self.stack.addWidget(welcome)

        account=self.page_base('ACCOUNT','Create your MechOS account.','This becomes the everyday login for Gaming Mode and Desktop Mode.')
        account.label('Username',QRect(70,290,300,34),12,True,'muted'); self.username=account.reg(QLineEdit(),QRect(70,326,650,58),14); self.username.setPlaceholderText('example: mechpilot')
        account.label('Password',QRect(70,410,300,34),12,True,'muted'); self.password=account.reg(QLineEdit(),QRect(70,446,650,58),14); self.password.setEchoMode(QLineEdit.EchoMode.Password)
        account.label('Confirm password',QRect(790,410,300,34),12,True,'muted'); self.confirm=account.reg(QLineEdit(),QRect(790,446,650,58),14); self.confirm.setEchoMode(QLineEdit.EchoMode.Password)
        account.label('Use at least 8 characters. Password text is never shown on the review page.',QRect(70,548,1370,54),12,False,'muted')
        self.stack.addWidget(account)

        region=self.page_base('REGION & TIME','Set your local environment.','Choose the timezone and language/locale used by MechOS and creator applications.')
        region.label('Timezone',QRect(70,300,300,34),12,True,'muted'); self.zone=region.reg(QComboBox(),QRect(70,338,650,60),14); self.zone.setEditable(True); self.zone.addItems(self.zones); self.zone.setCurrentText('America/New_York' if 'America/New_York' in self.zones else (self.zones[0] if self.zones else 'UTC'))
        region.label('Language / locale',QRect(790,300,300,34),12,True,'muted'); self.locale=region.reg(QComboBox(),QRect(790,338,650,60),14); self.locale.addItems(self.locales); self.locale.setCurrentText('en_US.UTF-8')
        region.label('These settings can be changed later from Desktop Mode.',QRect(70,456,1370,50),12,False,'muted')
        self.stack.addWidget(region)

        device=self.page_base('DEVICE','Name and identify this machine.','Choose the keyboard layout and local network name for the installed system.')
        device.label('Keyboard layout',QRect(70,300,300,34),12,True,'muted'); self.keyboard=device.reg(QComboBox(),QRect(70,338,650,60),14)
        for label,code in self.keymaps: self.keyboard.addItem(label,code)
        device.label('Computer name',QRect(790,300,300,34),12,True,'muted'); self.hostname=device.reg(QLineEdit('mechos'),QRect(790,338,650,60),14); self.hostname.setPlaceholderText('example: gaming-rig')
        device.label('The computer name is used for local networking and diagnostics.',QRect(70,456,1370,50),12,False,'muted')
        self.stack.addWidget(device)

        review=self.page_base('REVIEW','Ready to finish setup.','Confirm the configuration below. Your password is intentionally not displayed.')
        self.review=review.reg(QLabel(),QRect(70,290,1370,250),17); self.review.setWordWrap(True); self.review.setStyleSheet('background:#0b1524;border:1px solid #314b6b;border-radius:16px;padding:24px;color:#eef5ff')
        self.stack.addWidget(review)

        self.back=self.button('Back','Previous step',QRect(190,850,260,78),self.owner.prev_page,False,False,13); self.back.setProperty('role','nav')
        self.next=self.button('Next','Continue setup',QRect(1470,850,260,78),self.owner.next_page,True,False,13); self.next.setProperty('role','primary')
        self.label('Enter / A  Select     Esc / B  Back     D-Pad / Arrows  Navigate',QRect(550,858,800,58),11,False,'muted',Qt.AlignmentFlag.AlignCenter)

    def paint_background(self,p):
        p.fillRect(self.scale_rect(QRect(0,0,BASE_W,BASE_H)),QColor('#030711'))
        self.panel(p,QRect(160,94,1600,748),'#07101b','#2a3f5d',22,1)
