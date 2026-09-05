#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
HELPER="$ROOT/usr/local/libexec/mechos-native-install-helper"

log(){ printf '[MechOS Build 111 Firstboot] %s\n' "$*"; }
fail(){ printf '[MechOS Build 111 Firstboot] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Build 111 Firstboot] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -d "$ROOT" ] || fail "ArchISO rootfs missing"
[ -s "$ARCHIVE" ] || fail "installed-system payload missing"
[ -f "$HELPER" ] || fail "native installer helper missing"

# The native installer creates the temporary first-boot account before the
# installed payload ever boots. Keep that handoff deterministic: the temporary
# account has no password, is not the permanent administrator, and every XDG
# autostart path goes through the guarded OOBE launcher.
python3 - "$HELPER" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_BUILD111_FIRSTBOOT_HANDOFF_V1'
if marker not in t:
    old='arch-chroot "$MNT" passwd -l mechos-setup >/dev/null 2>&1 || true'
    new='arch-chroot "$MNT" passwd -d mechos-setup >/dev/null 2>&1 || true'
    if old not in t:
        raise SystemExit('[MechOS Build 111 Firstboot] setup-account password anchor missing')
    t=t.replace(old,new,1)

    old='Exec=/usr/local/bin/mechos-oobe\nTerminal=false\nX-KDE-autostart-after=panel'
    new='Exec=/usr/local/bin/mechos-oobe-start\nTryExec=/usr/local/bin/mechos-oobe-start\nTerminal=false\nX-KDE-autostart-after=panel'
    if old not in t:
        raise SystemExit('[MechOS Build 111 Firstboot] native OOBE autostart anchor missing')
    t=t.replace(old,new,1)

    anchor='arch-chroot "$MNT" chown -R mechos-setup:mechos-setup /home/mechos-setup\n'
    if anchor not in t:
        raise SystemExit('[MechOS Build 111 Firstboot] setup-home ownership anchor missing')
    block=r'''# MECHOS_BUILD111_FIRSTBOOT_HANDOFF_V1
# Do not show the stock KDE/Plasma session splash during first-run setup. The
# branded MechOS Plymouth splash is the boot splash; account creation should
# appear immediately when the temporary Plasma session becomes usable.
cat > "$MNT/home/mechos-setup/.config/ksplashrc" <<'KSPLASH'
[KSplash]
Engine=none
Theme=None
KSPLASH
'''
    t=t.replace(anchor,block+anchor,1)

p.write_text(t,encoding='utf-8')
PY
bash -n "$HELPER" || fail "native installer helper invalid after firstboot hotfix"

STAGE="$(mktemp -d /tmp/mechos-build111-firstboot.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$STAGE"

AUTH="$STAGE/usr/local/libexec/mechos-firstboot-authority"
START="$STAGE/usr/local/bin/mechos-oobe-start"
OOBE="$STAGE/usr/local/bin/mechos-oobe"

[ -x "$AUTH" ] || fail "firstboot authority missing from installed payload"
[ -x "$START" ] || fail "OOBE launcher missing from installed payload"
[ -x "$OOBE" ] || fail "OOBE UI missing from installed payload"

# Build 111 reached Plasma but did not reliably start account creation. Patch the
# absolute final authority emitted by the clean-build gate, then add a systemd
# --user fallback so OOBE does not depend on KDE's XDG autostart alone.
python3 - "$AUTH" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(encoding='utf-8')
marker='# MECHOS_BUILD111_OOBE_AUTHORITY_V1'
if marker not in t:
    old='passwd -l "$SETUP_USER" >/dev/null 2>&1 || true\n'
    if old not in t:
        raise SystemExit('[MechOS Build 111 Firstboot] final authority password anchor missing')
    new='''# MECHOS_BUILD111_OOBE_AUTHORITY_V1\n# SDDM first-run autologin needs a usable temporary account. It is deliberately\n# not an administrator; mechos-oobe-apply is authorized by the dedicated polkit rule.\npasswd -d "$SETUP_USER" >/dev/null 2>&1 || true\nif getent group wheel >/dev/null 2>&1; then\n  gpasswd -d "$SETUP_USER" wheel >/dev/null 2>&1 || true\nfi\n'''
    t=t.replace(old,new,1)

    old='''DESKTOP\nchown -R "$SETUP_USER:$SETUP_USER" "$home/.config"\n'''
    new='''DESKTOP\ncat > "$home/.config/ksplashrc" <<'KSPLASH'\n[KSplash]\nEngine=none\nTheme=None\nKSPLASH\nchown -R "$SETUP_USER:$SETUP_USER" "$home/.config"\n'''
    if old not in t:
        raise SystemExit('[MechOS Build 111 Firstboot] final authority autostart anchor missing')
    t=t.replace(old,new,1)

    # A failed Plasma/OOBE process must return to the greeter rather than create
    # an automatic login loop. The user service below retries only the OOBE app.
    t=t.replace('Relogin=true\nSDDM', 'Relogin=false\nSDDM', 1)

p.write_text(t,encoding='utf-8')
PY
chmod 0755 "$AUTH"
bash -n "$AUTH" || fail "firstboot authority invalid after Build 111 hotfix"

mkdir -p \
  "$STAGE/usr/lib/systemd/user" \
  "$STAGE/etc/systemd/user/default.target.wants" \
  "$STAGE/etc/systemd/user/graphical-session.target.wants" \
  "$STAGE/etc/xdg" \
  "$STAGE/etc/skel/.config"

cat > "$STAGE/usr/lib/systemd/user/mechos-oobe-autostart.service" <<'EOF'
[Unit]
Description=Launch MechOS account creation on first installed login
ConditionUser=mechos-setup
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/oobe-complete
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mechos-oobe-start
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target graphical-session.target
EOF

ln -sfn /usr/lib/systemd/user/mechos-oobe-autostart.service \
  "$STAGE/etc/systemd/user/default.target.wants/mechos-oobe-autostart.service"
ln -sfn /usr/lib/systemd/user/mechos-oobe-autostart.service \
  "$STAGE/etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service"

# The stock KDE session splash was showing after the branded boot splash. Disable
# Plasma's secondary splash system-wide and in new-user defaults so the visible
# boot branding stays MechOS and first-run account creation can take focus.
cat > "$STAGE/etc/xdg/ksplashrc" <<'EOF'
[KSplash]
Engine=none
Theme=None
EOF
cp -f "$STAGE/etc/xdg/ksplashrc" "$STAGE/etc/skel/.config/ksplashrc"
chmod 0644 \
  "$STAGE/etc/xdg/ksplashrc" \
  "$STAGE/etc/skel/.config/ksplashrc" \
  "$STAGE/usr/lib/systemd/user/mechos-oobe-autostart.service"

# Keep the MechOS Plymouth theme as the one boot splash while suppressing only
# the later KDE/Plasma session splash.
[ -f "$STAGE/usr/share/plymouth/themes/mechos/mechos.plymouth" ] \
  || fail "MechOS Plymouth theme missing from installed payload"
grep -Fq 'Theme=mechos' "$STAGE/etc/plymouth/plymouthd.conf" \
  || fail "MechOS is not the installed Plymouth theme"

# Regression guards for the exact Build 111 VM failures.
grep -Fq 'MECHOS_BUILD111_FIRSTBOOT_HANDOFF_V1' "$HELPER" \
  || fail "native firstboot handoff marker missing"
grep -Fq 'passwd -d mechos-setup' "$HELPER" \
  || fail "native setup account is still locked"
grep -Fq 'Exec=/usr/local/bin/mechos-oobe-start' "$HELPER" \
  || fail "native firstboot autostart bypasses guarded launcher"
grep -Fq 'MECHOS_BUILD111_OOBE_AUTHORITY_V1' "$AUTH" \
  || fail "final firstboot authority marker missing"
grep -Fq 'passwd -d "$SETUP_USER"' "$AUTH" \
  || fail "final setup account is still locked"
if grep -Fq 'passwd -l "$SETUP_USER"' "$AUTH"; then
  fail "final firstboot authority can still lock the setup account"
fi
grep -Fq 'Engine=none' "$STAGE/etc/xdg/ksplashrc" \
  || fail "stock KDE/Plasma splash is not disabled"
[ -L "$STAGE/etc/systemd/user/default.target.wants/mechos-oobe-autostart.service" ] \
  || fail "OOBE default-target user-service fallback is not enabled"
[ -L "$STAGE/etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service" ] \
  || fail "OOBE graphical-session user-service fallback is not enabled"

TMP="$ARCHIVE.build111-firstboot"
tar --zstd -cpf "$TMP" -C "$STAGE" .
mv -f "$TMP" "$ARCHIVE"
rm -rf "$STAGE"
trap - EXIT

log 'Build 111 update applied: account creation has XDG + systemd-user launch paths, temporary setup login is usable/non-admin, KDE session splash is suppressed, and MechOS Plymouth remains authoritative'
