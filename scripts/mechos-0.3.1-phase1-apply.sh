#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_031_PHASE1_WALLPAPERS_V1

log(){ printf '[%s] [MechOS 0.3.1] %s\n' "$(date -Is 2>/dev/null || date)" "$*" | tee -a /var/log/mechos-0.3.1-phase1.log; }
fail(){ log "ERROR: $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || fail 'must run as root'
[ -f /var/lib/mechos/installed ] || fail 'not an installed MechOS system'
[ ! -e /run/archiso/bootmnt ] || fail 'refusing live ISO'

SRC=/usr/share/mechos/wallpapers/0.3.1
DST=/usr/share/wallpapers
MARKER=/var/lib/mechos/0.3.1-phase1-wallpapers-applied

[ -d "$SRC" ] || fail "wallpaper payload missing: $SRC"

for i in $(seq -w 1 16); do
  img="$SRC/mechos-wallpaper-$i.jpg"
  [ -s "$img" ] || fail "missing wallpaper $img"
done

for i in $(seq -w 1 16); do
  pkg="$DST/MechOS-$i"
  mkdir -p "$pkg/contents/images"
  install -m0644 "$SRC/mechos-wallpaper-$i.jpg" "$pkg/contents/images/1920x1080.jpg"
  cat >"$pkg/metadata.json" <<EOF
{
  "KPlugin": {
    "Id": "MechOS-$i",
    "Name": "MechOS 0.3.1 Wallpaper $i",
    "Description": "Official MechOS 0.3.1 wallpaper collection",
    "Version": "0.3.1",
    "License": "Proprietary"
  }
}
EOF
done

# Maintain the existing stable MechOS wallpaper package ID while updating its
# backing image to the approved 0.3.1 default. This does not overwrite a user's
# current Plasma wallpaper choice; it only updates the packaged default asset.
mkdir -p "$DST/MechOS/contents/images"
install -m0644 "$SRC/mechos-wallpaper-01.jpg" "$DST/MechOS/contents/images/mechos-default.jpg"
cat >"$DST/MechOS/metadata.json" <<'EOF'
{
  "KPlugin": {
    "Id": "MechOS",
    "Name": "MechOS",
    "Description": "Default MechOS 0.3.1 desktop wallpaper",
    "Version": "0.3.1",
    "License": "Proprietary"
  }
}
EOF

mkdir -p /var/lib/mechos
touch "$MARKER"
log '0.3.1 Phase 1 applied: 16 official wallpapers installed for KDE Plasma without replacing user wallpaper selections.'
