#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS OOBE] %s\n' "$*"; }
fail() { printf '[MechOS OOBE] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$PAYLOAD/mechos-rootfs.tar.zst" ] || fail "installed-system payload archive is missing"
[ -x "$PAYLOAD/mechos-postinstall-target" ] || fail "post-install target is missing"

install_oobe_runtime() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local libexec="$tree/usr/local/libexec"
  local apps="$tree/usr/share/applications"
  local polkit="$tree/etc/polkit-1/rules.d"
  local systemd="$tree/etc/systemd/system"
  mkdir -p "$bin" "$libexec" "$apps" "$polkit" "$systemd"

  cat > "$bin/mechos-oobe" <<'PYEOF'
#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import (
    QApplication, QComboBox, QFrame, QFormLayout, QHBoxLayout, QLabel,
    QLineEdit, QMainWindow, QMessageBox, QPushButton, QStackedWidget,
    QVBoxLayout, QWidget
)

HELPER = "/usr/local/libexec/mechos-oobe-apply"
STYLE = """
QWidget { background:#070910; color:#eef3ff; font-family:Sans Serif; }
QFrame#card { background:#0e1220; border:1px solid #433064; border-radius:18px; }
QLabel#brand { color:#b987ff; font-size:14px; font-weight:800; }
QLabel#title { color:white; font-size:30px; font-weight:900; }
QLabel#body { color:#cbd6e8; font-size:15px; }
QLineEdit,QComboBox { background:#111827; border:1px solid #46516a; border-radius:8px; padding:10px; font-size:15px; }
QPushButton { background:#171e30; border:1px solid #5f3f8f; border-radius:10px; padding:12px 20px; font-size:15px; font-weight:700; }
QPushButton#primary { background:#6d36ad; border-color:#b475ff; }
"""

COMMON_LOCALES = [
    "en_US.UTF-8", "en_GB.UTF-8", "es_ES.UTF-8", "fr_FR.UTF-8",
    "de_DE.UTF-8", "it_IT.UTF-8", "pt_BR.UTF-8", "ja_JP.UTF-8"
]
KEYMAPS = [
    ("US English", "us"), ("UK English", "gb"), ("Spanish", "es"),
    ("French", "fr"), ("German", "de"), ("Italian", "it"),
    ("Portuguese (Brazil)", "br"), ("Japanese", "jp")
]


def timezones():
    zones = []
    tab = Path("/usr/share/zoneinfo/zone.tab")
    if tab.is_file():
        for line in tab.read_text(errors="ignore").splitlines():
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 3:
                zones.append(parts[2])
    return sorted(set(zones)) or ["UTC"]


