#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from fixed_canvas import FixedCanvas
from PyQt6.QtCore import QRect
from PyQt6.QtWidgets import QComboBox,QPlainTextEdit

class RecoveryShell(FixedCanvas):
    # MECHOS_RECOVERY_VISUAL_V14
    def __init__(self,owner,actions,parent=None):
        super().__init__(parent); self.owner=owner; self.actions=actions; self.build()
    def act(self,key): return self.actions.get(key)
    def build(self):
        self.label('◉  MECHOS',QRect(42,18,300,54),20,True)
        self.label('RECOVERY CENTER',QRect(690,18,540,54),25,True,'accent')
        self.label('SAFE SYSTEM REPAIR  •  NO BLIND FORMATTING',QRect(1450,18,410,54),11,True,'muted')

        self.label('RECOVERY COMMAND',QRect(74,110,620,34),13,True,'section')
        self.label('Repair. Restore.\nGet Back In.',QRect(72,146,700,108),36,True)
        self.label('Inspect the installed system first, then choose a targeted repair. MechOS keeps the selected root and EFI target visible before any boot or rollback action.',QRect(72,266,720,92),14,False,'muted')
        self.button('↻  Rescan Systems','Detect installed Linux roots and EFI partitions',QRect(72,382,340,78),self.act('rescan'),True)
        self.button('◈  Hardware Scan','CPU, GPU, storage and boot environment',QRect(430,382,360,78),self.act('hardware'))

        self.label('RECOVERY TARGET',QRect(918,110,360,34),13,True,'section')
        self.label('●  TARGET STATUS',QRect(1520,110,290,34),11,True,'accent')
        self.label('Choose the installed root and EFI partition that MechOS should inspect.',QRect(918,146,900,38),12,False,'muted')
        self.label('Installed System',QRect(918,196,280,32),11,True,'muted')
        self.root_combo=self.reg(QComboBox(),QRect(918,232,900,58)); self.root_combo.setPlaceholderText('No installed system selected — run Rescan Systems')
        self.root_combo.setStyleSheet('QComboBox{background:#091524;color:#eef5ff;border:1px solid #42658e;border-radius:13px;padding:11px} QComboBox:hover{border:2px solid #6ce8ff}')
        self.label('EFI Partition',QRect(918,310,280,32),11,True,'muted')
        self.esp_combo=self.reg(QComboBox(),QRect(918,346,900,58)); self.esp_combo.setPlaceholderText('No EFI partition selected')
        self.esp_combo.setStyleSheet('QComboBox{background:#091524;color:#eef5ff;border:1px solid #42658e;border-radius:13px;padding:11px} QComboBox:hover{border:2px solid #a77cff}')
        self.label('✓  Selection stays visible before repair     ✓  Logs are preserved     ✓  Reinstall keeps confirmation screens',QRect(918,420,900,42),11,False,'muted')

        self.label('RECOVERY ACTIONS',QRect(72,520,380,34),13,True,'section')
        actions=[
          ('⚙  Repair Boot','Rebuild initramfs and restore the detected bootloader','repair',True,False),
          ('↶  Rollback Failed Update','Use a recorded compatible Snapper snapshot','rollback',False,False),
          ('▤  Install / Update Logs','Review MechOS install and update history','logs',False,False),
          ('⌂  Reinstall • Keep Home','Open protected reinstall workflow','keep-home',False,False),
          ('◉  Disk Check','Inspect selected storage and filesystem state','disk',False,False),
          ('←  Return to MechScope','Leave recovery and return to Gaming Mode','mechscope',False,False),
        ]
        for i,(title,sub,key,primary,danger) in enumerate(actions):
            x=72+(i%3)*584; y=568+(i//3)*104
            self.button(title,sub,QRect(x,y,552,86),self.act(key),primary,danger)

        self.label('DIAGNOSTIC CONSOLE',QRect(72,802,420,34),13,True,'section')
        self.label('LIVE RECOVERY OUTPUT',QRect(1455,802,350,34),10,True,'muted')
        self.output=self.reg(QPlainTextEdit(),QRect(72,844,1746,158)); self.output.setReadOnly(True); self.output.setPlaceholderText('Run a scan or recovery action to see detailed output here.')
        self.output.setStyleSheet('QPlainTextEdit{background:#030812;color:#c7daf0;border:1px solid #315578;border-radius:15px;padding:14px;font-family:Monospace;selection-background-color:#5a3d8f}')
        self.label('SAFETY: Boot Repair never repartitions or formats disks. Rollback appears only when MechOS recorded a compatible snapshot.',QRect(72,1010,1746,38),11,False,'muted')
    def paint_background(self,p):
        self.panel(p,QRect(46,92,786,392),'#07101d','#5a3f88',24,2)
        self.panel(p,QRect(884,92,972,392),'#06111e','#315d82',24,2)
        self.panel(p,QRect(46,502,1810,258),'#060d17','#2d4565',19,1)
        self.panel(p,QRect(46,784,1810,238),'#050b14','#2d4565',19,1)
