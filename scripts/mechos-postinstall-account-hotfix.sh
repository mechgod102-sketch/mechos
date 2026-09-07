#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_POSTINSTALL_ACCOUNT_HOTFIX_V2

PHASE="${1:-final}"
[ "$PHASE" = "final" ] || exit 0

ROOT=/workspace/archlive/airootfs
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
POSTTARGET="$PAYLOAD/mechos-postinstall-target"
HELPER="$ROOT/usr/local/libexec/mechos-native-install-helper"

log(){ printf '[MechOS Account Hotfix] %s\n' "$*"; }
fail(){ printf '[MechOS Account Hotfix] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Account Hotfix] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -d "$ROOT" ] || fail "ArchISO rootfs is missing"
[ -s "$ARCHIVE" ] || fail "installed-system payload is missing"
[ -f "$HELPER" ] || fail "native installer helper is missing"
[ -f "$POSTTARGET" ] || fail "post-install target is missing"

# mechos-setup is only a transport account used by SDDM to display OOBE. It must
# never become the installed owner account or survive the completed OOBE reboot.
python3 - "$HELPER" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
marker = "# MECHOS_POSTINSTALL_ACCOUNT_NATIVE_V2"
if marker not in t:
    locked = 'arch-chroot "$MNT" passwd -l mechos-setup >/dev/null 2>&1 || true'
    unlocked = 'arch-chroot "$MNT" passwd -d mechos-setup >/dev/null 2>&1 || true'
    if locked in t:
        t = t.replace(locked, unlocked, 1)
    elif unlocked not in t:
        raise SystemExit("native installer setup-account password anchor missing")

    anchor = unlocked + "\n"
    harden = (
        marker + "\n"
        '# Temporary OOBE user is deliberately not an administrator.\n'
        'arch-chroot "$MNT" gpasswd -d mechos-setup wheel >/dev/null 2>&1 || true\n'
    )
    t = t.replace(anchor, anchor + harden, 1)

    t = t.replace(
        "Exec=/usr/local/bin/mechos-oobe\nTerminal=false\nX-KDE-autostart-after=panel",
        "Exec=/usr/local/bin/mechos-oobe-start\nTryExec=/usr/local/bin/mechos-oobe-start\nTerminal=false\nX-KDE-autostart-after=panel",
        1,
    )
    t = t.replace("Relogin=true\nSDDM", "Relogin=false\nSDDM", 1)

p.write_text(t, encoding="utf-8")
PY
bash -n "$HELPER" || fail "native installer helper is invalid after account hotfix"

# Archinstall/post-install path gets the same temporary-account semantics.
python3 - "$POSTTARGET" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
marker = "# MECHOS_POSTINSTALL_ACCOUNT_TARGET_V2"
if marker not in t:
    locked = "passwd -l mechos-setup >/dev/null 2>&1 || true"
    unlocked = "passwd -d mechos-setup >/dev/null 2>&1 || true"
    if locked in t:
        t = t.replace(locked, unlocked, 1)
    elif unlocked not in t:
        raise SystemExit("post-install setup-account password anchor missing")

    anchor = unlocked + "\n"
    harden = (
        marker + "\n"
        "# OOBE elevation is PolicyKit-scoped; the temporary user is never wheel.\n"
        "gpasswd -d mechos-setup wheel >/dev/null 2>&1 || true\n"
    )
    t = t.replace(anchor, anchor + harden, 1)
    t = t.replace(
        "Exec=/usr/local/bin/mechos-oobe\nTerminal=false\nX-KDE-autostart-after=panel",
        "Exec=/usr/local/bin/mechos-oobe-start\nTryExec=/usr/local/bin/mechos-oobe-start\nTerminal=false\nX-KDE-autostart-after=panel",
        1,
    )
    t = t.replace("Relogin=true\nSDDMOOBE", "Relogin=false\nSDDMOOBE", 1)

p.write_text(t, encoding="utf-8")
PY
bash -n "$POSTTARGET" || fail "post-install target is invalid after account hotfix"

STAGE="$(mktemp -d /tmp/mechos-account-hotfix.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
tar --warning=no-timestamp --zstd -xpf "$ARCHIVE" -C "$STAGE"

AUTH="$STAGE/usr/local/libexec/mechos-firstboot-authority"
START="$STAGE/usr/local/bin/mechos-oobe-start"
OOBE="$STAGE/usr/local/bin/mechos-oobe"
APPLY="$STAGE/usr/local/libexec/mechos-oobe-apply"
CLEANUP="$STAGE/usr/local/libexec/mechos-oobe-cleanup"
POLKIT="$STAGE/etc/polkit-1/rules.d/49-mechos-oobe.rules"

[ -x "$AUTH" ] || fail "firstboot authority is missing from installed payload"
[ -x "$START" ] || fail "guarded OOBE launcher is missing from installed payload"
[ -x "$OOBE" ] || fail "OOBE UI is missing from installed payload"
[ -x "$APPLY" ] || fail "OOBE account apply helper is missing from installed payload"
[ -x "$CLEANUP" ] || fail "OOBE cleanup helper is missing from installed payload"

python3 - "$AUTH" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
marker = "# MECHOS_POSTINSTALL_ACCOUNT_AUTHORITY_V2"
if marker not in t:
    locked = 'passwd -l "$SETUP_USER" >/dev/null 2>&1 || true\n'
    unlocked = 'passwd -d "$SETUP_USER" >/dev/null 2>&1 || true\n'
    if locked in t:
        t = t.replace(locked, unlocked, 1)
    elif unlocked not in t:
        raise SystemExit("firstboot authority setup-account password anchor missing")

    block = (
        marker + "\n"
        "# SDDM may enter this one-time setup session, but it is never admin.\n"
        'if getent group wheel >/dev/null 2>&1; then\n'
        '  gpasswd -d "$SETUP_USER" wheel >/dev/null 2>&1 || true\n'
        "fi\n"
    )
    t = t.replace(unlocked, unlocked + block, 1)
    t = t.replace("Relogin=true\nSDDMEOF", "Relogin=false\nSDDMEOF", 1)

p.write_text(t, encoding="utf-8")
PY
chmod 0755 "$AUTH"
bash -n "$AUTH" || fail "firstboot authority is invalid after account hotfix"

# Patch the OOBE itself so the temporary account never becomes the visible
# post-setup destination. The root apply helper owns the reboot handoff; the UI
# no longer attempts an unprivileged systemctl reboot from mechos-setup.
python3 - "$APPLY" "$OOBE" <<'PY'
from pathlib import Path
import sys

apply_path = Path(sys.argv[1])
oobe_path = Path(sys.argv[2])
apply_text = apply_path.read_text(encoding="utf-8")
ui_text = oobe_path.read_text(encoding="utf-8")
marker = "# MECHOS_POSTINSTALL_ACCOUNT_FINISH_V2"

if marker not in apply_text:
    anchor = 'subprocess.run(["systemctl", "enable", "mechos-oobe-cleanup.service"], check=False)\nprint("MechOS first system setup complete.")'
    if anchor not in apply_text:
        raise SystemExit("OOBE completion/reboot anchor missing")
    replacement = '''# MECHOS_POSTINSTALL_ACCOUNT_FINISH_V2
# Remove every stale SDDM fragment that still targets the transport account.
for cfg in sddm.glob("*.conf"):
    try:
        if "mechos-setup" in cfg.read_text(errors="ignore"):
            cfg.unlink()
    except OSError:
        pass

# After OOBE, boot to the real sign-in screen. The created user is stored in
# /var/lib/mechos/system-user and SDDM will enumerate it normally.
(sddm / "99-mechos-final-user.conf").write_text(
    "[Autologin]\\n"
    "User=\\n"
    "Session=mechos-gaming.desktop\\n"
    "Relogin=false\\n"
)
subprocess.run(["systemctl", "enable", "mechos-oobe-cleanup.service"], check=False)

# The helper is already running as root through the narrowly scoped PolicyKit
# rule. Schedule the reboot here so completion cannot drop back into the
# mechos-setup Plasma session because an unprivileged reboot was denied.
subprocess.run([
    "systemd-run", "--unit=mechos-oobe-finish-reboot", "--on-active=3s",
    "--collect", "/usr/bin/systemctl", "reboot"
], check=True)
print("MechOS first system setup complete; reboot scheduled.")'''
    apply_text = apply_text.replace(anchor, replacement, 1)

# The privileged helper now owns reboot. Leaving this call in the GUI can cause
# PolicyKit to ask mechos-setup for a password or leave the desktop open.
ui_text = ui_text.replace(
    '        subprocess.Popen(["systemctl", "reboot"])',
    '        # Reboot is scheduled by the privileged OOBE apply helper.',
)
ui_text = ui_text.replace(
    'w = OOBE(); w.showMaximized(); return app.exec()',
    'w = OOBE(); w.showFullScreen(); return app.exec()',
)

apply_path.write_text(apply_text, encoding="utf-8")
oobe_path.write_text(ui_text, encoding="utf-8")
PY
chmod 0755 "$APPLY" "$OOBE"
python3 -m py_compile "$APPLY" "$OOBE" || fail "OOBE Python invalid after account finish patch"

# Cleanup is authoritative on the next boot. It removes the transport user and
# any stale SDDM entry before the display manager can start.
python3 - "$CLEANUP" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
marker = "# MECHOS_POSTINSTALL_ACCOUNT_CLEANUP_V2"
if marker not in t:
    anchor = 'rm -rf /home/mechos-setup\nmkdir -p /var/lib/mechos\ntouch /var/lib/mechos/oobe-cleaned'
    if anchor not in t:
        raise SystemExit("OOBE cleanup anchor missing")
    replacement = '''rm -rf /home/mechos-setup
# MECHOS_POSTINSTALL_ACCOUNT_CLEANUP_V2
mkdir -p /etc/sddm.conf.d /var/lib/mechos
for cfg in /etc/sddm.conf.d/*.conf; do
  [ -f "$cfg" ] || continue
  if grep -Fq 'mechos-setup' "$cfg"; then
    rm -f "$cfg"
  fi
done
cat > /etc/sddm.conf.d/99-mechos-final-user.conf <<'SDDMFINAL'
[Autologin]
User=
Session=mechos-gaming.desktop
Relogin=false
SDDMFINAL
rm -f /etc/systemd/user/default.target.wants/mechos-oobe-autostart.service
rm -f /etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service
touch /var/lib/mechos/oobe-cleaned'''
    t = t.replace(anchor, replacement, 1)
p.write_text(t, encoding="utf-8")
PY
chmod 0755 "$CLEANUP"
bash -n "$CLEANUP" || fail "OOBE cleanup invalid after account handoff patch"

# OOBE has a redundant launch route so a KDE autostart race cannot expose a
# normal mechos-setup desktop instead of account creation.
mkdir -p \
  "$STAGE/usr/lib/systemd/user" \
  "$STAGE/etc/systemd/user/default.target.wants" \
  "$STAGE/etc/systemd/user/graphical-session.target.wants"
cat > "$STAGE/usr/lib/systemd/user/mechos-oobe-autostart.service" <<'EOF'
[Unit]
Description=Launch MechOS post-install account creation
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

# Reassert the narrow PolicyKit permission after all cumulative payload overlays.
mkdir -p "$(dirname "$POLKIT")"
cat > "$POLKIT" <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        subject.user == "mechos-setup" &&
        action.lookup("program") == "/usr/local/libexec/mechos-oobe-apply") {
        return polkit.Result.YES;
    }
});
EOF
chmod 0644 "$POLKIT" "$STAGE/usr/lib/systemd/user/mechos-oobe-autostart.service"

