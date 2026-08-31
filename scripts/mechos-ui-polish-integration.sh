#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ROOTFS_ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS UI] %s\n' "$*"; }
fail() { printf '[MechOS UI] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS UI] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ROOTFS_ARCHIVE" ] || fail "installed-system payload archive is missing"

write_shared_theme() {
  local tree="$1"
  local theme="$tree/usr/share/mechos/theme"
  mkdir -p "$theme"
  cat > "$theme/mechos-ui.qss" <<'QSS_EOF'
/* MECHOS_VISUAL_THEME_V1
 * Shared, lightweight visual system based on the MechOS blue/purple concept UI.
 * Static QSS only: no video backgrounds, blur loops or animation timers.
 */
QMainWindow, QDialog {
  background-color:#050812;
  color:#f4f8ff;
}
QWidget {
  background-color:#070b14;
  color:#eef5ff;
  font-family:"Noto Sans", "Sans Serif";
  font-size:14px;
}
QFrame#sidebar {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #060a13,stop:1 #091427);
  border:0;
  border-right:2px solid #1769d7;
}
QFrame#top, QFrame#bottom {
  background:#070c17;
  border:1px solid #193c70;
}
QFrame#panel, QFrame#card {
  background:qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #0b1424,stop:1 #08101d);
  border:1px solid #244c7c;
  border-radius:14px;
}
QFrame#glowPanel {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #0c1526,stop:1 #130d25);
  border:2px solid #7755d9;
  border-radius:15px;
}
QLabel#title {
  color:#ffffff;
  font-size:30px;
  font-weight:900;
}
QLabel#brand, QLabel#purple {
  color:#b579ff;
  font-weight:900;
}
QLabel#section {
  color:#58c7ff;
  font-size:13px;
  font-weight:900;
}
QLabel#muted, QLabel#body, QLabel#sub {
  color:#a9b9d0;
}
QPushButton {
  color:#f5f9ff;
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #0d203c,stop:1 #151530);
  border:1px solid #286fd3;
  border-radius:10px;
  min-height:34px;
  padding:8px 14px;
  font-weight:700;
}
QPushButton:hover, QPushButton:focus {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #12315b,stop:1 #261949);
  border:2px solid #9b68ff;
  color:white;
}
QPushButton:pressed {
  background:#172b4c;
  border:2px solid #5cc8ff;
}
QPushButton:disabled {
  color:#607087;
  background:#0b101b;
  border:1px solid #243044;
}
QPushButton#primary, QPushButton#action, QPushButton#profile {
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #176de3,stop:0.52 #4b53db,stop:1 #7f35c9);
  border:1px solid #8bd7ff;
  color:white;
  font-weight:900;
}
QLineEdit, QComboBox, QSpinBox, QDoubleSpinBox, QTextEdit, QPlainTextEdit {
  color:#f5f9ff;
  background:#081221;
  border:1px solid #31567f;
  border-radius:9px;
  padding:9px;
  selection-background-color:#744fd0;
}
QLineEdit:focus, QComboBox:focus, QTextEdit:focus, QPlainTextEdit:focus {
  border:2px solid #8c63ff;
  background:#0a1628;
}
QComboBox::drop-down { border:0; width:28px; }
QComboBox QAbstractItemView {
  background:#081221;
  color:#f4f8ff;
  border:1px solid #4c56a0;
  selection-background-color:#31356c;
}
QListWidget, QTreeWidget, QTableWidget {
  background:#07111e;
  alternate-background-color:#0a1525;
  border:1px solid #25496f;
  border-radius:10px;
  outline:0;
}
QListWidget::item, QTreeWidget::item { padding:8px; border-radius:7px; }
QListWidget::item:selected, QTreeWidget::item:selected {
  background:#172f58;
  color:white;
  border:1px solid #8a66ff;
}
QTabWidget::pane {
  border:1px solid #28486c;
  border-radius:10px;
  background:#07101d;
}
QTabBar::tab {
  background:#0a1423;
  color:#9fb3ce;
  border:1px solid #243f60;
  padding:9px 15px;
  margin-right:3px;
  border-top-left-radius:8px;
  border-top-right-radius:8px;
}
QTabBar::tab:selected {
  color:white;
  background:#172a50;
  border:1px solid #795cff;
}
QProgressBar {
  color:#eef7ff;
  background:#08111e;
  border:1px solid #24496f;
  border-radius:7px;
  text-align:center;
  min-height:14px;
}
QProgressBar::chunk {
  border-radius:6px;
  background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #20a7ff,stop:1 #8a4dff);
}
QScrollBar:vertical {
  width:10px;
  background:#060b13;
  margin:2px;
}
QScrollBar::handle:vertical {
  min-height:30px;
  border-radius:5px;
  background:#31558a;
}
QScrollBar::handle:vertical:hover { background:#7555d4; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height:0; }
QToolTip {
  color:#ffffff;
  background:#111b2c;
  border:1px solid #8d66ff;
  padding:6px;
}
QMessageBox { background:#070b14; }
QMenu {
  color:#eef5ff;
  background:#081221;
  border:1px solid #344d7a;
  padding:5px;
}
QMenu::item { padding:8px 24px; border-radius:6px; }
QMenu::item:selected { background:#332b68; }
QSS_EOF
}

install_system_tools_hub() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local apps="$tree/usr/share/applications"
  mkdir -p "$bin" "$apps"

  cat > "$bin/mechos-system-tools" <<'PY_EOF'
#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication, QFrame, QGridLayout, QHBoxLayout, QLabel, QMainWindow,
    QMessageBox, QPushButton, QVBoxLayout, QWidget
)

THEME = Path("/usr/share/mechos/theme/mechos-ui.qss")
STYLE = THEME.read_text(encoding="utf-8") if THEME.is_file() else ""

TOOLS = [
    ("RECOVERY CENTER", "Restore, inspect installations, repair supported boot paths and view recovery logs.", ["/usr/local/bin/mechos-recovery-center"]),
    ("UPDATE CENTER", "Check system packages and MechOS update status with rollback-aware update support.", ["/usr/local/bin/mechos-update-center"]),
    ("DIAGNOSTICS", "Generate a detailed MechOS boot and runtime health report.", ["/usr/local/bin/mechos-boot-diagnostics"]),
    ("HARDWARE SCAN", "Inspect CPU, memory, graphics, storage, network, audio and virtualization.", ["konsole", "-e", "/usr/local/bin/mechos-hardware-scan"]),
    ("BOOT DIAGNOSTICS", "Review boot timing, slow services, SDDM, GPU and Gaming Mode handoff.", ["/usr/local/bin/mechos-boot-diagnostics"]),
    ("OPTIMIZATION REPORT", "Measure boot time, idle RAM/load, services and the largest memory consumers.", ["/usr/local/bin/mechos-optimization-report"]),
    ("REPAIR BOOT", "Open Recovery Center directly at the supported boot-repair workflow.", ["/usr/local/bin/mechos-recovery-center"]),
    ("ROLLBACK FAILED UPDATE", "Open recovery controls for a recorded failed-update rollback when available.", ["/usr/local/bin/mechos-recovery-center"]),
    ("PRESERVE HOME REINSTALL", "Open the non-destructive preserve-home reinstall guidance.", ["konsole", "-e", "/usr/local/bin/mechos-preserve-home"]),
    ("NAVIGATION TUTORIAL", "Reopen the MechScope and Creator Mode navigation tutorial at any time.", ["/usr/local/bin/mechos-tutorial"]),
]


def readable_uptime():
    try:
        seconds = int(float(Path("/proc/uptime").read_text().split()[0]))
        days, rem = divmod(seconds, 86400)
        hours, rem = divmod(rem, 3600)
        mins = rem // 60
        return f"{days}d {hours}h {mins}m" if days else f"{hours}h {mins}m"
    except Exception:
        return "Unknown"


def memory_summary():
    try:
        vals = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, value = line.split(":", 1)
            vals[key] = int(value.strip().split()[0])
        total = vals["MemTotal"] / 1024 / 1024
        avail = vals["MemAvailable"] / 1024 / 1024
        used = max(0, total - avail)
        return f"{used:.1f} / {total:.1f} GiB"
    except Exception:
        return "Unknown"


def storage_summary():
    try:
        st = os.statvfs("/")
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        used = total - free
        return f"{used/2**30:.0f} / {total/2**30:.0f} GiB"
    except Exception:
        return "Unknown"


def launch(parent, command):
    exe = command[0]
    if exe.startswith("/") and not Path(exe).exists():
        QMessageBox.warning(parent, "MechOS System Tools", f"This tool is not installed yet:\n{exe}")
        return
    if not exe.startswith("/") and shutil.which(exe) is None:
        QMessageBox.warning(parent, "MechOS System Tools", f"Required launcher is unavailable:\n{exe}")
        return
    try:
        subprocess.Popen(command, start_new_session=True)
    except Exception as exc:
        QMessageBox.warning(parent, "MechOS System Tools", str(exc))


class SystemTools(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechOS System Tools Hub")
        self.resize(1500, 900)
        self.setMinimumSize(1100, 700)
        self.setStyleSheet(STYLE)
        self.build()

    def build(self):
        root = QWidget(); self.setCentralWidget(root)
        outer = QVBoxLayout(root); outer.setContentsMargins(28,22,28,22); outer.setSpacing(16)

        header = QFrame(); header.setObjectName("glowPanel")
        h = QHBoxLayout(header); h.setContentsMargins(22,16,22,16)
        titles = QVBoxLayout()
        title = QLabel("MECHOS SYSTEM TOOLS HUB"); title.setObjectName("title")
        subtitle = QLabel("MAINTAIN  //  OPTIMIZE  //  RECOVER"); subtitle.setObjectName("section")
        titles.addWidget(title); titles.addWidget(subtitle)
        h.addLayout(titles); h.addStretch(1)
        health = QLabel("SYSTEM HEALTH  •  READY"); health.setObjectName("purple")
        h.addWidget(health)
        outer.addWidget(header)

        section = QLabel("SYSTEM TOOLS"); section.setObjectName("section"); outer.addWidget(section)
        grid = QGridLayout(); grid.setHorizontalSpacing(14); grid.setVerticalSpacing(14)
        for i, (name, description, command) in enumerate(TOOLS):
            card = QFrame(); card.setObjectName("panel")
            c = QVBoxLayout(card); c.setContentsMargins(18,16,18,16); c.setSpacing(10)
            n = QLabel(name); n.setStyleSheet("font-size:17px;font-weight:900;color:#ffffff;background:transparent")
            d = QLabel(description); d.setObjectName("muted"); d.setWordWrap(True)
            b = QPushButton("OPEN"); b.setObjectName("action")
            b.clicked.connect(lambda _, cmd=command: launch(self, cmd))
            c.addWidget(n); c.addWidget(d,1); c.addWidget(b)
            grid.addWidget(card, i//5, i%5)
        outer.addLayout(grid, 1)

        info = QFrame(); info.setObjectName("panel")
        il = QHBoxLayout(info); il.setContentsMargins(18,12,18,12)
        for heading, value in (
            ("SYSTEM UPTIME", readable_uptime()),
            ("MEMORY USED", memory_summary()),
            ("ROOT STORAGE", storage_summary()),
            ("GAMING MODE", "MechScope 2.0"),
        ):
            box = QVBoxLayout()
            label = QLabel(heading); label.setObjectName("section")
            val = QLabel(value); val.setStyleSheet("font-weight:800;color:#f7fbff;background:transparent")
            box.addWidget(label); box.addWidget(val)
            il.addLayout(box); il.addStretch(1)
        outer.addWidget(info)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setApplicationName("MechOS System Tools")
    win = SystemTools(); win.showMaximized()
    raise SystemExit(app.exec())
PY_EOF
  chmod 755 "$bin/mechos-system-tools"

  cat > "$apps/mechos-system-tools.desktop" <<'DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=MechOS System Tools
Comment=Recovery, updates, diagnostics and optimization tools
Exec=/usr/local/bin/mechos-system-tools
Icon=preferences-system
Terminal=false
Categories=System;Settings;
DESKTOP_EOF
}

patch_pyqt_apps() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  [ -d "$bin" ] || return 0

  while IFS= read -r -d '' file; do
    grep -q 'PyQt6' "$file" || continue
    python3 - "$file" <<'PY_PATCH'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_VISUAL_THEME_V1"
if marker in text:
    raise SystemExit(0)

expr = "(__import__('pathlib').Path('/usr/share/mechos/theme/mechos-ui.qss').read_text(encoding='utf-8') if __import__('pathlib').Path('/usr/share/mechos/theme/mechos-ui.qss').is_file() else '')"
changed = False

if "self.setStyleSheet(STYLE)" in text:
    text = text.replace("self.setStyleSheet(STYLE)", f"self.setStyleSheet(STYLE + {expr})")
    changed = True

# Some generated MechOS tools use an inline triple-quoted stylesheet rather
# than a STYLE constant (notably Performance Center). Append the shared theme
# to those window styles without replacing their existing tool-specific rules.
if not changed:
    pattern = re.compile(r'self\.setStyleSheet\((""".*?""")\)', re.S)
    m = pattern.search(text)
    if m:
        replacement = f"self.setStyleSheet({m.group(1)} + {expr})"
        text = text[:m.start()] + replacement + text[m.end():]
        changed = True

if not changed:
    raise SystemExit(0)

lines = text.splitlines(True)
insert_at = 1 if lines and lines[0].startswith("#!") else 0
lines.insert(insert_at, marker + "\n")
text = "".join(lines)

# Give the first-run setup the same product title used by the target visual.
text = text.replace("MECHOS • FIRST SYSTEM SETUP", "MECHOS SETUP  //  FIRST RUN")

# Surface the real System Tools Hub beside Performance Center anywhere a
# MechOS action list already exposes the performance tool.
if '"/usr/local/bin/mechos-system-tools"' not in text:
    anchor = re.compile(r'(?m)^(\s*)\("Performance Center",\s*\["/usr/local/bin/mechos-performance-center"\]\),\s*$')
    text = anchor.sub(lambda m: m.group(0) + "\n" + m.group(1) + '("System Tools", ["/usr/local/bin/mechos-system-tools"]),', text)

path.write_text(text, encoding="utf-8")
PY_PATCH
    python3 -m py_compile "$file"
  done < <(find "$bin" -maxdepth 1 -type f -print0)
}

patch_tree() {
  local tree="$1"
  write_shared_theme "$tree"
  install_system_tools_hub "$tree"
  patch_pyqt_apps "$tree"
  python3 -m py_compile "$tree/usr/local/bin/mechos-system-tools"
}

# Polish the Live-side graphical tools that remain in the ISO.
patch_tree "$ROOT"

# Polish the installed-system payload as well. Creator Mode and several other
# post-install-only tools have already been removed from Live by this phase, so
# the installed archive is the authoritative copy for those interfaces.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tar --zstd -xf "$ROOTFS_ARCHIVE" -C "$tmp"
patch_tree "$tmp"
new_archive="$ROOTFS_ARCHIVE.ui-new"
tar --zstd -cpf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ROOTFS_ARCHIVE"
rm -rf "$tmp"
trap - EXIT

# Build-time assertions for the major real screens represented by the UI set.
[ -s "$ROOT/usr/share/mechos/theme/mechos-ui.qss" ] || fail "shared Live UI theme is missing"
[ -x "$ROOT/usr/local/bin/mechos-system-tools" ] || fail "Live System Tools Hub is missing"
tar --zstd -tf "$ROOTFS_ARCHIVE" './usr/share/mechos/theme/mechos-ui.qss' >/dev/null || fail "installed payload lost shared UI theme"
tar --zstd -tf "$ROOTFS_ARCHIVE" './usr/local/bin/mechos-system-tools' >/dev/null || fail "installed payload lost System Tools Hub"

if [ -f "$ROOT/usr/local/bin/mechscope" ]; then
  grep -q 'MECHOS_VISUAL_THEME_V1' "$ROOT/usr/local/bin/mechscope" || fail "MechScope did not receive the shared visual theme"
fi

log "UI polish v1 applied: shared neon theme, real System Tools Hub and functional PyQt screen styling"
