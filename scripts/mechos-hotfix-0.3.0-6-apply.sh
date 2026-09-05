#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/mechos
MARKER="$STATE/hotfix-0.3.0-6-applied"
LOG=/var/log/mechos-hotfix-0.3.0-6.log
mkdir -p "$STATE" /var/log
exec >>"$LOG" 2>&1

echo "[$(date -Is)] MechOS v0.3.0 Hotfix 6 apply start"
[ -e "$MARKER" ] && exit 0

is_live(){
  [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null
}
is_live && { echo "Live ISO detected; installed-system Hotfix 6 repair skipped."; exit 0; }

install_reboot_helper(){
  cat > /usr/local/bin/mechos-reboot <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
LOG="$LOG_DIR/reboot.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true
log(){ printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG" 2>/dev/null || true; }

if command -v qdbus6 >/dev/null 2>&1; then
  if qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot >>"$LOG" 2>&1; then
    log 'reboot accepted by KDE Plasma shutdown service (qdbus6)'
    exit 0
  fi
fi
if command -v qdbus >/dev/null 2>&1; then
  if qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot >>"$LOG" 2>&1; then
    log 'reboot accepted by KDE Plasma shutdown service (qdbus)'
    exit 0
  fi
fi
if command -v busctl >/dev/null 2>&1; then
  if busctl call org.freedesktop.login1 /org/freedesktop/login1 \
      org.freedesktop.login1.Manager Reboot b true >>"$LOG" 2>&1; then
    log 'reboot accepted by systemd-logind'
    exit 0
  fi
fi
if [ "$(id -u)" -eq 0 ]; then
  log 'falling back to root systemctl reboot'
  exec /usr/bin/systemctl reboot
fi
if command -v pkexec >/dev/null 2>&1; then
  log 'session-owned reboot paths failed; requesting PolicyKit systemctl reboot'
  exec pkexec /usr/bin/systemctl reboot
fi
log 'ERROR: no usable reboot mechanism is available'
echo "MechOS could not request a reboot. See $LOG" >&2
exit 1
EOF
  chmod 0755 /usr/local/bin/mechos-reboot
  bash -n /usr/local/bin/mechos-reboot
}

patch_update_center_reboot(){
  local owner=""
  for candidate in \
    /usr/local/bin/mechos-update-center \
    /usr/local/bin/mechos-update-center.real \
    /usr/local/libexec/mechos-update-center-v5.py; do
    if [ -f "$candidate" ] && grep -Fq 'class UpdateCenter(' "$candidate"; then owner="$candidate"; break; fi
  done
  [ -n "$owner" ] || { echo "Update Center owner not found; reboot helper still installed."; return 0; }

  python3 - "$owner" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
cls=t.find('class UpdateCenter(')
start=t.find('    def reboot(self):',cls)
if start < 0: raise SystemExit('[Hotfix 6] UpdateCenter.reboot missing')
end=t.find('\n    def ',start+8)
if end < 0: end=t.find('\ndef main():',start)
if end < 0: raise SystemExit('[Hotfix 6] UpdateCenter.reboot end missing')
new='''    def reboot(self):\n        # MECHOS_HOTFIX6_REBOOT_V2\n        response = QMessageBox.question(\n            self, "Restart MechOS",\n            "Restart now to finish applying system updates?"\n        )\n        if response != QMessageBox.StandardButton.Yes:\n            return\n        try:\n            result = subprocess.run(\n                ["/usr/local/bin/mechos-reboot"],\n                text=True,\n                stdout=subprocess.PIPE,\n                stderr=subprocess.STDOUT,\n                timeout=12,\n            )\n            if result.returncode != 0:\n                detail=(result.stdout or "").strip().splitlines()[-4:]\n                message="\\n".join(detail) or "The reboot helper returned an error."\n                QMessageBox.critical(\n                    self, "Restart MechOS",\n                    message + "\\n\\nLog: ~/.local/state/mechos/reboot.log"\n                )\n        except subprocess.TimeoutExpired:\n            QMessageBox.critical(\n                self, "Restart MechOS",\n                "The reboot request timed out.\\n\\nLog: ~/.local/state/mechos/reboot.log"\n            )\n        except Exception as exc:\n            QMessageBox.critical(self, "Restart MechOS", f"Restart failed: {exc}")\n'''
t=t[:start]+new+t[end:]
compile(t,str(p),'exec')
p.write_text(t,encoding='utf-8')
PY
  chmod 0755 "$owner"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$owner"
  grep -Fq 'MECHOS_HOTFIX6_REBOOT_V2' "$owner"
}

# The bundle installs the V3 source-owned canvas before this service runs.
# Verify it is actually present so the VM Creator repair cannot silently claim
# success while still using the older two-line-overlap geometry.
verify_vm_creator_runtime(){
  local canvas=/usr/local/share/mechos/ui/fixed_canvas.py
  [ -f "$canvas" ] || { echo "ERROR: source-owned fixed_canvas.py missing"; exit 31; }
  grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V3' "$canvas" || {
    echo "ERROR: VM responsive geometry V3 missing from installed canvas"; exit 32;
  }
  grep -Fq "compact = bool(subtitle)" "$canvas" || {
    echo "ERROR: compact VM button labels missing"; exit 33;
  }
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$canvas"
}

install_reboot_helper
patch_update_center_reboot
verify_vm_creator_runtime

mkdir -p /etc/mechos
printf '0.3.0-hotfix.6\n' > /etc/mechos/release
if [ -f /etc/mechos/mechos.conf ]; then
  if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
    sed -i 's/^MECHOS_VERSION=.*/MECHOS_VERSION=0.3.0-hotfix.6/' /etc/mechos/mechos.conf
  else
    printf 'MECHOS_VERSION=0.3.0-hotfix.6\n' >> /etc/mechos/mechos.conf
  fi
fi
printf 'MechOS v0.3.0 Hotfix 6\n' > /etc/system-release

touch "$MARKER"
echo "[$(date -Is)] Hotfix 6 applied: Update Center reboot uses KDE/logind authority and low-resolution VM Creator controls use compact geometry."