# Permanent-account contract checks.
grep -Fq '["useradd", "-m", "-s", "/bin/bash"]' "$APPLY" \
  || fail "OOBE apply helper no longer creates a permanent user"
grep -Fq '"wheel"' "$APPLY" \
  || fail "permanent account administrator-group assignment is missing"
grep -Fq '["chpasswd"]' "$APPLY" \
  || fail "permanent account password assignment is missing"
grep -Fq 'oobe-complete' "$APPLY" \
  || fail "OOBE completion marker is missing"
grep -Fq 'mechos-oobe-finish-reboot' "$APPLY" \
  || fail "privileged OOBE reboot handoff is missing"
grep -Fq '99-mechos-final-user.conf' "$APPLY" \
  || fail "final SDDM handoff is missing"
grep -Fq '/usr/local/libexec/mechos-oobe-apply' "$POLKIT" \
  || fail "OOBE PolicyKit scope is missing"

# Regression guards for the exact post-install failure.
grep -Fq 'passwd -d mechos-setup' "$HELPER" \
  || fail "native temporary setup account is still locked"
! grep -Fq 'passwd -l mechos-setup' "$HELPER" \
  || fail "native installer can still lock the setup account"
grep -Fq 'Exec=/usr/local/bin/mechos-oobe-start' "$HELPER" \
  || fail "native installer bypasses the guarded OOBE launcher"
