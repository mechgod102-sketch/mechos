#!/usr/bin/env python3
"""MechOS Stream Center v14 — fullscreen OBS control surface."""
from __future__ import annotations
import json, subprocess, sys
from pathlib import Path
from PyQt6.QtCore import QTimer, Qt
from PyQt6.QtWidgets import (
    QApplication, QFrame, QGridLayout, QHBoxLayout, QLabel, QListWidget,
    QMainWindow, QMessageBox, QPushButton, QPlainTextEdit, QVBoxLayout, QWidget
)

CONTROL='/usr/local/bin/mechos-stream-control'
LOG=Path.home()/'.local/state/mechos/stream-center-v14.log'
STYLE='''
QMainWindow,QWidget{background:#020611;color:#f4f7ff}
QFrame#card{background:#07101e;border:1px solid #294968;border-radius:18px}
QFrame#hero{background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #101b34,stop:.55 #12102a,stop:1 #06222a);border:1px solid #594584;border-radius:24px}
QLabel#brand{font-size:21px;font-weight:900}
QLabel#title{font-size:32px;font-weight:900}
QLabel#section{font-size:13px;font-weight:900;color:#64e6ff;letter-spacing:2px}
QLabel#muted{color:#8fa4bf}
QLabel#live{color:#ff667d;font-size:18px;font-weight:900}
QLabel#ready{color:#53e89f;font-size:18px;font-weight:900}
QPushButton{background:#0c192b;border:1px solid #355371;border-radius:13px;color:#f7f9ff;padding:12px 15px;text-align:left;font-weight:800}
QPushButton:hover,QPushButton:focus{border:2px solid #6ae5ff;background:#152941}
QPushButton#primary{background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #55308b,stop:1 #16415a);border:2px solid #a67dff}
QPushButton#danger{background:#2d111c;border:1px solid #9b405e}
QListWidget,QPlainTextEdit{background:#040b15;border:1px solid #294968;border-radius:13px;color:#dce9f8;padding:10px}
QListWidget::item{padding:11px;border-radius:9px}
QListWidget::item:selected{background:#23365c;color:white}
'''

def log(msg):
    try:
        LOG.parent.mkdir(parents=True,exist_ok=True)
        with LOG.open('a',encoding='utf-8') as f:f.write(msg.rstrip()+'\n')
    except Exception:pass