class OOBE(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Welcome to MechOS")
        self.setMinimumSize(1000, 680)
        self.setStyleSheet(STYLE)
        self.index = 0
        self.build_ui()
        self.render()

    def build_ui(self):
        root = QWidget(); self.setCentralWidget(root)
        outer = QVBoxLayout(root); outer.setContentsMargins(48,32,48,32); outer.setSpacing(18)
        brand = QLabel("MECHOS • FIRST SYSTEM SETUP"); brand.setObjectName("brand")
        outer.addWidget(brand)
        self.stack = QStackedWidget(); outer.addWidget(self.stack, 1)

        self.stack.addWidget(self.welcome_page())
        self.stack.addWidget(self.account_page())
        self.stack.addWidget(self.region_page())
        self.stack.addWidget(self.device_page())
        self.stack.addWidget(self.review_page())

        nav = QHBoxLayout()
        self.back = QPushButton("Back"); self.back.clicked.connect(self.prev_page)
        self.next = QPushButton("Next"); self.next.setObjectName("primary"); self.next.clicked.connect(self.next_page)
        nav.addWidget(self.back); nav.addStretch(1); nav.addWidget(self.next)
        outer.addLayout(nav)

    def card(self, title, body):
        frame = QFrame(); frame.setObjectName("card")
        layout = QVBoxLayout(frame); layout.setContentsMargins(38,34,38,34); layout.setSpacing(16)
        t = QLabel(title); t.setObjectName("title"); t.setWordWrap(True); layout.addWidget(t)
        b = QLabel(body); b.setObjectName("body"); b.setWordWrap(True); layout.addWidget(b)
        return frame, layout

    def welcome_page(self):
        f,l = self.card("Welcome to MechOS", "Set up the account and regional settings that will be used for this system. MechScope will not start until setup is complete.")
        note = QLabel("You will choose your username, password, timezone, language/locale, keyboard layout, and computer name. After setup MechOS will reboot once, show the navigation tutorial, then enter MechScope.")
        note.setObjectName("body"); note.setWordWrap(True); l.addWidget(note); l.addStretch(1)
        return f

    def account_page(self):
        f,l = self.card("Create your system account", "This becomes your everyday MechOS account. The password is used for administrator actions and account security.")
        form = QFormLayout(); form.setSpacing(14)
        self.username = QLineEdit(); self.username.setPlaceholderText("example: mechpilot")
        self.password = QLineEdit(); self.password.setEchoMode(QLineEdit.EchoMode.Password)
        self.confirm = QLineEdit(); self.confirm.setEchoMode(QLineEdit.EchoMode.Password)
        form.addRow("Username", self.username); form.addRow("Password", self.password); form.addRow("Confirm password", self.confirm)
        l.addLayout(form); l.addStretch(1); return f

    def region_page(self):
        f,l = self.card("Region and time", "Choose the timezone and language/locale used by the installed system.")
        form = QFormLayout(); form.setSpacing(14)
        self.zone = QComboBox(); self.zone.setEditable(True); self.zone.addItems(timezones())
        try:
            self.zone.setCurrentText(Path("/etc/timezone").read_text().strip())
        except Exception:
            self.zone.setCurrentText("America/New_York")
        self.locale = QComboBox(); self.locale.addItems(COMMON_LOCALES); self.locale.setCurrentText("en_US.UTF-8")
        form.addRow("Timezone", self.zone); form.addRow("Language / locale", self.locale)
        l.addLayout(form); l.addStretch(1); return f

    def device_page(self):
        f,l = self.card("Keyboard and device name", "Choose the keyboard layout and the name this computer uses on your local network.")
        form = QFormLayout(); form.setSpacing(14)
        self.keyboard = QComboBox()
        for label, code in KEYMAPS: self.keyboard.addItem(label, code)
        self.hostname = QLineEdit("mechos"); self.hostname.setPlaceholderText("example: gaming-rig")
        form.addRow("Keyboard layout", self.keyboard); form.addRow("Computer name", self.hostname)
        l.addLayout(form); l.addStretch(1); return f

    def review_page(self):
        f,l = self.card("Ready to finish setup", "Review your selections. No password is displayed on this page.")
        self.review = QLabel(); self.review.setObjectName("body"); self.review.setWordWrap(True); l.addWidget(self.review); l.addStretch(1)
        return f

    def validate_account(self):
        name = self.username.text().strip()
        if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", name):
            QMessageBox.warning(self, "Account", "Use a lowercase username beginning with a letter or underscore. Letters, numbers, _ and - are allowed.")
            return False
        if len(self.password.text()) < 8:
            QMessageBox.warning(self, "Account", "Use a password with at least 8 characters.")
            return False
        if self.password.text() != self.confirm.text():
            QMessageBox.warning(self, "Account", "The passwords do not match.")
            return False
        return True

    def validate_device(self):
        host = self.hostname.text().strip().lower()
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", host) or host.endswith("-"):
            QMessageBox.warning(self, "Computer name", "Use letters, numbers and hyphens only, without a trailing hyphen.")
            return False
        return True

    def render(self):
        self.stack.setCurrentIndex(self.index)
        self.back.setEnabled(self.index > 0)
        self.next.setText("Finish setup" if self.index == self.stack.count()-1 else "Next")
        if self.index == self.stack.count()-1:
            self.review.setText(
                f"Username: <b>{self.username.text().strip()}</b><br>"
                f"Timezone: <b>{self.zone.currentText().strip()}</b><br>"
                f"Locale: <b>{self.locale.currentText()}</b><br>"
                f"Keyboard: <b>{self.keyboard.currentText()}</b><br>"
                f"Computer name: <b>{self.hostname.text().strip().lower()}</b><br><br>"
                "Finishing setup will configure the account, switch the next login to MechScope, and reboot the system."
            )

    def prev_page(self):
        if self.index > 0:
            self.index -= 1; self.render()

    def next_page(self):
        if self.index == 1 and not self.validate_account(): return
        if self.index == 3 and not self.validate_device(): return
        if self.index < self.stack.count()-1:
            self.index += 1; self.render(); return
        self.apply()

    def apply(self):
        if not self.validate_account() or not self.validate_device(): return
        payload = {
            "username": self.username.text().strip(),
            "password": self.password.text(),
            "timezone": self.zone.currentText().strip(),
            "locale": self.locale.currentText(),
            "keyboard": self.keyboard.currentData(),
            "hostname": self.hostname.text().strip().lower(),
        }
        self.next.setEnabled(False); self.back.setEnabled(False)
        try:
            proc = subprocess.run(["pkexec", HELPER], input=json.dumps(payload), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
        except Exception as exc:
            QMessageBox.critical(self, "MechOS Setup", f"Setup could not start: {exc}")
            self.next.setEnabled(True); self.back.setEnabled(True); return
        if proc.returncode != 0:
            msg = (proc.stderr or proc.stdout or "Unknown setup error").strip()
            QMessageBox.critical(self, "MechOS Setup", msg[-2000:])
            self.next.setEnabled(True); self.back.setEnabled(True); return
        QMessageBox.information(self, "MechOS Setup", "Setup is complete. MechOS will reboot into your account and show the navigation tutorial before MechScope.")
        subprocess.Popen(["systemctl", "reboot"])

    def closeEvent(self, event):
        if not Path("/var/lib/mechos/oobe-complete").exists():
            event.ignore()
            QMessageBox.information(self, "MechOS Setup", "Finish system setup before entering MechScope.")
        else:
            event.accept()


def main():
    if Path("/var/lib/mechos/oobe-complete").exists():
        return 0
    app = QApplication(sys.argv); app.setApplicationName("MechOS First Setup")
    w = OOBE(); w.showMaximized(); return app.exec()

if __name__ == "__main__":
    raise SystemExit(main())
PYEOF
  chmod 755 "$bin/mechos-oobe"

  cat > "$libexec/mechos-oobe-apply" <<'PYEOF'
#!/usr/bin/env python3
import json
import os
import pwd
import re
import shutil
import subprocess
import sys
from pathlib import Path

if os.geteuid() != 0:
    raise SystemExit("Administrator privileges are required.")

try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit("Invalid setup data.")

username = str(data.get("username", "")).strip()
password = str(data.get("password", ""))
timezone = str(data.get("timezone", "")).strip()
locale = str(data.get("locale", "")).strip()
keyboard = str(data.get("keyboard", "")).strip()
hostname = str(data.get("hostname", "")).strip().lower()

if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", username): raise SystemExit("Invalid username.")
if username in {"root", "mechos-setup", "nobody"}: raise SystemExit("That username is reserved.")
if len(password) < 8: raise SystemExit("Password must contain at least 8 characters.")
if not re.fullmatch(r"[A-Za-z0-9_+.-]+/[A-Za-z0-9_+./-]+|UTC", timezone): raise SystemExit("Invalid timezone.")
zone = Path("/usr/share/zoneinfo") / timezone
if not zone.is_file(): raise SystemExit("Selected timezone is unavailable.")
if not re.fullmatch(r"[A-Za-z_]+\.UTF-8", locale): raise SystemExit("Invalid locale.")
if keyboard not in {"us","gb","es","fr","de","it","br","jp"}: raise SystemExit("Invalid keyboard layout.")
if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", hostname) or hostname.endswith("-"): raise SystemExit("Invalid computer name.")

candidate_file = Path("/var/lib/mechos/installer-user")
candidate = candidate_file.read_text().strip() if candidate_file.is_file() else ""

def user_exists(name):
    try: pwd.getpwnam(name); return True
    except KeyError: return False

def group_exists(name):
    return subprocess.run(["getent", "group", name], stdout=subprocess.DEVNULL).returncode == 0

supp = [g for g in ("wheel","video","audio","input","storage","optical") if group_exists(g)]

if candidate and candidate not in {"root","mechos-setup","nobody"} and user_exists(candidate):
    if username != candidate:
        if user_exists(username): raise SystemExit("The requested username already exists.")
        old_group = group_exists(candidate)
        subprocess.run(["usermod", "-l", username, candidate], check=True)
        if old_group:
            subprocess.run(["groupmod", "-n", username, candidate], check=True)
        subprocess.run(["usermod", "-d", f"/home/{username}", "-m", username], check=True)
else:
    if user_exists(username): raise SystemExit("The requested username already exists.")
    cmd = ["useradd", "-m", "-s", "/bin/bash"]
    if supp: cmd += ["-G", ",".join(supp)]
    cmd += [username]
    subprocess.run(cmd, check=True)

if supp:
    subprocess.run(["usermod", "-aG", ",".join(supp), username], check=True)
subprocess.run(["chpasswd"], input=f"{username}:{password}\n", text=True, check=True)

Path("/etc/localtime").unlink(missing_ok=True)
Path("/etc/localtime").symlink_to(zone)
subprocess.run(["hwclock", "--systohc"], check=False)

locale_gen = Path("/etc/locale.gen")
if locale_gen.is_file():
    lines = locale_gen.read_text(errors="ignore").splitlines()
    wanted = f"{locale} UTF-8"
    found = False; out = []
    for line in lines:
        stripped = line.lstrip("#").strip()
        if stripped == wanted:
            out.append(wanted); found = True
        else:
            out.append(line)
    if not found: out.append(wanted)
    locale_gen.write_text("\n".join(out) + "\n")
    subprocess.run(["locale-gen"], check=True)
Path("/etc/locale.conf").write_text(f"LANG={locale}\n")
Path("/etc/vconsole.conf").write_text(f"KEYMAP={keyboard}\n")
subprocess.run(["localectl", "set-x11-keymap", keyboard], check=False)
Path("/etc/hostname").write_text(hostname + "\n")
subprocess.run(["hostnamectl", "set-hostname", hostname], check=False)

sddm = Path("/etc/sddm.conf.d"); sddm.mkdir(parents=True, exist_ok=True)
(sddm / "95-mechos-oobe.conf").write_text(
    "[Autologin]\n"
    f"User={username}\n"
    "Session=mechos-gaming.desktop\n"
    "Relogin=true\n"
)

state = Path("/var/lib/mechos"); state.mkdir(parents=True, exist_ok=True)
(state / "system-user").write_text(username + "\n")
(state / "oobe-complete").write_text("MechOS first system setup complete\n")
(state / "oobe-pending").unlink(missing_ok=True)

# The one-time setup account and its passwordless policy are removed on the
# next boot, after this graphical session has ended.
subprocess.run(["systemctl", "enable", "mechos-oobe-cleanup.service"], check=False)
print("MechOS first system setup complete.")
PYEOF
  chmod 755 "$libexec/mechos-oobe-apply"

  cat > "$libexec/mechos-oobe-cleanup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ -e /var/lib/mechos/oobe-complete ] || exit 0
[ -e /var/lib/mechos/oobe-cleaned ] && exit 0
if id mechos-setup >/dev/null 2>&1; then
  userdel -r mechos-setup 2>/dev/null || userdel mechos-setup 2>/dev/null || true
fi
rm -f /etc/polkit-1/rules.d/49-mechos-oobe.rules
rm -rf /home/mechos-setup
mkdir -p /var/lib/mechos
touch /var/lib/mechos/oobe-cleaned
EOF
  chmod 755 "$libexec/mechos-oobe-cleanup"

  cat > "$systemd/mechos-oobe-cleanup.service" <<'EOF'
[Unit]
Description=Remove one-time MechOS setup account
Before=sddm.service
ConditionPathExists=/var/lib/mechos/oobe-complete
ConditionPathExists=!/var/lib/mechos/oobe-cleaned

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-oobe-cleanup

[Install]
WantedBy=graphical.target
EOF

  cat > "$polkit/49-mechos-oobe.rules" <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        subject.user == "mechos-setup" &&
        action.lookup("program") == "/usr/local/libexec/mechos-oobe-apply") {
        return polkit.Result.YES;
    }
});
EOF

  cat > "$apps/mechos-oobe.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup
