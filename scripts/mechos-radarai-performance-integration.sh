#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
MARKER="MECHOS_RADARAI_PERFORMANCE_CENTER_V1"

log() { printf '[MechOS RadarAI integration] %s\n' "$*"; }
fail() { printf '[MechOS RadarAI integration] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || {
  log "waiting for final phase"
  exit 0
}
[ -d "$ROOT" ] || fail "ArchISO rootfs does not exist at $ROOT"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

patch_performance_center() {
  local tree="$1"
  local file="$tree/usr/local/bin/mechos-performance-center"
  [ -f "$file" ] || fail "Performance Center not found: $file"

  python3 - "$file" <<'PYEOF'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "MECHOS_RADARAI_PERFORMANCE_CENTER_V1"

if marker in text:
    raise SystemExit(0)

qt_import = "from PyQt6.QtCore import Qt\n"
qt_replacement = """from PyQt6.QtCore import Qt, QTimer

RADARAI_APP_ID = "io.mechgod.RadarAI"
# MECHOS_RADARAI_PERFORMANCE_CENTER_V1
"""
if qt_import not in text:
    raise SystemExit("RadarAI integration: PyQt6.QtCore import anchor is missing")
text = text.replace(qt_import, qt_replacement, 1)

profile_anchor = "def set_profile(profile):\n"
helpers = '''def flatpak_app_installed(app_id):
    """Return True for either a per-user or system-wide Flatpak install."""
    if not shutil.which("flatpak"):
        return False
    for scope in ("--user", "--system"):
        result = subprocess.run(
            ["flatpak", "info", scope, app_id],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return True
    return False


def launch_radarai(parent):
    if not flatpak_app_installed(RADARAI_APP_ID):
        QMessageBox.information(
            parent,
            "RadarAI",
            "RadarAI is not installed. Install io.mechgod.RadarAI from Discover, then it will appear here automatically.",
        )
        return
    run(["flatpak", "run", RADARAI_APP_ID])


'''
if profile_anchor not in text:
    raise SystemExit("RadarAI integration: power-profile function anchor is missing")
text = text.replace(profile_anchor, helpers + profile_anchor, 1)

grid_anchor = '''        for i, (label, cb) in enumerate(actions):
            b = QPushButton(label)
            b.clicked.connect(cb)
            grid.addWidget(b, i // 2, i % 2)

        v.addLayout(grid)
'''
grid_replacement = '''        for i, (label, cb) in enumerate(actions):
            b = QPushButton(label)
            b.clicked.connect(cb)
            grid.addWidget(b, i // 2, i % 2)

        self.radarai_button = QPushButton("🛡 RadarAI System Diagnostics")
        self.radarai_button.setToolTip(
            "Scan MechOS health and submit reviewed, sanitized error reports"
        )
        self.radarai_button.clicked.connect(lambda: launch_radarai(self))
        grid.addWidget(
            self.radarai_button,
            len(actions) // 2,
            len(actions) % 2,
        )

        # Detect user or system Flatpak installs without modifying the host.
        # If Discover installs RadarAI while this window is open, the button
        # becomes visible within three seconds.
        self.radarai_timer = QTimer(self)
        self.radarai_timer.timeout.connect(self.refresh_radarai)
        self.radarai_timer.start(3000)
        self.refresh_radarai()

        v.addLayout(grid)
'''
if grid_anchor not in text:
    raise SystemExit("RadarAI integration: action-grid anchor is missing")
text = text.replace(grid_anchor, grid_replacement, 1)

stretch_anchor = "        v.addStretch(1)\n\napp = QApplication(sys.argv)\n"
stretch_replacement = '''        v.addStretch(1)

    def refresh_radarai(self):
        self.radarai_button.setVisible(flatpak_app_installed(RADARAI_APP_ID))

app = QApplication(sys.argv)
'''
if stretch_anchor not in text:
    raise SystemExit("RadarAI integration: Perf class end anchor is missing")
text = text.replace(stretch_anchor, stretch_replacement, 1)

path.write_text(text, encoding="utf-8")
PYEOF

  grep -Fq "$MARKER" "$file" || fail "RadarAI marker missing from $file"
  grep -Fq 'RADARAI_APP_ID = "io.mechgod.RadarAI"' "$file"     || fail "RadarAI app ID missing from $file"
  grep -Fq 'flatpak", "run", RADARAI_APP_ID' "$file"     || fail "RadarAI launcher missing from $file"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file"
}

patch_performance_center "$ROOT"

[ -s "$ARCHIVE" ] || fail "installed-system payload archive is missing"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
patch_performance_center "$tmp"
new_archive="$ARCHIVE.radarai"
tar --zstd -cpf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

tar --zstd -xOf "$ARCHIVE" ./usr/local/bin/mechos-performance-center   | grep -Fq "$MARKER"   || fail "installed-system payload lost RadarAI integration"

log "RadarAI auto-discovery added to Live and installed Performance Center"
