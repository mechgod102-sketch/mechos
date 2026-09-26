#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_BUILD_HOTFIX_0316_MECHSCOPE_PLASMA_FOREGROUND_V1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

BASE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.5-update.tar.zst"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.1-hotfix.6-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p "$(dirname "$BUNDLE")"
[ -s "$BASE" ] || bash "$ROOT/scripts/build-hotfix-0.3.1-5.sh"
[ -s "$BASE" ] || { echo 'MechOS 0.3.1 Hotfix 5 cumulative base bundle missing' >&2; exit 1; }
tar --warning=no-timestamp --zstd -xpf "$BASE" -C "$STAGE"

mkdir -p   "$STAGE/usr/local/bin"   "$STAGE/usr/local/libexec"   "$STAGE/etc/xdg/autostart"

install -m0755 "$ROOT/scripts/mechscope-session-v20.sh"   "$STAGE/usr/local/bin/mechscope-session"
install -m0755 "$ROOT/scripts/mechos-mechscope-source-runtime-v33.py"   "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"
install -m0755 "$ROOT/scripts/mechos-mechscope-plasma-fallback-v25.sh"   "$STAGE/usr/local/bin/mechos-mechscope-plasma-fallback-v25"

cat >"$STAGE/etc/xdg/autostart/mechos-mechscope-plasma-fallback.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS MechScope Plasma Fallback
Comment=Launch MechScope after Plasma is ready when Gaming Mode requires the compatibility fallback
Exec=/usr/local/bin/mechos-mechscope-plasma-fallback-v25
OnlyShowIn=KDE;
NoDisplay=true
X-KDE-autostart-after=panel
X-KDE-StartupNotify=false
EOF

bash -n   "$STAGE/usr/local/bin/mechscope-session"   "$STAGE/usr/local/bin/mechos-mechscope-plasma-fallback-v25"
python3 -m py_compile "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"

grep -Fq 'MECHOS_MECHSCOPE_SESSION_V25_PLASMA_READY_HANDOFF'   "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'Plasma autostart will own the visible launch'   "$STAGE/usr/local/bin/mechscope-session"
grep -Fq 'MECHOS_MECHSCOPE_PLASMA_FALLBACK_V25'   "$STAGE/usr/local/bin/mechos-mechscope-plasma-fallback-v25"
grep -Fq 'MECHOS_MECHSCOPE_FOREGROUND_PRESENT_V34'   "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"
grep -Fq 'requestActivate'   "$STAGE/usr/local/libexec/mechos-mechscope-source-runtime-v33"

# Hotfix 6 is the first normal payload-only release. Updater infrastructure is
# frozen and must not be shipped, replaced, activated or repaired by this OS
# payload.
bash "$ROOT/scripts/mechos-strip-updater-from-stage-v1.sh" "$STAGE"

DAY="$(date -u +%F)"
EPOCH="$(date -u -d "$DAY 00:00:00" +%s)"
rm -f "$BUNDLE" "$SUM"
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner   --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" >"$SUM"

bash "$ROOT/scripts/validate-payload-only-hotfix-v1.sh" "$BUNDLE"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import datetime,json,sys
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.1-hotfix.6',
  'release_name':'MechOS v0.3.1 Hotfix 6',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'MechScope Plasma-fallback visibility fix. On legacy/non-Vulkan GPU paths, MechOS now starts Plasma first and launches MechScope from Plasma autostart after the real Wayland display is ready, instead of starting MechScope from a pre-Plasma background supervisor. The source-owned runtime reasserts fullscreen/activation during the startup window so KWin cannot leave MechScope behind the desktop. This is the first payload-only hotfix: it contains no Update Center, helper, transaction, engine-slot, recovery, reboot-helper or signing-key infrastructure.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.1-hotfix.6-update.tar.zst',
  'bundle_sha256':sha,
  'signature_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json.sig',
  'signing_key_id':'mechos-stable-2026-01',
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'MechOS 0.3.1 Hotfix 6 payload-only bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
