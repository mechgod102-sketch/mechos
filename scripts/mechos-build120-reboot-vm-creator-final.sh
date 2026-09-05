#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/workspace/archlive/airootfs
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
REBOOT=/workspace/scripts/mechos-reboot-hotfix6.sh
CANVAS=/workspace/src/mechos_ui/fixed_canvas.py

log(){ printf '[MechOS Build 120 Reboot + VM Creator] %s\n' "$*"; }
fail(){ printf '[MechOS Build 120 Reboot + VM Creator] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail 'Live rootfs missing'
[ -s "$ARCHIVE" ] || fail 'installed payload missing'
[ -f "$REBOOT" ] || fail 'Hotfix 6 reboot helper missing'
[ -f "$CANVAS" ] || fail 'source-owned fixed canvas missing'
bash -n "$REBOOT" || fail 'reboot helper syntax failed'
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$CANVAS" || fail 'fixed canvas syntax failed'
grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V3' "$CANVAS" || fail 'VM geometry V3 missing'
if grep -Fq 'loginctl reboot' "$REBOOT"; then fail 'invalid legacy reboot path present'; fi

owner_file(){
  local tree="$1" candidate
  for candidate in \
    "$tree/usr/local/bin/mechos-update-center" \
    "$tree/usr/local/bin/mechos-update-center.real" \
    "$tree/usr/local/libexec/mechos-update-center-v5.py"; do
    if [ -f "$candidate" ] && grep -Fq 'class UpdateCenter(' "$candidate"; then
      printf '%s\n' "$candidate"; return 0
    fi
  done
  return 1
}

patch_update_reboot(){
  local tree="$1" owner
  owner="$(owner_file "$tree")" || fail "Update Center owner missing in $tree"
  python3 - "$owner" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
cls=t.find('class UpdateCenter(')
start=t.find('    def reboot(self):',cls)
if start < 0: raise SystemExit('[Build 120] UpdateCenter.reboot missing')
end=t.find('\n    def ',start+8)
if end < 0: end=t.find('\ndef main():',start)
if end < 0: raise SystemExit('[Build 120] UpdateCenter.reboot end missing')
new='''    def reboot(self):\n        # MECHOS_HOTFIX6_REBOOT_V2\n        response = QMessageBox.question(\n            self, "Restart MechOS",\n            "Restart now to finish applying system updates?"\n        )\n        if response != QMessageBox.StandardButton.Yes:\n            return\n        try:\n            result = subprocess.run(\n                ["/usr/local/bin/mechos-reboot"],\n                text=True,\n                stdout=subprocess.PIPE,\n                stderr=subprocess.STDOUT,\n                timeout=12,\n            )\n            if result.returncode != 0:\n                detail=(result.stdout or "").strip().splitlines()[-4:]\n                message="\\n".join(detail) or "The reboot helper returned an error."\n                QMessageBox.critical(\n                    self, "Restart MechOS",\n                    message + "\\n\\nLog: ~/.local/state/mechos/reboot.log"\n                )\n        except subprocess.TimeoutExpired:\n            QMessageBox.critical(\n                self, "Restart MechOS",\n                "The reboot request timed out.\\n\\nLog: ~/.local/state/mechos/reboot.log"\n            )\n        except Exception as exc:\n            QMessageBox.critical(self, "Restart MechOS", f"Restart failed: {exc}")\n'''
t=t[:start]+new+t[end:]
compile(t,str(p),'exec')
p.write_text(t,encoding='utf-8')
PY
  chmod 0755 "$owner"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$owner" || fail "Update Center Python validation failed in $tree"
  grep -Fq 'MECHOS_HOTFIX6_REBOOT_V2' "$owner" || fail "Update Center reboot V2 missing in $tree"
}

install_tree(){
  local tree="$1"
  mkdir -p "$tree/usr/local/bin" "$tree/usr/local/share/mechos/ui"
  install -m 0755 "$REBOOT" "$tree/usr/local/bin/mechos-reboot"
  install -m 0644 "$CANVAS" "$tree/usr/local/share/mechos/ui/fixed_canvas.py"
  bash -n "$tree/usr/local/bin/mechos-reboot" || fail "reboot helper syntax failed in $tree"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$tree/usr/local/share/mechos/ui/fixed_canvas.py" || fail "canvas syntax failed in $tree"
  grep -Fq 'MECHOS_VM_RESPONSIVE_GEOMETRY_V3' "$tree/usr/local/share/mechos/ui/fixed_canvas.py" || fail "VM geometry V3 missing in $tree"
  grep -Fq 'compact_label = s < 0.72' "$tree/usr/local/share/mechos/ui/fixed_canvas.py" || fail "compact VM labels missing in $tree"
  patch_update_reboot "$tree"
}

install_tree "$ROOT"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$tmp"
install_tree "$tmp"
replacement="$ARCHIVE.build120-reboot-vm-creator"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"; trap - EXIT

log 'Update Center restart now uses KDE/logind reboot authority and low-resolution VM system surfaces compact short controls/status labels before ISO creation'
