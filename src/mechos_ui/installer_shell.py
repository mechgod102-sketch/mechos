#!/usr/bin/env python3
"""Reference-backed MechOS Live installer surface.

The approved installer PNG remains the visual authority for static chrome,
branding, panel placement and styling. Demo/reference-only values baked into the
artwork are masked at runtime and replaced with real machine/install data so the
installer cannot lie about hardware, drives, version or install state.
"""
from pathlib import Path
import subprocess

from PyQt6.QtCore import QRect, Qt, QTimer
from PyQt6.QtGui import QColor, QFont, QPainter, QPixmap
from PyQt6.QtWidgets import QLabel, QProgressBar, QPushButton

from fixed_canvas import BASE_H, BASE_W, FixedCanvas

REFERENCE = Path('/usr/share/mechos/branding/mechos-installer-reference.png')
RELEASE = Path('/etc/mechos/release')


def _run(*args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ''


def _one_line(text, limit=52):
    text = ' '.join((text or '').split())
    if len(text) > limit:
        return text[: max(1, limit - 1)] + '…'
    return text


def _cpu_name():
    out = _run('lscpu')
    for line in out.splitlines():
        if line.lower().startswith('model name:'):
            return _one_line(line.split(':', 1)[1], 44)
    return 'CPU detecting'


def _ram_name():
    try:
        kb = 0
        for line in Path('/proc/meminfo').read_text(encoding='utf-8').splitlines():
            if line.startswith('MemTotal:'):
                kb = int(line.split()[1]); break
        if kb:
            return f'{kb / 1024 / 1024:.1f} GB memory'
    except Exception:
        pass
    return 'RAM detecting'


def _gpu_name():
    out = _run('lspci')
    for line in out.splitlines():
        if any(tag in line for tag in ('VGA compatible controller', '3D controller', 'Display controller')):
            value = line.split(': ', 1)[1] if ': ' in line else line
            return _one_line(value, 46)
    return 'GPU detecting'


def _firmware_name():
    fw = 'UEFI' if Path('/sys/firmware/efi').exists() else 'Legacy BIOS'
    virt = _run('systemd-detect-virt')
    if virt and virt not in ('none', 'unknown'):
        return f'{fw} • {virt}'
    return fw


def _release_name():
    try:
        value = RELEASE.read_text(encoding='utf-8').strip()
        return value or '0.3.0-alpha'
    except Exception:
        return '0.3.0-alpha'


class InstallerShell(FixedCanvas):
    def __init__(self, owner, parent=None):
        super().__init__(parent)
        self.owner = owner
        self.reference = QPixmap(str(REFERENCE))
        self.mode_buttons = {}
        self.current_path = ''
        self.current_model = ''
        self.current_size = ''
        self.setStyleSheet('''
QWidget#mechosFixedCanvas{background:#030711;color:#eef5ff}
QPushButton[role="hotspot"]{background:transparent;border:0;color:transparent;padding:0;margin:0}
QPushButton[role="hotspot"]:hover{background:rgba(36,141,255,10);border:1px solid rgba(102,220,255,90);border-radius:12px}
QPushButton[role="mode"]{color:#eef5ff;text-align:left;padding:12px 16px;border-radius:12px;background:#0b1423;border:1px solid #2c4263;font-weight:700}
QPushButton[role="mode"]:hover,QPushButton[role="mode"]:focus{background:#101d31;border:2px solid #51c9ff}
QPushButton[role="mode"]:checked{background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #173a70,stop:1 #26184c);border:2px solid #5ab9ff}
QPushButton[role="action-secondary"]{color:#eef5ff;padding:12px 18px;border-radius:14px;background:#0b1423;border:1px solid #375272;font-weight:800}
QPushButton[role="action-secondary"]:hover,QPushButton[role="action-secondary"]:focus{background:#13223a;border:2px solid #58c7ff}
QPushButton[role="action-primary"]{color:#ffffff;padding:12px 18px;border-radius:14px;background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #1d74c9,stop:0.55 #3159c9,stop:1 #713db3);border:2px solid #65d7ff;font-weight:900}
QPushButton[role="action-primary"]:hover,QPushButton[role="action-primary"]:focus{border:3px solid #caa7ff;background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #258be9,stop:0.55 #496de1,stop:1 #8b4bd3)}
QLabel[role="runtime-title"]{color:#eef5ff;background:transparent}
QLabel[role="runtime-muted"]{color:#91a6c6;background:transparent}
QLabel[role="runtime-accent"]{color:#58bfff;background:transparent}
QProgressBar{background:#07101c;border:1px solid #315174;border-radius:8px;color:#eef5ff;text-align:center}
QProgressBar::chunk{background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #248dff,stop:1 #9b5cff);border-radius:7px}
''')
        self._build()
        # In Plasma-backed VM sessions setWindowState() can be downgraded to a
        # maximized window during startup. Reassert true fullscreen after the
        # event loop starts so the Plasma panel never sits under the installer.
        QTimer.singleShot(0, self.owner.showFullScreen)
        QTimer.singleShot(250, self.owner.showFullScreen)
        QTimer.singleShot(1000, self.owner.showFullScreen)

    def hotspot(self, name, rect, fn=None):
        q = self.reg(QPushButton(''), rect)
        q.setProperty('role', 'hotspot')
        q.setToolTip(name)
        q.setAccessibleName(name)
        # Transparent reference-backed navigation is pointer-only. Keeping
        # these buttons out of the keyboard focus chain prevents a stray focus
        # border from revealing an invisible hitbox over the artwork.
        q.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        q.setCursor(Qt.CursorShape.PointingHandCursor)
        if fn:
            q.clicked.connect(fn)
        return q

    def action_button(self, title, rect, fn, primary=False):
        """Render the action and its hit target as the same Qt widget.

        The old Live installer used invisible hotspots over buttons baked into
        the reference PNG. Any artwork/runtime geometry drift could therefore
        make a button look clickable in one place while the real hit target sat
        somewhere else. These source-owned buttons make visual and input
        geometry identical at every FixedCanvas scale.
        """
        q = self.reg(QPushButton(title), rect, 13)
        q.setProperty('role', 'action-primary' if primary else 'action-secondary')
        q.setProperty('mechosTitle', title)
        q.setProperty('mechosSubtitle', '')
        q.setAccessibleName(title)
        q.setCursor(Qt.CursorShape.PointingHandCursor)
        q.clicked.connect(fn)
        f = QFont('Sans Serif', 13)
        f.setBold(True)
        q.setFont(f)
        self._font_sizes[q] = 13
        return q

    def runtime_label(self, text, rect, size=12, bold=False, role='runtime-title'):
        q = self.reg(QLabel(text), rect, size)
        q.setProperty('role', role)
        q.setWordWrap(True)
        q.setAlignment(Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft)
        f = QFont('Sans Serif', size)
        f.setBold(bold)
        q.setFont(f)
        self._font_sizes[q] = size
        return q

    def mode_button(self, key, title, subtitle, rect):
        b = self.reg(QPushButton(f'{title}\n{subtitle}'), rect, 11)
        b.setProperty('role', 'mode')
        b.setCheckable(True)
        b.setCursor(Qt.CursorShape.PointingHandCursor)
        b.setAccessibleName(title)
        b.clicked.connect(lambda _=False, m=key: self.owner.set_mode(m, True))
        f = QFont('Sans Serif', 11)
        f.setBold(True)
        b.setFont(f)
        self._font_sizes[b] = 11
        self.mode_buttons[key] = b
        return b

    def _build(self):
        # The approved artwork has exactly eight visible navigation rows.
        # Their reference-space card bounds are x=72..486, y=192..278, with
        # 90 authored pixels between row starts. The previous 28/154/318/66
        # geometry was visibly up/left of the artwork and also created a ninth
        # invisible hitbox with no corresponding step.
        for row in range(8):
            self.hotspot(
                f'Installer step {row + 1}',
                QRect(72, 192 + row * 90, 414, 86),
                lambda _=False, r=row: self.owner.nav_selected(r),
            )

        self.repair_button = self.action_button('Repair', QRect(1280, 930, 250, 96), self.owner.recovery)
        self.install_button = self.action_button('Install Now', QRect(1540, 930, 330, 96), self.owner.install, primary=True)

        # Mask only the demo-data regions; preserve approved reference chrome.
        # Real target panel. This replaces the fake WD/Samsung/Seagate devices
        # embedded in the design reference.
        self.runtime_label('SELECT INSTALL TARGET', QRect(430, 300, 520, 34), 12, True, 'runtime-accent')
        self.drive_title = self.runtime_label('No drive selected', QRect(465, 365, 540, 42), 15, True)
        self.drive_detail = self.runtime_label('Choose the drive MechOS should install to.', QRect(465, 408, 590, 54), 11, False, 'runtime-muted')
        self.drive_path = self.runtime_label('', QRect(465, 466, 590, 34), 10, True, 'runtime-accent')
        self.change_drive = self.reg(QPushButton('Change Drive'), QRect(955, 378, 170, 64), 11)
        self.change_drive.setProperty('role', 'mode')
        self.change_drive.clicked.connect(self.owner.open_partition_selector)

        # Real install options. Reference art provides the surrounding chrome;
        # these cards own the actual selected state.
        self.runtime_label('INSTALLATION OPTIONS', QRect(430, 575, 520, 34), 12, True, 'runtime-accent')
        self.mode_button('clean', 'Clean Install', 'Erase target and install MechOS', QRect(430, 625, 225, 108))
        self.mode_button('keep', 'Keep Personal Data', 'Preserve user files where supported', QRect(672, 625, 225, 108))
        self.mode_button('custom', 'Custom Install', 'Advanced partition/install options', QRect(914, 625, 225, 108))

        # Real system summary. Never show the reference machine's demo Ryzen,
        # RTX, motherboard or memory values as if they belonged to the user.
        self.runtime_label('SYSTEM SUMMARY', QRect(1290, 250, 500, 34), 12, True, 'runtime-accent')
        self.cpu_value = self.runtime_label(_cpu_name(), QRect(1390, 300, 390, 46), 11, True)
        self.ram_value = self.runtime_label(_ram_name(), QRect(1390, 352, 390, 46), 11, True)
        self.gpu_value = self.runtime_label(_gpu_name(), QRect(1390, 404, 390, 58), 11, True)
        self.storage_value = self.runtime_label('Storage: waiting for target', QRect(1390, 470, 390, 46), 11, True)
        self.firmware_value = self.runtime_label(_firmware_name(), QRect(1390, 522, 390, 46), 11, True)
        for name, y in [('CPU', 300), ('RAM', 352), ('GPU', 404), ('STORAGE', 470), ('FIRMWARE', 522)]:
            self.runtime_label(name, QRect(1300, y, 88, 46), 9, True, 'runtime-accent')

        self.runtime_label('INSTALL OVERVIEW', QRect(1290, 628, 500, 34), 12, True, 'runtime-accent')
        self.runtime_label('Edition', QRect(1300, 675, 150, 34), 10, False, 'runtime-muted')
        self.edition_value = self.runtime_label('MechOS v0.3.0', QRect(1470, 675, 320, 34), 10, True)
        self.runtime_label('Target Drive', QRect(1300, 715, 150, 34), 10, False, 'runtime-muted')
        self.overview_target = self.runtime_label('Not selected', QRect(1470, 715, 320, 34), 10, True)
        self.runtime_label('Install Type', QRect(1300, 755, 150, 34), 10, False, 'runtime-muted')
        self.overview_mode = self.runtime_label('Clean Install', QRect(1470, 755, 320, 34), 10, True)
        self.runtime_label('Status', QRect(1300, 795, 150, 34), 10, False, 'runtime-muted')
        self.overview_status = self.runtime_label('Ready to install', QRect(1470, 795, 320, 34), 10, True)

        self.progress = self.reg(QProgressBar(), QRect(1300, 842, 500, 44), 10)
        self.progress.setRange(0, 100)
        self.progress.setValue(0)
        self.progress.setFormat('Ready to install')
        self.progress.valueChanged.connect(self._progress_changed)

        release = _release_name()
        self.runtime_label('MECHOS LIVE ENVIRONMENT', QRect(72, 970, 320, 28), 9, True, 'runtime-accent')
        self.runtime_label(f'Version {release}', QRect(72, 1000, 410, 28), 9, False, 'runtime-muted')

        self.set_mode('clean')

    def _progress_changed(self, value):
        if value >= 100:
            self.overview_status.setText('Installation complete')
        elif value > 0:
            self.overview_status.setText('Installing MechOS')
        else:
            self.overview_status.setText('Ready to install')

    def set_mode(self, mode):
        names = {
            'clean': 'Clean Install',
            'keep': 'Keep Personal Data',
            'custom': 'Custom Install',
            'alongside': 'Install Alongside Existing OS',
        }
        for key, button in self.mode_buttons.items():
            button.setChecked(key == mode)
        self.overview_mode.setText(names.get(mode, mode))

    def set_drive(self, path='', model='', size=''):
        self.current_path = str(path or '')
        self.current_model = str(model or '').strip()
        self.current_size = str(size or '').strip()
        if path:
            display = self.current_model or 'Selected drive'
            self.drive_title.setText(display)
            detail = self.current_size or 'Size unavailable'
            if 'vbox' in display.lower() or _run('systemd-detect-virt') not in ('', 'none', 'unknown'):
                detail += ' • virtual/test storage'
            self.drive_detail.setText(detail)
            self.drive_path.setText(str(path))
            self.storage_value.setText(_one_line(f'{display} {self.current_size} {path}', 46))
            self.overview_target.setText(_one_line(f'{display} {self.current_size}', 34))
        else:
            self.drive_title.setText('No drive selected')
            self.drive_detail.setText('Choose the drive MechOS should install to.')
            self.drive_path.setText('')
            self.storage_value.setText('Storage: waiting for target')
            self.overview_target.setText('Not selected')

    def paint_background(self, painter: QPainter):
        target = self.scale_rect(QRect(0, 0, BASE_W, BASE_H))
        painter.fillRect(target, QColor('#030711'))
        if not self.reference.isNull():
            painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, True)
            painter.drawPixmap(target, self.reference)
        else:
            painter.setPen(QColor('#eef5ff'))
            painter.drawText(target, Qt.AlignmentFlag.AlignCenter, 'Approved MechOS installer reference artwork is missing')
            return

        # Mask all demo/reference-only interactive-looking content. The center
        # workspace is intentionally widened to the real right-column boundary
        # and extended through the old baked cards so no non-operational image
        # control is left looking clickable behind the real Qt widgets.
        self.panel(painter, QRect(400, 285, 870, 620), '#07101c', '#263a59', 16, 1)
        self.panel(painter, QRect(1270, 225, 560, 385), '#07101c', '#263a59', 16, 1)
        self.panel(painter, QRect(1270, 615, 560, 290), '#07101c', '#263a59', 16, 1)
        self.panel(painter, QRect(1260, 916, 630, 122), '#07101c', '#263a59', 16, 1)
        # Remove the baked bottom-center/back control from the reference image;
        # it has no runtime action and must not appear interactive.
        self.panel(painter, QRect(548, 916, 712, 122), '#030711', '#030711', 0, 0)
        self.panel(painter, QRect(48, 952, 500, 86), '#07101c', '#1f3554', 12, 1)