Comment=Create the system account and configure regional settings
Exec=/usr/local/bin/mechos-oobe
Icon=preferences-system
Terminal=false
Categories=System;Settings;
EOF
}

patch_postinstall() {
  local target="$1"
  grep -Fq '# MECHOS_OOBE_POSTINSTALL_V1' "$target" && return 0
  cat >> "$target" <<'EOF'

# MECHOS_OOBE_POSTINSTALL_V1
# The installer is complete, but MechScope must not run until the owner creates
# the final account and chooses region settings in the graphical first-run UI.
mkdir -p /var/lib/mechos
INSTALLER_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "mechos-setup" && $1 != "nobody" {print $1; exit}' /etc/passwd)"
if [ -n "$INSTALLER_USER" ]; then
  printf '%s\n' "$INSTALLER_USER" > /var/lib/mechos/installer-user
fi

if ! id mechos-setup >/dev/null 2>&1; then
  SETUP_GROUPS="$(for g in wheel video audio input storage optical; do getent group "$g" >/dev/null 2>&1 && printf '%s,' "$g"; done | sed 's/,$//')"
  if [ -n "$SETUP_GROUPS" ]; then
    useradd -m -s /bin/bash -G "$SETUP_GROUPS" mechos-setup
  else
    useradd -m -s /bin/bash mechos-setup
  fi
fi
passwd -l mechos-setup >/dev/null 2>&1 || true
mkdir -p /home/mechos-setup/.config/autostart
cat > /home/mechos-setup/.config/autostart/mechos-oobe.desktop <<'AUTOOOBE'
[Desktop Entry]
Type=Application
Name=MechOS First System Setup
Exec=/usr/local/bin/mechos-oobe
Terminal=false
X-KDE-autostart-after=panel
AUTOOOBE
chown -R mechos-setup:mechos-setup /home/mechos-setup

mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/95-mechos-oobe.conf <<'SDDMOOBE'
[Autologin]
User=mechos-setup
Session=plasma.desktop
Relogin=false
SDDMOOBE

touch /var/lib/mechos/oobe-pending
rm -f /var/lib/mechos/oobe-complete /var/lib/mechos/oobe-cleaned
systemctl enable sddm.service 2>/dev/null || true
EOF
  chmod 755 "$target"
}

