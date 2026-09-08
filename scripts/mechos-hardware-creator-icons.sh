#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_HARDWARE_CREATOR_ICONS_V1

PHASE="${1:-final}"
[ "$PHASE" = final ] || exit 0

ROOT=/workspace/archlive/airootfs
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log(){ printf '[MechOS Hardware Creator Icons] %s\n' "$*"; }
fail(){ printf '[MechOS Hardware Creator Icons] ERROR: %s\n' "$*" >&2; exit 1; }

[ -s "$ARCHIVE" ] || fail 'installed-system payload missing'

STAGE="$(mktemp -d /tmp/mechos-hardware-creator-icons.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
tar --warning=no-timestamp --zstd -xpf "$ARCHIVE" -C "$STAGE"

CANVAS="$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"
[ -f "$CANVAS" ] || fail 'installed responsive FixedCanvas is missing'

python3 - "$CANVAS" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding='utf-8')
marker = 'MECHOS_CREATOR_BUTTON_ICONS_V1'
if marker in text:
    compile(text, str(p), 'exec')
    raise SystemExit(0)

replacements = [
    ('from PyQt6.QtCore import QRect, Qt', 'from PyQt6.QtCore import QRect, QSize, Qt'),
    ('from PyQt6.QtGui import QColor, QFont, QPainter, QPen', 'from PyQt6.QtGui import QColor, QFont, QIcon, QPainter, QPen'),
    ('from PyQt6.QtWidgets import QLabel, QPushButton, QWidget', 'from PyQt6.QtWidgets import QLabel, QPushButton, QStyle, QWidget'),
]
for old, new in replacements:
    if old not in text:
        raise SystemExit(f'[MechOS Creator Icons] import anchor missing: {old}')
    text = text.replace(old, new, 1)

anchor = 'BASE_W = 1920\nBASE_H = 1080\n'
icon_block = r'''
BASE_W = 1920
BASE_H = 1080

# MECHOS_CREATOR_BUTTON_ICONS_V1
# Prefer the installed KDE/Breeze icon theme, then fall back to Qt standard
# icons so Creator Mode never turns into a text-only dashboard when an app icon
# or theme alias is unavailable on a particular hardware image.
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
    'Unity Hub': (('unityhub', 'applications-development'), QStyle.StandardPixmap.SP_ComputerIcon),
    'Unreal Engine': (('unreal-engine', 'applications-development'), QStyle.StandardPixmap.SP_ComputerIcon),
    'VS Code': (('visual-studio-code', 'com.visualstudio.code', 'applications-development'), QStyle.StandardPixmap.SP_FileIcon),
    'GitKraken': (('gitkraken', 'git', 'applications-development'), QStyle.StandardPixmap.SP_FileIcon),
    'Krita': (('krita', 'applications-graphics'), QStyle.StandardPixmap.SP_FileIcon),
    'OBS Studio': (('obs', 'com.obsproject.Studio', 'camera-video'), QStyle.StandardPixmap.SP_MediaPlay),
    'Godot': (('godot', 'applications-development'), QStyle.StandardPixmap.SP_ComputerIcon),
    'VRChat Creator': (('applications-graphics', 'applications-development'), QStyle.StandardPixmap.SP_ComputerIcon),
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
'''
if anchor not in text:
    raise SystemExit('[MechOS Creator Icons] canvas size anchor missing')
text = text.replace(anchor, icon_block, 1)

button_anchor = "        q.setProperty('mechosSubtitle', subtitle)\n        q.setCursor(Qt.CursorShape.PointingHandCursor)\n"
button_insert = r'''        q.setProperty('mechosSubtitle', subtitle)
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
'''
if button_anchor not in text:
    raise SystemExit('[MechOS Creator Icons] button icon anchor missing')
text = text.replace(button_anchor, button_insert, 1)

resize_anchor = "            if isinstance(widget, QPushButton) and widget.property('role') != 'hotspot':\n                vpad = max(2, int(round(6 * s))); hpad = max(4, int(round(10 * s)))\n"
resize_insert = r'''            if isinstance(widget, QPushButton) and widget.property('role') != 'hotspot':
                icon_base = widget.property('mechosIconBase')
                if icon_base:
                    icon_px = max(12, int(round(int(icon_base) * s)))
                    widget.setIconSize(QSize(icon_px, icon_px))
                vpad = max(2, int(round(6 * s))); hpad = max(4, int(round(10 * s)))
'''
if resize_anchor not in text:
    raise SystemExit('[MechOS Creator Icons] responsive icon-size anchor missing')
text = text.replace(resize_anchor, resize_insert, 1)

compile(text, str(p), 'exec')
p.write_text(text, encoding='utf-8')
PY

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$CANVAS"
grep -Fq 'MECHOS_CREATOR_BUTTON_ICONS_V1' "$CANVAS" || fail 'Creator icon marker missing'
grep -Fq "'Blender':" "$CANVAS" || fail 'Creator app icon map missing'
grep -Fq "'Creator Mode':" "$CANVAS" || fail 'mode-bar icon map missing'
grep -Fq 'q.setIcon(icon)' "$CANVAS" || fail 'button icon assignment missing'
grep -Fq 'widget.setIconSize(QSize(icon_px, icon_px))' "$CANVAS" || fail 'responsive icon scaling missing'

mkdir -p "$STAGE/usr/share/mechos/hardware-test"
cat >"$STAGE/usr/share/mechos/hardware-test/creator-icons" <<'EOF'
MECHOS_HARDWARE_CREATOR_ICONS_V1
provider=KDE-Breeze-theme-with-Qt-standard-fallback
responsive=true
scope=Creator-Mode-buttons-and-mode-bar
EOF

if [ -f "$STAGE/etc/mechos/hardware-test-build" ]; then
    if grep -q '^creator_icons=' "$STAGE/etc/mechos/hardware-test-build"; then
        sed -i 's/^creator_icons=.*/creator_icons=MECHOS_HARDWARE_CREATOR_ICONS_V1/' "$STAGE/etc/mechos/hardware-test-build"
    else
        printf 'creator_icons=MECHOS_HARDWARE_CREATOR_ICONS_V1\n' >>"$STAGE/etc/mechos/hardware-test-build"
    fi
fi

TMP="$ARCHIVE.hardware-creator-icons"
tar --zstd -cpf "$TMP" -C "$STAGE" .
mv -f "$TMP" "$ARCHIVE"

tar --zstd -tf "$ARCHIVE" ./usr/share/mechos/hardware-test/creator-icons >/dev/null
log 'Creator Mode icon support restored with responsive scaling and Qt fallback icons'
