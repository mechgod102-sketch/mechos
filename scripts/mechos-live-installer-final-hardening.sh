#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_LIVE_INSTALLER_FINAL_HARDENING_V1

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
LIBEXEC="$ROOT/usr/local/libexec"
PROFILE="/workspace/archlive/profiledef.sh"

log(){ printf '[MechOS Live Installer Final] %s\n' "$*"; }
fail(){ printf '[MechOS Live Installer Final] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Live Installer Final] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing"
[ -x "$BIN/mechos-native-install" ] || fail "native installer launcher is missing"
[ -x "$LIBEXEC/mechos-native-install-helper" ] || fail "native installer helper is missing"
[ -x "$BIN/mechos-live-update-keep-home" ] || fail "Keep Home updater is missing"

LIVE_PY="$BIN/mechos-live-setup"
[ -f "$LIBEXEC/mechos-live-setup-v5.py" ] && LIVE_PY="$LIBEXEC/mechos-live-setup-v5.py"
[ -f "$LIVE_PY" ] || fail "Live installer Python implementation is missing"

# ---------------------------------------------------------------------------
# Final graphical installer behavior.
# - Never preselect a destructive target.
# - Clean Install accepts a whole disk only.
# - Keep Home launches without an interactive sudo prompt.
# - Unsupported Custom/Alongside modes fail closed instead of routing into the
#   wrong backend.
# ---------------------------------------------------------------------------
python3 - "$LIVE_PY" <<'PY'
from pathlib import Path
import re
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_LIVE_INSTALLER_FINAL_HARDENING_V1'

# Force an explicit target selection on every installer launch. A stale file in
# /tmp must not silently restore an old destructive target.
pattern=re.compile(
    r"self\.selected_disk=self\.disks\[0\]\[0\] if self\.disks else ''\n"
    r"\s*self\.selected_size=self\.disks\[0\]\[1\] if self\.disks else ''\n"
    r"\s*self\.selected_model=self\.disks\[0\]\[2\] if self\.disks else ''"
)
replacement=(
    "self.selected_disk=''\n"
    "        self.selected_size=''\n"
    "        self.selected_model=''\n"
    "        try:\n"
    "            self.SELECTION.unlink(missing_ok=True)\n"
    "        except Exception:\n"
    "            pass"
)
if pattern.search(text):
    text=pattern.sub(replacement,text,count=1)
elif "self.selected_disk=''" not in text:
    raise SystemExit('[MechOS Live Installer Final] could not disable automatic target selection')

if marker not in text:
    anchors=['\ndef main():','\nif __name__','\napp = QApplication','\napp=QApplication']
    class_pos=text.find('class Installer(')
    if class_pos < 0:
        raise SystemExit('[MechOS Live Installer Final] Installer class not found')
    anchor=-1
    for candidate in anchors:
        pos=text.find(candidate,class_pos)
        if pos >= 0 and (anchor < 0 or pos < anchor):
            anchor=pos
    if anchor < 0:
        raise SystemExit('[MechOS Live Installer Final] installer startup anchor not found')

    override=r'''
# MECHOS_LIVE_INSTALLER_FINAL_HARDENING_V1
def _mechos_final_install(self):
    mode=getattr(self,'install_mode','clean')

    if mode=='keep':
        # The helper performs its own sudo -n elevation. Launching sudo from
        # Konsole directly can display a password prompt on a broken Live image.
        subprocess.Popen(['konsole','-e','/usr/local/bin/mechos-live-update-keep-home'])
        return

    if mode=='custom':
        QMessageBox.information(
            self,'Custom Install',
            'Custom Install is temporarily disabled in this hardware-test build.\n\n'
            'The previous path could be misrouted into Keep Home. Use Clean Install '
            'for a whole-disk installation or Keep Personal Data for an existing MechOS system.'
        )
        return

    if mode=='alongside':
        QMessageBox.information(
            self,'Install Alongside',
            'Install Alongside is temporarily disabled in this hardware-test build.\n\n'
            'The previous compatibility route could open the wrong installer backend. '
            'No partitions have been changed.'
        )
        return

    disk=str(getattr(self,'selected_disk','') or '')
    if not disk:
        QMessageBox.warning(self,'MechOS Installer','Select a whole target disk before starting Clean Install.')
        return

    try:
        dtype=subprocess.check_output(
            ['lsblk','-dno','TYPE',disk], text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        dtype=''
    if dtype!='disk':
        QMessageBox.warning(
            self,'MechOS Installer',
            'Clean Install requires a whole disk, not an individual partition.\n\n'
            'Choose the complete target drive with Change Drive. No changes were made.'
        )
        return

    self.sync_selection_from_disk()
    subprocess.Popen(['/usr/local/bin/mechos-native-install'])

Installer.install=_mechos_final_install
'''
    text=text[:anchor]+override+text[anchor:]

compile(text,str(path),'exec')
path.write_text(text,encoding='utf-8')
PY

# ---------------------------------------------------------------------------
# Native Clean Install privilege + network/mirror preflight.
# The mirror check happens before progress 4 / wipefs, so a disconnected Live
# session cannot erase a disk and only then discover pacstrap cannot proceed.
# ---------------------------------------------------------------------------
python3 - "$LIBEXEC/mechos-native-install-helper" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_NATIVE_INSTALL_PREFLIGHT_V1'
if marker not in text:
    anchor='progress 4 "Preparing selected disk"'
    pos=text.find(anchor)
    if pos < 0:
        raise SystemExit('[MechOS Live Installer Final] native installer destructive-work anchor not found')
    preflight=r'''# MECHOS_NATIVE_INSTALL_PREFLIGHT_V1
progress 1 "Checking network and package mirrors"
command -v pacman >/dev/null 2>&1 || fail "pacman is missing from the Live image. No disk changes were made."
command -v timeout >/dev/null 2>&1 || fail "timeout is missing from the Live image. No disk changes were made."

# pacstrap installs the base system from Arch repositories. Refresh repository
# metadata now, before wipefs/sfdisk, so offline or broken-mirror failures are
# guaranteed to happen while the selected disk is still untouched.
if ! timeout 35s pacman -Sy --noconfirm >/tmp/mechos-installer-pacman-preflight.log 2>&1; then
  fail "Network or Arch mirror preflight failed. The selected disk was NOT changed. Connect to the Internet and try again. See /tmp/mechos-installer-pacman-preflight.log."
fi
for pkg in base linux grub; do
  pacman -Si "$pkg" >/dev/null 2>&1 \
    || fail "Required package '$pkg' is unavailable after mirror refresh. The selected disk was NOT changed."
done

'''
    text=text[:pos]+preflight+text[pos:]
path.write_text(text,encoding='utf-8')
PY

# ---------------------------------------------------------------------------
# Keep Home must never open an interactive sudo password prompt in the Live
# session. If the expected passwordless Live sudo policy is broken, stop with a
# useful error instead of hanging at a password request.
# ---------------------------------------------------------------------------
python3 - "$BIN/mechos-live-update-keep-home" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
old='''if [ "$(id -u)" -ne 0 ]; then\n  command -v sudo >/dev/null 2>&1 || fail "Administrator privileges are required."\n  exec sudo "$0" "$@"\nfi'''
new='''if [ "$(id -u)" -ne 0 ]; then\n  command -v sudo >/dev/null 2>&1 || fail "Administrator privileges are required."\n  if ! sudo -n true >/dev/null 2>&1; then\n    fail "Live installer privilege setup is unavailable. No password should be required in the MechOS Live session. Reboot the Live ISO and try again."\n  fi\n  exec sudo -n "$0" "$@"\nfi'''
if old in text:
    text=text.replace(old,new,1)
elif 'exec sudo -n "$0" "$@"' not in text:
    raise SystemExit('[MechOS Live Installer Final] Keep Home elevation block not found')
path.write_text(text,encoding='utf-8')
PY

# Give a clear preflight error before QProcess starts the root helper.
python3 - "$BIN/mechos-native-install" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_NATIVE_SUDO_PREFLIGHT_V1'
if marker not in text:
    old="""        self.status.setText(f'Installing MechOS to {self.disk}. Keep this computer powered on.')\n        self.proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)\n"""
    new="""        # MECHOS_NATIVE_SUDO_PREFLIGHT_V1\n        sudo_probe=subprocess.run(['sudo','-n','true'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n        if sudo_probe.returncode != 0:\n            message=(\n                'The MechOS Live installer could not obtain administrator privileges without a password.\\n\\n'\n                'No disk changes were made. Reboot the Live ISO and try again.'\n            )\n            self.last_error=message\n            self.status.setText(message)\n            self.log.appendPlainText('PRE-FLIGHT ERROR: '+message.replace('\\n',' '))\n            QMessageBox.critical(self,'MechOS Installer',message)\n            self.close_btn.setEnabled(True)\n            return\n        self.status.setText(f'Installing MechOS to {self.disk}. Keep this computer powered on.')\n        self.proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)\n"""
    if old not in text:
        raise SystemExit('[MechOS Live Installer Final] native sudo preflight anchor not found')
    text=text.replace(old,new,1)
path.write_text(text,encoding='utf-8')
PY

# Optional source-owned UI cue: Custom remains visible for roadmap continuity,
# but the hardware-test build makes its unavailable state explicit.
UI_SHELL="$ROOT/usr/local/share/mechos/ui/installer_shell.py"
if [ -f "$UI_SHELL" ]; then
  python3 - "$UI_SHELL" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8')
text=text.replace(
    "self.mode_button('custom', 'Custom Install', 'Advanced partition/install options', QRect(914, 625, 225, 108))",
    "self.mode_button('custom', 'Custom Install', 'Temporarily unavailable in hardware test', QRect(914, 625, 225, 108))",
    1,
)
p.write_text(text,encoding='utf-8')
PY
fi

# ArchISO permissions remain authoritative even if an earlier stage omitted a
# generated helper from profiledef.sh.
if [ -f "$PROFILE" ]; then
  for path in \
    /usr/local/bin/mechos-native-install \
    /usr/local/libexec/mechos-native-install-helper \
    /usr/local/bin/mechos-live-update-keep-home; do
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="0:0:755"\n' "$path" >> "$PROFILE"
    fi
  done
fi

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$LIVE_PY" "$BIN/mechos-native-install" \
  || fail "installer Python validation failed"
[ ! -f "$UI_SHELL" ] || PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$UI_SHELL" \
  || fail "source-owned installer shell validation failed"
bash -n "$LIBEXEC/mechos-native-install-helper" || fail "native installer helper shell validation failed"
bash -n "$BIN/mechos-live-update-keep-home" || fail "Keep Home updater shell validation failed"

grep -Fq 'MECHOS_LIVE_INSTALLER_FINAL_HARDENING_V1' "$LIVE_PY" \
  || fail "final graphical installer hardening marker is missing"
grep -Fq 'MECHOS_NATIVE_INSTALL_PREFLIGHT_V1' "$LIBEXEC/mechos-native-install-helper" \
  || fail "network/mirror preflight is missing"
grep -Fq 'MECHOS_NATIVE_SUDO_PREFLIGHT_V1' "$BIN/mechos-native-install" \
  || fail "native sudo preflight is missing"
grep -Fq 'exec sudo -n "$0" "$@"' "$BIN/mechos-live-update-keep-home" \
  || fail "Keep Home can still request an interactive sudo password"
grep -Fq "self.selected_disk=''" "$LIVE_PY" \
  || fail "Clean Install still auto-selects a disk"

log "Live installer is fail-closed: explicit disk selection, whole-disk Clean Install, noninteractive sudo, pre-wipe mirror checks, and unsupported custom routes disabled"
