#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.4-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/local/share/mechos/ui" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$(dirname "$BUNDLE")"

install -m 0755 "$ROOT/scripts/mechos-hotfix-0.3.0-4-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-4-apply"
install -m 0755 "$ROOT/scripts/mechos-update-manifest-refresh-runtime.sh" \
  "$STAGE/usr/local/libexec/mechos-update-manifest-refresh-runtime"
install -m 0755 "$ROOT/scripts/mechos-preoobe-update-auth-runtime.sh" \
  "$STAGE/usr/local/libexec/mechos-preoobe-update-auth-runtime"

# These source-owned modules are loaded dynamically by the installed Creator
# and MechScope runtimes. Shipping them makes the VM geometry repair immediate
# after the Hotfix 4 reboot without replacing the user's generated app backend.
install -m 0644 "$ROOT/src/mechos_ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py"
install -m 0644 "$ROOT/src/mechos_ui/creator_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_shell.py"
install -m 0644 "$ROOT/src/mechscope/mechscope_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/mechscope_shell.py"

# Carry a canonical OOBE + cleanup runtime so machines affected by the broken
# first-boot path can always be recovered by the update itself.
python3 - "$ROOT/scripts/mechos-oobe-integration.sh" "$STAGE" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text(encoding='utf-8')
stage=Path(sys.argv[2])

def grab(start, end, out):
    i=src.find(start)
    if i < 0: raise SystemExit(f'missing OOBE source marker: {start}')
    i += len(start)
    j=src.find(end,i)
    if j < 0: raise SystemExit(f'missing OOBE end marker for {out}')
    p=stage/out
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(src[i:j].lstrip('\n'),encoding='utf-8')
    p.chmod(0o755)

grab("cat > \"$bin/mechos-oobe\" <<'PYEOF'", "\nPYEOF", Path('usr/local/bin/mechos-oobe'))
grab("cat > \"$libexec/mechos-oobe-apply\" <<'PYEOF'", "\nPYEOF", Path('usr/local/libexec/mechos-oobe-apply'))
grab("cat > \"$libexec/mechos-oobe-cleanup\" <<'EOF'", "\nEOF", Path('usr/local/libexec/mechos-oobe-cleanup'))

# Hotfix 3 restored an older OOBE helper whose permanent session name no longer
# matched current MechOS. Normalize the recovered OOBE to the canonical
# mechscope.desktop session and seed the owner's initial mode file.
apply=stage/'usr/local/libexec/mechos-oobe-apply'
t=apply.read_text(encoding='utf-8')
t=t.replace('Session=mechos-gaming.desktop','Session=mechscope.desktop')
marker='# MECHOS_HOTFIX4_OOBE_GAMING_MODE_V1'
anchor='state = Path("/var/lib/mechos"); state.mkdir(parents=True, exist_ok=True)'
if marker not in t:
    if anchor not in t: raise SystemExit('OOBE state anchor missing')
    block='''# MECHOS_HOTFIX4_OOBE_GAMING_MODE_V1\nhome = Path(pwd.getpwnam(username).pw_dir)\nmode_dir = home / ".config" / "mechos"\nmode_dir.mkdir(parents=True, exist_ok=True)\nmode_file = mode_dir / "session-mode"\nmode_file.write_text("gaming\\n")\ntry:\n    uid = pwd.getpwnam(username).pw_uid\n    gid = pwd.getpwnam(username).pw_gid\n    for item in (mode_dir.parent, mode_dir, mode_file):\n        os.chown(item, uid, gid)\nexcept Exception:\n    pass\n\n'''
    t=t.replace(anchor,block+anchor,1)
compile(t,str(apply),'exec')
apply.write_text(t,encoding='utf-8')

# Use the Hotfix 4 reboot helper after successful account creation. The helper
# reports/falls back through PolicyKit instead of silently losing a detached
# systemctl request.
oobe=stage/'usr/local/bin/mechos-oobe'
t=oobe.read_text(encoding='utf-8')
t=t.replace('subprocess.Popen(["systemctl", "reboot"])', 'subprocess.Popen(["/usr/local/bin/mechos-reboot"])')
compile(t,str(oobe),'exec')
oobe.write_text(t,encoding='utf-8')
PY

# Carry the first-run tutorial itself. Hotfix 4 supplies an independent
# autostart + the repaired MechScope/Creator wrappers during first boot.
python3 - "$ROOT/scripts/mechos-tutorial-integration.sh" "$STAGE" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text(encoding='utf-8')
stage=Path(sys.argv[2])
start="cat > \"$bin/mechos-tutorial\" <<'PYEOF'"
i=src.find(start)
if i < 0: raise SystemExit('tutorial source marker missing')
i += len(start)
j=src.find('\nPYEOF',i)
if j < 0: raise SystemExit('tutorial source end missing')
p=stage/'usr/local/bin/mechos-tutorial'
p.parent.mkdir(parents=True,exist_ok=True)
p.write_text(src[i:j].lstrip('\n'),encoding='utf-8')
p.chmod(0o755)
PY

# Make the reboot helper available as soon as the verified bundle is extracted.
# The current Update Center button itself is repaired by the boot-time apply
# service, but this helper is immediately available for a manual/system-menu
# fallback during that one transition reboot.
cat > "$STAGE/usr/local/bin/mechos-reboot" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if command -v loginctl >/dev/null 2>&1; then
  if loginctl reboot; then exit 0; fi
fi
if command -v pkexec >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  exec pkexec /usr/bin/systemctl reboot
fi
exec /usr/bin/systemctl reboot
EOF
chmod 0755 "$STAGE/usr/local/bin/mechos-reboot"

cat > "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-4.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 4 firstboot, runtime and VM UI repairs
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-4-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-4-apply
ExecStartPost=/usr/local/libexec/mechos-update-manifest-refresh-runtime
ExecStartPost=/usr/local/libexec/mechos-preoobe-update-auth-runtime

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-4.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-4.service"

bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-4-apply"
bash -n "$STAGE/usr/local/libexec/mechos-update-manifest-refresh-runtime"
bash -n "$STAGE/usr/local/libexec/mechos-preoobe-update-auth-runtime"
bash -n "$STAGE/usr/local/bin/mechos-reboot"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  "$STAGE/usr/local/bin/mechos-oobe" \
  "$STAGE/usr/local/libexec/mechos-oobe-apply" \
  "$STAGE/usr/local/bin/mechos-tutorial" \
  "$STAGE/usr/local/share/mechos/ui/fixed_canvas.py" \
  "$STAGE/usr/local/share/mechos/ui/creator_shell.py" \
  "$STAGE/usr/local/share/mechos/ui/mechscope_shell.py"
bash -n "$STAGE/usr/local/libexec/mechos-oobe-cleanup"

rm -f "$BUNDLE" "$SUM"
tar --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" > "$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.4',
  'release_name':'MechOS v0.3.0 Hotfix 4',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Repairs the post-install first-run account/tutorial handoff, prevents incorrect-user OOBE/Python launch failures, restores MechScope VM fallback and the Update Center restart action, and fixes responsive Creator/installer control geometry seen at VirtualBox resolutions. Live-installer geometry is included in the next ISO source; installed Creator/runtime repairs are delivered by this hotfix.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.4-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'Hotfix 4 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