# Live rootfs gets the runtime for recovery/manual testing, but no OOBE autostart
# is configured there. The authoritative first-run flow lives in install payload.
install_oobe_runtime "$ROOT"
patch_postinstall "$PAYLOAD/mechos-postinstall-target"

ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
install_oobe_runtime "$tmp"
new_archive="$ARCHIVE.oobe"
tar --zstd -cf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

if [ -f "$PROFILE" ]; then
  for path in /usr/local/bin/mechos-oobe /usr/local/libexec/mechos-oobe-apply /usr/local/libexec/mechos-oobe-cleanup; do
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="0:0:755"\n' "$path" >> "$PROFILE"
    fi
  done
fi

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$ROOT/usr/local/bin/mechos-oobe" || fail "OOBE GUI syntax validation failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$ROOT/usr/local/libexec/mechos-oobe-apply" || fail "OOBE apply helper syntax validation failed"
bash -n "$ROOT/usr/local/libexec/mechos-oobe-cleanup" || fail "OOBE cleanup syntax validation failed"
bash -n "$PAYLOAD/mechos-postinstall-target" || fail "post-install syntax failed after OOBE integration"
grep -Fq 'User=mechos-setup' "$PAYLOAD/mechos-postinstall-target" || fail "temporary setup account is not configured for first boot"
grep -Fq 'Session=plasma.desktop' "$PAYLOAD/mechos-postinstall-target" || fail "first boot is not gated to setup desktop"
grep -Fq 'oobe-complete' "$ROOT/usr/local/libexec/mechos-oobe-apply" || fail "OOBE completion marker is missing"
grep -Fq 'Session=mechos-gaming.desktop' "$ROOT/usr/local/libexec/mechos-oobe-apply" || fail "final MechScope session handoff is missing"

log "post-install account/region OOBE installed; MechScope gated until completion"
