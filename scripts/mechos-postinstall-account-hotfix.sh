#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_POSTINSTALL_ACCOUNT_HOTFIX_V1

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

# The temporary account exists only to launch first-run account creation. It
# must be usable by SDDM without a password, but it must not be an administrator.
# The OOBE apply helper gets only its one required privileged action through a
# dedicated PolicyKit rule.
python3 - "$HELPER" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
marker = "# MECHOS_POSTINSTALL_ACCOUNT_NATIVE_V1"
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
        '# Keep the temporary OOBE account outside the administrator group.\n'
        'arch-chroot "$MNT" gpasswd -d mechos-setup wheel >/dev/null 2>&1 || true\n'
    )
    if marker not in t:
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

# Archinstall/post-install path receives the same temporary-account repair. A
# pre-existing installer user is preserved for OOBE to rename/update; otherwise
# the permanent account is created by mechos-oobe-apply on first boot.
python3 - "$POSTTARGET" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
marker = "# MECHOS_POSTINSTALL_ACCOUNT_TARGET_V1"
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
marker = "# MECHOS_POSTINSTALL_ACCOUNT_AUTHORITY_V1"
if marker not in t:
    locked = 'passwd -l "$SETUP_USER" >/dev/null 2>&1 || true\n'
    unlocked = 'passwd -d "$SETUP_USER" >/dev/null 2>&1 || true\n'
    if locked in t:
        t = t.replace(locked, unlocked, 1)
    elif unlocked not in t:
        raise SystemExit("firstboot authority setup-account password anchor missing")

    block = (
        marker + "\n"
        "# SDDM can enter the one-time setup session, but the account is not admin.\n"
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

# OOBE must have a second launch route in case KDE XDG autostart races the
# first graphical session. Both routes use mechos-oobe-start, whose state and
# user guards prevent duplicate setup after completion.
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

# Account-creation contract checks. The permanent account must receive its
# password and normal hardware/admin groups before OOBE is considered complete.
grep -Fq '["useradd", "-m", "-s", "/bin/bash"]' "$APPLY" \
  || fail "OOBE apply helper no longer creates a permanent user"
grep -Fq '"wheel"' "$APPLY" \
  || fail "permanent account administrator-group assignment is missing"
grep -Fq '["chpasswd"]' "$APPLY" \
  || fail "permanent account password assignment is missing"
grep -Fq 'oobe-complete' "$APPLY" \
  || fail "OOBE completion marker is missing"
grep -Fq '/usr/local/libexec/mechos-oobe-apply' "$POLKIT" \
  || fail "OOBE PolicyKit scope is missing"

# Regression guards for the hardware post-install failure.
grep -Fq 'passwd -d mechos-setup' "$HELPER" \
  || fail "native temporary setup account is still locked"
! grep -Fq 'passwd -l mechos-setup' "$HELPER" \
  || fail "native installer can still lock the setup account"
grep -Fq 'Exec=/usr/local/bin/mechos-oobe-start' "$HELPER" \
  || fail "native installer bypasses the guarded OOBE launcher"
grep -Fq 'MECHOS_POSTINSTALL_ACCOUNT_AUTHORITY_V1' "$AUTH" \
  || fail "firstboot authority account repair marker is missing"
grep -Fq 'passwd -d "$SETUP_USER"' "$AUTH" \
  || fail "firstboot authority still cannot enter setup session"
! grep -Fq 'passwd -l "$SETUP_USER"' "$AUTH" \
  || fail "firstboot authority can still lock the setup account"
grep -Fq 'gpasswd -d "$SETUP_USER" wheel' "$AUTH" \
  || fail "temporary firstboot account can still retain administrator group"
grep -Fq 'Relogin=false' "$AUTH" \
  || fail "firstboot SDDM configuration can still loop autologin"
[ -L "$STAGE/etc/systemd/user/default.target.wants/mechos-oobe-autostart.service" ] \
  || fail "OOBE default-target fallback is not enabled"
[ -L "$STAGE/etc/systemd/user/graphical-session.target.wants/mechos-oobe-autostart.service" ] \
  || fail "OOBE graphical-session fallback is not enabled"

TMP="$ARCHIVE.account-hotfix"
tar --zstd -cpf "$TMP" -C "$STAGE" .
mv -f "$TMP" "$ARCHIVE"
rm -rf "$STAGE"
trap - EXIT

# Final archive presence checks prevent a successful ISO build with a missing
# account-creation runtime.
for member in \
  ./usr/local/bin/mechos-oobe \
  ./usr/local/bin/mechos-oobe-start \
  ./usr/local/libexec/mechos-oobe-apply \
  ./usr/local/libexec/mechos-firstboot-authority \
  ./usr/lib/systemd/user/mechos-oobe-autostart.service \
  ./etc/polkit-1/rules.d/49-mechos-oobe.rules; do
  tar --zstd -tf "$ARCHIVE" "$member" >/dev/null \
    || fail "final installed payload is missing $member"
done

log "post-install account creation repaired: setup login usable/non-admin, OOBE has guarded redundant launch paths, pkexec is narrowly authorized, and permanent user/password creation is validated"