grep -Fq 'MECHOS_POSTINSTALL_ACCOUNT_AUTHORITY_V2' "$AUTH" \
  || fail "firstboot authority account repair marker is missing"
grep -Fq 'passwd -d "$SETUP_USER"' "$AUTH" \
  || fail "firstboot authority still cannot enter setup session"
! grep -Fq 'passwd -l "$SETUP_USER"' "$AUTH" \
  || fail "firstboot authority can still lock the setup account"
grep -Fq 'gpasswd -d "$SETUP_USER" wheel' "$AUTH" \
  || fail "temporary firstboot account can still retain administrator group"
grep -Fq 'Relogin=false' "$AUTH" \
  || fail "firstboot SDDM configuration can still loop autologin"
grep -Fq 'showFullScreen()' "$OOBE" \
  || fail "OOBE is not forced fullscreen over the temporary session"
! grep -Fq 'subprocess.Popen(["systemctl", "reboot"])' "$OOBE" \
  || fail "OOBE UI still attempts an unprivileged reboot as mechos-setup"
grep -Fq 'MECHOS_POSTINSTALL_ACCOUNT_CLEANUP_V2' "$CLEANUP" \
  || fail "temporary-user cleanup repair is missing"
[ -L "$STAGE/etc/systemd/user/default.target.wants/mechos-oobe-autostart.service" ] \
  || fail "OOBE default-target fallback is not enabled"
[ -L "$STAGE/etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service" ] \
  || fail "OOBE graphical-session fallback is not enabled"

TMP="$ARCHIVE.account-hotfix"
tar --zstd -cpf "$TMP" -C "$STAGE" .
mv -f "$TMP" "$ARCHIVE"
rm -rf "$STAGE"
trap - EXIT

for member in \
  ./usr/local/bin/mechos-oobe \
  ./usr/local/bin/mechos-oobe-start \
  ./usr/local/libexec/mechos-oobe-apply \
  ./usr/local/libexec/mechos-oobe-cleanup \
  ./usr/local/libexec/mechos-firstboot-authority \
  ./usr/lib/systemd/user/mechos-oobe-autostart.service \
  ./etc/polkit-1/rules.d/49-mechos-oobe.rules; do
  tar --zstd -tf "$ARCHIVE" "$member" >/dev/null \
    || fail "final installed payload is missing $member"
done

log "post-install account creation repaired: mechos-setup is only a hidden transport session; OOBE is fullscreen, permanent user/password creation is validated, root schedules the completion reboot, and cleanup removes the temporary account before SDDM returns"
