#!/usr/bin/env bash
set -u

# Only act in the disposable Live ISO session. Installed MechOS already has
# its own first-boot/OOBE flow and the global KDED default prevents Plasma
# Welcome from racing it during the first login.
if [[ ! -e /run/archiso/bootmnt && ! -e /run/miso/bootmnt && ! -e /run/mechos-live ]]; then
  exit 0
fi

mkdir -p "${HOME}/.config"

# Persist the no-autoload choice in the live user's config too. This protects
# against Plasma/KDED versions that prefer the per-user setting over the
# system-wide /etc/xdg default.
if command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --file kded5rc --group Module-plasma-welcome --key autoload false >/dev/null 2>&1 || true
else
  cat > "${HOME}/.config/kded5rc" <<'EOF'
[Module-plasma-welcome]
autoload=false
EOF
fi

# If the KDED module was already loaded before XDG autostart processing,
# disable/unload it for the current session. Method names differ slightly
# between Plasma releases, so every call is best-effort.
if command -v qdbus6 >/dev/null 2>&1; then
  qdbus6 org.kde.kded6 /kded org.kde.kded6.setModuleAutoloading plasma-welcome false >/dev/null 2>&1 || true
  qdbus6 org.kde.kded6 /kded org.kde.kded6.unloadModule plasma-welcome >/dev/null 2>&1 || true
  qdbus6 org.kde.kded6 /kded org.kde.kded6.reconfigure >/dev/null 2>&1 || true
fi

# Welcome Center can be spawned a moment after the desktop becomes visible.
# Keep a short guard alive through that startup race, then get out of the way.
for _ in $(seq 1 40); do
  pkill -x plasma-welcome >/dev/null 2>&1 || true
  sleep 0.5
done

exit 0
