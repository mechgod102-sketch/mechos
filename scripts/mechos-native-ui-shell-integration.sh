#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
SOURCE="/workspace/src/mechscope/mechscope_shell.py"

log(){ printf '[MechOS Native UI Shell] %s\n' "$*"; }
fail(){ printf '[MechOS Native UI Shell] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Native UI Shell] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -f "$SOURCE" ] || fail "source-owned MechScope shell missing: $SOURCE"
[ -d "$ROOT" ] || fail "ArchISO rootfs missing: $ROOT"
[ -s "$PAYLOAD" ] || fail "installed-system payload missing: $PAYLOAD"

install_tree(){
  local tree="$1"
  local target="$tree/usr/local/share/mechos/ui/mechscope_shell.py"
  local public="$tree/usr/local/bin/mechscope"
  local impl="$public"
  [ -f "$public.real" ] && impl="$public.real"

  [ -f "$impl" ] || fail "MechScope runtime missing from $tree"
  mkdir -p "$(dirname "$target")"
  install -m 0644 "$SOURCE" "$target"

  python3 - "$impl" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_SOURCE_OWNED_SHELL_V1'
if marker in text:
    raise SystemExit(0)

cls=text.find('class MechScope(QMainWindow):')
if cls < 0:
    raise SystemExit('[MechOS Native UI Shell] MechScope class not found')

# Inject a tiny loader before the class. The build still owns runtime backends,
# but visual composition lives in src/mechscope instead of shell heredocs.
loader=r'''# MECHOS_SOURCE_OWNED_SHELL_V1
import importlib.util as _mechos_importlib_util
import sys as _mechos_sys
from pathlib import Path as _MechPath


def _mechos_load_source_shell():
    _path=_MechPath('/usr/local/share/mechos/ui/mechscope_shell.py')
    _spec=_mechos_importlib_util.spec_from_file_location('mechos_source_shell',_path)
    if _spec is None or _spec.loader is None:
        raise RuntimeError(f'Unable to load MechScope source shell: {_path}')
    _module=_mechos_importlib_util.module_from_spec(_spec)
    _mechos_sys.modules[_spec.name]=_module
    _spec.loader.exec_module(_module)
    return _module

_MECHOS_SOURCE_SHELL=_mechos_load_source_shell()

'''
text=text[:cls]+loader+text[cls:]


def replace_method(source,name,new):
    c=source.find('class MechScope(QMainWindow):')
    s=source.find('    def '+name+'(',c)
    if s < 0:
        raise SystemExit(f'[MechOS Native UI Shell] MechScope.{name} not found')
    e=source.find('\n    def ',s+8)
    if e < 0:
        raise SystemExit(f'[MechOS Native UI Shell] end of MechScope.{name} not found')
    return source[:s]+new.rstrip()+'\n'+source[e:]

build=r'''    def build_ui(self):
        # Visual authority lives in /usr/local/share/mechos/ui/mechscope_shell.py
        # and ultimately in src/mechscope/mechscope_shell.py in the repository.
        self.setWindowTitle('MechOS • MechScope 2.0')
        self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
        self.setWindowState(Qt.WindowState.WindowFullScreen)
        actions={
            'steam': self.open_steam,
            'store': self.open_store,
            'performance': lambda: spawn(['/usr/local/bin/mechos-performance-center']),
            'updates': lambda: spawn(['/usr/local/bin/mechos-update-center']),
            'drivers': lambda: spawn(['/usr/local/bin/mechos-update-center']),
            'systeminfo': lambda: spawn(['systemsettings','kcm_about-distro']),
            'network': lambda: spawn(['systemsettings','kcm_networkmanagement']),
            'gaming': lambda: None,
            'desktop': lambda: self.switch_mode('desktop'),
            'creator': lambda: self.switch_mode('creator'),
            'vr': self.open_vr,
            'recovery': lambda: spawn(['/usr/local/bin/mechos-recovery-center']),
            'shutdown': lambda: spawn(['/usr/local/bin/mechos-power-menu']) if __import__('pathlib').Path('/usr/local/bin/mechos-power-menu').exists() else spawn(['systemctl','poweroff']),
        }
        self.native_shell=_MECHOS_SOURCE_SHELL.MechScopeShell(self,actions,self)
        self.setCentralWidget(self.native_shell)
        self.cpu_gauge=self.native_shell.cpu_gauge
        self.ram_gauge=self.native_shell.ram_gauge
        self.disk_gauge=self.native_shell.disk_gauge
        self.gpu_status=self.native_shell.gpu_status
        self.temp_label=self.native_shell.temp_label
        self.net_label=self.native_shell.net_label
        self.time_label=self.native_shell.time_label
        self.pad_label=self.native_shell.pad_label
        self.stats_label=QLabel(self); self.stats_label.hide()
        self.native_shell.set_recent_games(getattr(self,'games',[]), self.launch_game)
        if getattr(self,'focusables',None):
            self.focusables[0].setFocus()
'''
text=replace_method(text,'build_ui',build)

refresh=r'''    def refresh_stats(self):
        cpu=cpu_percent(); ram=ram_percent(); disk=disk_percent()
        self.cpu_gauge.setValue(cpu); self.ram_gauge.setValue(ram); self.disk_gauge.setValue(disk)
        try:
            gpu=mechos_gpu_load_percent()
        except Exception:
            gpu=None
        gpu_text=gpu_name()
        if gpu is not None: gpu_text+=f'  •  {gpu}% load'
        self.gpu_status.setText('GPU  '+gpu_text)
        self.net_label.setText('NET  '+network_name())
        self.time_label.setText(time.strftime('%I:%M %p'))
        temp=output(['bash','-lc',"for f in /sys/class/thermal/thermal_zone*/temp; do [ -r \\"$f\\" ] || continue; v=$(cat \\"$f\\"); [ \\"$v\\" -gt 1000 ] && v=$((v/1000)); [ \\"$v\\" -gt 0 ] && [ \\"$v\\" -lt 120 ] && { echo \\"${v}°C\\"; break; }; done"])
        self.temp_label.setText('Temperature: '+(temp or 'sensor dependent'))
'''
text=replace_method(text,'refresh_stats',refresh)

# Ensure the helper used by refresh_stats exists even if an older exact-layout
# pass is no longer the authority.
if 'def mechos_gpu_load_percent():' not in text:
    helper=r'''\ndef mechos_gpu_load_percent():
    command="if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1; exit 0; fi; for f in /sys/class/drm/card*/device/gpu_busy_percent; do [ -r \\"$f\\" ] || continue; cat \\"$f\\"; exit 0; done"
    try:
        value=output(['bash','-lc',command]).strip().splitlines()[0]
        return max(0,min(100,int(float(value))))
    except Exception:
        return None
\n'''
    pos=text.find('class MechScope(QMainWindow):')
    text=text[:pos]+helper+text[pos:]

compile(text,str(path),'exec')
path.write_text(text,encoding='utf-8')
PY

  chmod 755 "$impl"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$impl" "$target" \
    || fail "source-owned UI Python validation failed in $tree"
  grep -Fq '# MECHOS_SOURCE_OWNED_SHELL_V1' "$impl" || fail "runtime did not receive source-shell marker"
  grep -Fq 'MechScopeShell' "$impl" || fail "runtime is not using source-owned MechScopeShell"
}

install_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xpf "$PAYLOAD" -C "$tmp"
install_tree "$tmp"
replacement="$PAYLOAD.native-ui"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$PAYLOAD"
rm -rf "$tmp"
trap - EXIT

log 'MechScope visual authority moved to src/mechscope; build-time layout stretching disabled'
