#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT="$BASE/out"
IMAGE="${MECHOS_ARCH_IMAGE:-archlinux:latest}"

command -v docker >/dev/null 2>&1 || {
  echo "Docker is required. Run ./scripts/setup-build-host.sh for a prerequisite check." >&2
  exit 127
}

docker info >/dev/null 2>&1 || {
  echo "Docker is installed but the daemon is unavailable to this user." >&2
  exit 1
}

available_kb="$(df -Pk "$BASE" | awk 'NR==2 {print $4}')"
required_kb=$((45 * 1024 * 1024))
if [[ -n "$available_kb" && "$available_kb" -lt "$required_kb" ]]; then
  echo "At least 45 GiB of free disk space is required for the ArchISO build." >&2
  exit 1
fi

mkdir -p "$OUT"

docker run --rm --privileged \
  -e "MECHOS_HOST_UID=$(id -u)" \
  -e "MECHOS_HOST_GID=$(id -g)" \
  -e "MECHOS_HARDWARE_TARGET_VERSION=${MECHOS_HARDWARE_TARGET_VERSION:-}" \
  -v "$BASE:/workspace" \
  -w /workspace \
  "$IMAGE" \
  bash -lc '
    set -Eeuo pipefail
    bash /workspace/scripts/patch-mechos-live-autologin-partitionmanager.sh /workspace/scripts/build-mechos-archiso.sh
    bash /workspace/scripts/build-mechos-archiso.sh
    chown -R "${MECHOS_HOST_UID}:${MECHOS_HOST_GID}" /workspace/out
  '

ISO="$(find "$OUT" -maxdepth 2 -type f -name '*.iso' -print -quit)"
[[ -n "$ISO" && -s "$ISO" ]] || {
  echo "The build completed without producing a non-empty ISO." >&2
  exit 1
}
[[ -s "$ISO.sha256" ]] || {
  echo "The ISO checksum file is missing: $ISO.sha256" >&2
  exit 1
}

(
  cd "$(dirname "$ISO")"
  sha256sum -c "$(basename "$ISO").sha256"
)

echo "MechOS ISO ready: $ISO"
