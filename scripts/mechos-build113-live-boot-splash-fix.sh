#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
REFERENCE="/workspace/branding/mechos-splash-reference.png"
SDDM="$ROOT/etc/sddm.conf.d/99-mechos-live.conf"
SYSTEMD="$ROOT/etc/systemd/system"

log(){ printf '[MechOS Build 113 Live Boot] %s\n' "$*"; }
fail(){ printf '[MechOS Build 113 Live Boot] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Build 113 Live Boot] ERROR line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -d "$ROOT" ] || fail "ArchISO rootfs missing"
[ -s "$REFERENCE" ] || fail "approved MechOS splash artwork missing"
[ -s "$ARCHIVE" ] || fail "installed payload missing"
[ -f "$SDDM" ] || fail "final Live SDDM configuration missing"

# ---------------------------------------------------------------------------
# Build 112 regression: the Live image could remain on a black screen forever.
# The final Live authority had changed SDDM's session from the known-good
# plasma.desktop entry to the bare word 'plasma'. Reassert the real desktop
# entry that exists in the image and fail the build if it disappears.
# ---------------------------------------------------------------------------
if [ ! -f "$ROOT/usr/share/wayland-sessions/plasma.desktop" ] && \
   [ ! -f "$ROOT/usr/share/xsessions/plasma.desktop" ]; then
  fail "plasma.desktop session file is missing from the Live image"
fi
sed -i -E 's/^Session=.*/Session=plasma.desktop/' "$SDDM"
grep -Fq 'Session=plasma.desktop' "$SDDM" || fail "Live SDDM session was not repaired"

# Release Plymouth before SDDM takes the graphical VT. This is intentionally a
# Live-only service: even if the normal plymouth-quit unit misses its handoff in
# a VM, the boot splash cannot permanently cover the desktop/installer.
mkdir -p "$SYSTEMD/sddm.service.d"
cat > "$SYSTEMD/mechos-live-plymouth-release.service" <<'EOF'
[Unit]
Description=Release MechOS Live boot splash before the desktop
After=systemd-user-sessions.service
Before=sddm.service display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c '/usr/bin/plymouth --ping >/dev/null 2>&1 && /usr/bin/plymouth quit || true'
RemainAfterExit=yes
EOF

cat > "$SYSTEMD/sddm.service.d/10-mechos-live-prepare.conf" <<'EOF'
[Unit]
Wants=mechos-live-session-prepare.service mechos-live-plymouth-release.service
After=mechos-live-session-prepare.service mechos-live-plymouth-release.service
EOF

# ---------------------------------------------------------------------------
# Distinct Live and installed Plymouth identities.
# Both use the approved MechOS artwork, but Live says it is loading the Live
# environment while an installed system simply says it is starting MechOS.
# The artwork must be on a positive Z layer; the old -100 layer could be hidden
# behind Plymouth's background and render as a completely black screen.
# ---------------------------------------------------------------------------
write_script(){
  local path="$1"
  local title="$2"
  local subtitle="$3"
  cat > "$path" <<EOF
# MECHOS_BUILD113_VISIBLE_SPLASH_V1
Window.SetBackgroundTopColor(0.004, 0.008, 0.020);
Window.SetBackgroundBottomColor(0.004, 0.008, 0.020);

reference.original = Image("mechos-splash-reference.png");
screen.w = Window.GetWidth();
screen.h = Window.GetHeight();
image.w = reference.original.GetWidth();
image.h = reference.original.GetHeight();
scale.x = screen.w / image.w;
scale.y = screen.h / image.h;
scale = scale.x;
if (scale.y < scale.x) {
    scale = scale.y;
}
reference.image = reference.original.Scale(image.w * scale, image.h * scale);
reference.sprite = Sprite(reference.image);
reference.sprite.SetX((screen.w - reference.image.GetWidth()) / 2);
reference.sprite.SetY((screen.h - reference.image.GetHeight()) / 2);
reference.sprite.SetZ(10);

status.image = Image.Text("$title", 0.92, 0.94, 1.00);
status.sprite = Sprite(status.image);
status.sprite.SetX(Window.GetWidth() / 2 - status.image.GetWidth() / 2);
status.sprite.SetY(Window.GetHeight() - status.image.GetHeight() - 70);
status.sprite.SetZ(30);

mode.image = Image.Text("$subtitle", 0.62, 0.72, 0.98);
mode.sprite = Sprite(mode.image);
mode.sprite.SetX(Window.GetWidth() / 2 - mode.image.GetWidth() / 2);
mode.sprite.SetY(Window.GetHeight() - mode.image.GetHeight() - 38);
mode.sprite.SetZ(30);

message.image = Image.Text("", 0.84, 0.90, 1.00);
message.sprite = Sprite(message.image);
message.sprite.SetZ(40);
fun message_callback(text) {
    message.image = Image.Text(text, 0.84, 0.90, 1.00);
    message.sprite.SetImage(message.image);
    message.sprite.SetX(Window.GetWidth() / 2 - message.image.GetWidth() / 2);
    message.sprite.SetY(28);
}
Plymouth.SetMessageFunction(message_callback);
EOF
}

# Live ISO theme: separate name/config so it can never inherit installed-system
# wording or accidentally be replaced by an installed-target theme pass.
LIVE_THEME="$ROOT/usr/share/plymouth/themes/mechos-live"
mkdir -p "$LIVE_THEME" "$ROOT/etc/plymouth"
install -m 0644 "$REFERENCE" "$LIVE_THEME/mechos-splash-reference.png"
cat > "$LIVE_THEME/mechos-live.plymouth" <<'EOF'
[Plymouth Theme]
Name=MechOS Live
Description=MechOS Live Environment boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/mechos-live
ScriptFile=/usr/share/plymouth/themes/mechos-live/mechos-live.script
EOF
write_script "$LIVE_THEME/mechos-live.script" \
  "LOADING MECHOS LIVE ENVIRONMENT..." \
  "MECHOS LIVE  >  TRY IT  >  INSTALL IT"
cat > "$ROOT/etc/plymouth/plymouthd.conf" <<'EOF'
[Daemon]
Theme=mechos-live
ShowDelay=0
DeviceTimeout=8
EOF
ln -sfn mechos-live/mechos-live.plymouth \
  "$ROOT/usr/share/plymouth/themes/default.plymouth"

# Installed-system theme lives inside the install payload. It intentionally does
# not contain Live/installer wording.
STAGE="$(mktemp -d /tmp/mechos-build113-installed-splash.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
tar --zstd -xpf "$ARCHIVE" -C "$STAGE"
INSTALLED_THEME="$STAGE/usr/share/plymouth/themes/mechos"
mkdir -p "$INSTALLED_THEME" "$STAGE/etc/plymouth"
install -m 0644 "$REFERENCE" "$INSTALLED_THEME/mechos-splash-reference.png"
write_script "$INSTALLED_THEME/mechos.script" \
  "STARTING MECHOS..." \
  "GAMING + CREATOR OS"
cat > "$INSTALLED_THEME/mechos.plymouth" <<'EOF'
[Plymouth Theme]
Name=MechOS
Description=MechOS installed-system boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/mechos
ScriptFile=/usr/share/plymouth/themes/mechos/mechos.script
EOF
cat > "$STAGE/etc/plymouth/plymouthd.conf" <<'EOF'
[Daemon]
Theme=mechos
ShowDelay=0
DeviceTimeout=8
EOF
ln -sfn mechos/mechos.plymouth "$STAGE/usr/share/plymouth/themes/default.plymouth"

# Add a second, systemd-user launch path for the Live installer. XDG autostart
# remains primary; a lock wrapper prevents duplicate installer windows when both
# launch mechanisms fire.
mkdir -p \
  "$ROOT/usr/lib/systemd/user" \
  "$ROOT/etc/systemd/user/graphical-session.target.wants" \
  "$ROOT/usr/local/bin"
cat > "$ROOT/usr/local/bin/mechos-live-autostart" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${USER:-}" = "mechos" ] || exit 0
if ! { [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; }; then
  exit 0
fi
mkdir -p "${XDG_RUNTIME_DIR:-/tmp}"
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/mechos-live-installer.lock"
flock -n 9 || exit 0
exec /usr/local/bin/mechos-live-welcome
EOF
chmod 0755 "$ROOT/usr/local/bin/mechos-live-autostart"

if [ -f "$ROOT/etc/xdg/autostart/mechos-live-welcome.desktop" ]; then
  sed -i 's#^Exec=.*#Exec=/usr/local/bin/mechos-live-autostart#' \
    "$ROOT/etc/xdg/autostart/mechos-live-welcome.desktop"
fi

cat > "$ROOT/usr/lib/systemd/user/mechos-live-installer.service" <<'EOF'
[Unit]
Description=Launch MechOS Live installer
ConditionUser=mechos
ConditionPathExists=/run/archiso/bootmnt
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mechos-live-autostart
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
ln -sfn /usr/lib/systemd/user/mechos-live-installer.service \
  "$ROOT/etc/systemd/user/graphical-session.target.wants/mechos-live-installer.service"

# Repack installed payload only after its normal-boot theme is finalized.
TMP="$ARCHIVE.build113-splash"
tar --zstd -cpf "$TMP" -C "$STAGE" .
mv -f "$TMP" "$ARCHIVE"
rm -rf "$STAGE"
trap - EXIT

# Exact regression guards for the Build 112 VM failure.
grep -Fq 'Theme=mechos-live' "$ROOT/etc/plymouth/plymouthd.conf" \
  || fail "Live theme is not mechos-live"
grep -Fq 'reference.sprite.SetZ(10)' "$LIVE_THEME/mechos-live.script" \
  || fail "Live artwork is not on a visible layer"
grep -Fq 'LOADING MECHOS LIVE ENVIRONMENT' "$LIVE_THEME/mechos-live.script" \
  || fail "Live splash identity is missing"
grep -Fq 'Session=plasma.desktop' "$SDDM" \
  || fail "Live SDDM does not target plasma.desktop"
grep -Fq 'mechos-live-plymouth-release.service' \
  "$SYSTEMD/sddm.service.d/10-mechos-live-prepare.conf" \
  || fail "SDDM does not force-release Plymouth"
[ -L "$ROOT/etc/systemd/user/graphical-session.target.wants/mechos-live-installer.service" ] \
  || fail "Live installer user-service fallback is not enabled"
grep -Fq 'Exec=/usr/local/bin/mechos-live-autostart' \
  "$ROOT/etc/xdg/autostart/mechos-live-welcome.desktop" \
  || fail "Live XDG autostart does not use the single-instance wrapper"

CHECK="$(mktemp -d /tmp/mechos-build113-check.XXXXXX)"
tar --zstd -xpf "$ARCHIVE" -C "$CHECK"
grep -Fq 'Theme=mechos' "$CHECK/etc/plymouth/plymouthd.conf" \
  || fail "installed theme is not mechos"
grep -Fq 'reference.sprite.SetZ(10)' \
  "$CHECK/usr/share/plymouth/themes/mechos/mechos.script" \
  || fail "installed artwork is not on a visible layer"
grep -Fq 'STARTING MECHOS' "$CHECK/usr/share/plymouth/themes/mechos/mechos.script" \
  || fail "installed splash identity is missing"
if grep -Fq 'MECHOS LIVE' "$CHECK/usr/share/plymouth/themes/mechos/mechos.script"; then
  fail "installed splash still contains Live wording"
fi
rm -rf "$CHECK"

log 'Build 113 fix applied: visible Live/installed splashes, plasma.desktop autologin, forced Plymouth release, and redundant single-instance Live installer launch'
