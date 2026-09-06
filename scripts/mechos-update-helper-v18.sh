#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_UPDATE_HELPER_V14
# MECHOS_UPDATE_HELPER_V18

CORE=/usr/local/libexec/mechos-update-helper-core-v18
HEALTH=/usr/local/libexec/mechos-pacman-health-v18
TXLOG=/var/log/mechos-update-transaction.log

[ -x "$CORE" ] || { echo 'MechOS update helper core is missing.' >&2; exit 73; }

cmd="${1:-status}"
case "$cmd" in
  status|check)
    exec "$CORE" "$cmd"
    ;;
  apply)
    [ "$(id -u)" -eq 0 ] || { echo 'Administrator privileges required. Run through pkexec.' >&2; exit 77; }
    [ -x "$HEALTH" ] || { echo 'Pacman health helper is missing.' >&2; exit 74; }
    "$HEALTH"

    before=0
    [ -f "$TXLOG" ] && before="$(wc -l <"$TXLOG" 2>/dev/null || echo 0)"

    set +e
    "$CORE" apply
    rc=$?
    set -e
    [ "$rc" -eq 0 ] && exit 0

    # The core helper performs the MechOS transaction before Arch/Flatpak
    # package updates. If that transaction committed during this run but a
    # later package refresh failed, preserve the successful MechOS update and
    # report the package problem as partial success rather than rolling the OS
    # update back or showing a false total-install failure.
    committed=0
    if [ -f "$TXLOG" ]; then
      start=$((before + 1))
      tail -n +"$start" "$TXLOG" 2>/dev/null | grep -Fq 'transaction committed for ' && committed=1 || true
    fi
    if [ "$committed" -eq 1 ]; then
      echo 'MECHOS_CORE_UPDATE_STAGED=1'
      echo 'PACKAGE_UPDATE_FAILED=1'
      echo 'MechOS update staged successfully. One or more Arch/Flatpak package updates need to be retried after restart.' >&2
      "$CORE" status || true
      exit 0
    fi
    exit "$rc"
    ;;
  *)
    echo 'Usage: mechos-update-helper {status|check|apply}' >&2
    exit 2
    ;;
esac