def call(args, timeout=12):
    try:
        p=subprocess.run([CONTROL,*args],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
        log('$ '+CONTROL+' '+' '.join(args)+'\n'+(p.stdout or ''))
        return p
    except Exception as exc:
        log(f'command failed: {exc}')
        class Result:returncode=1; stdout=str(exc)
        return Result()

class StreamCenter(QMainWindow):
    # MECHOS_STREAM_CENTER_VISUAL_V14
    # MECHOS_HOTFIX14_ESCAPE_BACK_STREAMCENTER
    def __init__(self):
        super().__init__()
        self.setWindowTitle('MechOS Stream Center')
        self.setStyleSheet(STYLE)
        self.setWindowFlag(Qt.WindowType.FramelessWindowHint,True)
        self.build()
        self.setWindowState(Qt.WindowState.WindowFullScreen)
        QTimer.singleShot(0,self.showFullScreen)
        QTimer.singleShot(250,self.showFullScreen)
        QTimer.singleShot(500,self.refresh)

    def keyPressEvent(self,event):
        if event.key()==Qt.Key.Key_Escape:
            self.close(); return
        super().keyPressEvent(event)

    def card(self,name='card'):
        f=QFrame();f.setObjectName(name);return f
    def button(self,text,fn,primary=False,danger=False):
        b=QPushButton(text);b.setObjectName('primary' if primary else ('danger' if danger else ''));b.clicked.connect(fn);return b
    def section(self,text):
        q=QLabel(text);q.setObjectName('section');return q
    def muted(self,text):
        q=QLabel(text);q.setObjectName('muted');q.setWordWrap(True);return q

    def build(self):
        root=QWidget();self.setCentralWidget(root)
        outer=QVBoxLayout(root);outer.setContentsMargins(24,18,24,18);outer.setSpacing(14)
        top=QHBoxLayout();brand=QLabel('◉  MECHOS');brand.setObjectName('brand');top.addWidget(brand);top.addStretch();
        title=QLabel('STREAM CENTER');title.setObjectName('section');top.addWidget(title);top.addStretch();
        close=self.button('←  Return',self.close);close.setMaximumWidth(150);top.addWidget(close);outer.addLayout(top)

        hero=self.card('hero');hl=QHBoxLayout(hero);hl.setContentsMargins(28,24,28,24);hl.setSpacing(20)
        copy=QVBoxLayout();copy.addWidget(self.section('LIVE BROADCAST CONTROL'));h=QLabel('Your stream.\nOne command center.');h.setObjectName('title');copy.addWidget(h)
        copy.addWidget(self.muted('Control OBS streaming, recording and scenes without leaving MechOS. Your Twitch/YouTube account remains configured inside OBS Studio.'))
        hr=QHBoxLayout();hr.addWidget(self.button('●  GO LIVE',self.start_stream,True));hr.addWidget(self.button('■  END STREAM',self.stop_stream,False,True));hr.addWidget(self.button('◉  TOGGLE RECORDING',self.toggle_record));copy.addLayout(hr);hl.addLayout(copy,3)
        status=self.card();sl=QVBoxLayout(status);sl.addWidget(self.section('LIVE STATUS'));self.obs_state=QLabel('OBS  •  CHECKING');self.obs_state.setObjectName('muted');sl.addWidget(self.obs_state);self.stream_state=QLabel('STREAM  •  OFFLINE');self.stream_state.setObjectName('ready');sl.addWidget(self.stream_state);self.record_state=QLabel('RECORDING  •  IDLE');self.record_state.setObjectName('ready');sl.addWidget(self.record_state);self.scene_state=QLabel('SCENE  •  —');self.scene_state.setObjectName('muted');sl.addWidget(self.scene_state);hl.addWidget(status,2);outer.addWidget(hero)

        body=QHBoxLayout();body.setSpacing(14)
        scenes=self.card();sc=QVBoxLayout(scenes);sc.addWidget(self.section('SCENES'));sc.addWidget(self.muted('Select a scene, then activate it. Double-click also switches scenes.'));self.scenes=QListWidget();self.scenes.itemDoubleClicked.connect(lambda _item:self.set_scene());sc.addWidget(self.scenes,1);sc.addWidget(self.button('Switch to Selected Scene',self.set_scene,True));body.addWidget(scenes,2)

        controls=self.card();cl=QVBoxLayout(controls);cl.addWidget(self.section('OBS CONTROL'));cl.addWidget(self.button('Open OBS Studio',self.open_obs,True));cl.addWidget(self.button('Refresh Connection',self.refresh));cl.addWidget(self.button('Start Recording',lambda:self.action(['start-record'],'Start recording')));cl.addWidget(self.button('Stop Recording',lambda:self.action(['stop-record'],'Stop recording')));cl.addWidget(self.button('Start Stream',self.start_stream));cl.addWidget(self.button('Stop Stream',self.stop_stream));cl.addStretch();cl.addWidget(self.muted('OBS WebSocket: 127.0.0.1:4455\nIf OBS is not running, MechOS can launch it for supported actions.'));body.addWidget(controls,1)

        diag=self.card();dl=QVBoxLayout(diag);dl.addWidget(self.section('ACTIVITY & DIAGNOSTICS'));self.output=QPlainTextEdit();self.output.setReadOnly(True);self.output.setPlaceholderText('OBS status and command results appear here.');dl.addWidget(self.output,1);dl.addWidget(self.button('Clear Activity',self.output.clear));body.addWidget(diag,2)
        outer.addLayout(body,1)

    def show_error(self,title,text):
        QMessageBox.warning(self,title,text or 'Unknown OBS control error')
    def action(self,args,label='Action'):
        p=call(args)
        self.output.appendPlainText(f'{label}: '+((p.stdout or '').strip() or ('OK' if p.returncode==0 else 'FAILED')))
        if p.returncode:self.show_error(label,p.stdout)
        QTimer.singleShot(250,self.refresh)
    def start_stream(self):self.action(['start-stream'],'Start stream')
    def stop_stream(self):self.action(['stop-stream'],'Stop stream')
    def toggle_record(self):self.action(['toggle-record'],'Toggle recording')
    def open_obs(self):self.action(['launch-obs'],'Open OBS')
    def set_scene(self):
        item=self.scenes.currentItem()
        if not item:return
        self.action(['set-scene',item.text()],'Switch scene')

    def refresh(self):
        p=call(['status'])
        if p.returncode:
            self.obs_state.setText('OBS  •  OFFLINE');self.obs_state.setObjectName('muted');self.obs_state.style().unpolish(self.obs_state);self.obs_state.style().polish(self.obs_state)
            self.output.appendPlainText('OBS connection unavailable: '+(p.stdout or '').strip());return
        try:data=json.loads((p.stdout or '{}').strip())
        except Exception as exc:
            self.output.appendPlainText(f'Status parse error: {exc}');return
        streaming=bool(data.get('streaming',False));recording=bool(data.get('recording',False));scene=data.get('current_scene') or data.get('currentScene') or data.get('scene') or '—';scene_list=data.get('scenes') or []
        self.obs_state.setText('OBS  •  CONNECTED');self.obs_state.setObjectName('ready')
        self.stream_state.setText('STREAM  •  LIVE' if streaming else 'STREAM  •  OFFLINE');self.stream_state.setObjectName('live' if streaming else 'ready')
        self.record_state.setText('RECORDING  •  ACTIVE' if recording else 'RECORDING  •  IDLE');self.record_state.setObjectName('live' if recording else 'ready')
        self.scene_state.setText('SCENE  •  '+str(scene))
        for w in (self.obs_state,self.stream_state,self.record_state):w.style().unpolish(w);w.style().polish(w)
        wanted=[str(x) for x in scene_list]
        current=[self.scenes.item(i).text() for i in range(self.scenes.count())]
        if wanted!=current:
            self.scenes.clear();self.scenes.addItems(wanted)
            matches=self.scenes.findItems(str(scene),Qt.MatchFlag.MatchExactly)
            if matches:self.scenes.setCurrentItem(matches[0])
        self.output.appendPlainText(f'OBS connected • stream={streaming} • recording={recording} • scene={scene}')

def main():
    app=QApplication(sys.argv);app.setApplicationName('MechOS Stream Center');app.setStyleSheet('QToolTip{color:#fff;background:#101c2d;border:1px solid #43658a}')
    w=StreamCenter();w.showFullScreen();return app.exec()
if __name__=='__main__':raise SystemExit(main())
