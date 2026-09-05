#!/usr/bin/env bash
set -Eeuo pipefail
TREE="${1:-/}"
TREE="${TREE%/}"
[ -n "$TREE" ] || TREE=""

fail(){ printf '[MechOS Pre-OOBE Update Auth Runtime] ERROR: %s\n' "$*" >&2; exit 1; }

owner_file(){
  local public="$TREE/usr/local/bin/mechos-update-center"
  local libexec="$TREE/usr/local/libexec/mechos-update-center-v5.py"
  if [ -f "$public" ] && grep -Fq 'class UpdateCenter(' "$public"; then printf '%s\n' "$public"; return 0; fi
  if [ -f "$public.real" ] && grep -Fq 'class UpdateCenter(' "$public.real"; then printf '%s\n' "$public.real"; return 0; fi
  if [ -f "$libexec" ] && grep -Fq 'class UpdateCenter(' "$libexec"; then printf '%s\n' "$libexec"; return 0; fi
  return 1
}

owner="$(owner_file)" || fail "Update Center owner missing under ${TREE:-/}"
mkdir -p "$TREE/usr/local/libexec" "$TREE/etc/polkit-1/rules.d"

cat > "$TREE/usr/local/libexec/mechos-firstboot-update-apply" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE=/var/lib/mechos
[ "$(id -u)" -eq 0 ] || { echo 'Root privileges required.' >&2; exit 1; }
[ -e "$STATE/installed" ] || { echo 'Installed-system marker is missing.' >&2; exit 2; }
[ ! -e "$STATE/oobe-complete" ] || { echo 'First-run setup is already complete.' >&2; exit 3; }
caller_uid="${PKEXEC_UID:-}"
[ -n "$caller_uid" ] || { echo 'This helper may only be launched through PolicyKit.' >&2; exit 4; }
caller="$(getent passwd "$caller_uid" | cut -d: -f1)"
[ "$caller" = mechos-setup ] || { echo 'Only the temporary MechOS setup account may use this helper.' >&2; exit 5; }
exec /usr/local/bin/mechos-update-helper apply
EOF
chmod 0755 "$TREE/usr/local/libexec/mechos-firstboot-update-apply"

cat > "$TREE/etc/polkit-1/rules.d/50-mechos-firstboot-update.rules" <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        subject.user == "mechos-setup" &&
        action.lookup("program") == "/usr/local/libexec/mechos-firstboot-update-apply") {
        return polkit.Result.YES;
    }
});
EOF
chmod 0644 "$TREE/etc/polkit-1/rules.d/50-mechos-firstboot-update.rules"

python3 - "$owner" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_PREOOBE_UPDATE_AUTH_V1'
if marker in t:
    raise SystemExit(0)
old='''        if privileged:\n            program = "pkexec"\n            pargs = [HELPER] + args\n        else:\n            program = HELPER\n            pargs = args\n'''
new='''        # MECHOS_PREOOBE_UPDATE_AUTH_V1\n        if privileged:\n            program = "pkexec"\n            _uid = __import__("os").getuid()\n            _user = __import__("pwd").getpwuid(_uid).pw_name\n            _state = __import__("pathlib").Path("/var/lib/mechos")\n            _pre_oobe = (_state / "installed").exists() and not (_state / "oobe-complete").exists()\n            if _user == "mechos-setup" and _pre_oobe and args == ["apply"]:\n                pargs = ["/usr/local/libexec/mechos-firstboot-update-apply"]\n            else:\n                pargs = [HELPER] + args\n        else:\n            program = HELPER\n            pargs = args\n'''
if old not in t:
    raise SystemExit('[MechOS Pre-OOBE Update Auth Runtime] privileged launch block missing')
t=t.replace(old,new,1)
compile(t,str(p),'exec'); p.write_text(t,encoding='utf-8')
PY
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$owner"
grep -Fq 'MECHOS_PREOOBE_UPDATE_AUTH_V1' "$owner"
echo '[MechOS Pre-OOBE Update Auth Runtime] guarded firstboot updater authorization installed'
