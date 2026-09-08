#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_VM_MECHSCOPE_SUSTAINED_HEALTH_V6

MODE="${1:-boot}"
CORE=/usr/local/libexec/mechos-vm-mode-runtime-v5
WATCHDOG=/usr/local/libexec/mechos-vm-mechscope-watchdog-v29
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/session-mode"
LOG="$STATE_DIR/vm-mode-runtime.log"
mkdir -p "$STATE_DIR" "$(dirname "$MODE_FILE")"

log(){ printf '[%s] [v6] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG"; }
mechscope_running(){
  pgrep -u "$(id -u)" -f '(/usr/bin/python3[[:space:]]+)?/usr/local/(bin/mechscope(\.real)?|libexec/mechos-mechscope-runtime-v23)([[:space:]]|$)' >/dev/null 2>&1
}

[ -x "$CORE" ] || { log "core VM runtime missing: $CORE"; exit 1; }

wanted="$MODE"
if [ "$wanted" = boot ]; then
  wanted=gaming
  if [ -r "$MODE_FILE" ]; then wanted="$(tr -d '[:space:]' <"$MODE_FILE")"; fi
  case "$wanted" in gaming|creator|desktop) ;; *) wanted=gaming ;; esac
fi
case "$wanted" in start|mechscope) wanted=gaming ;; esac

# Non-gaming transitions should remain immediate and must stop any watchdog.
if [ "$wanted" != gaming ]; then
  systemctl --user stop mechos-vm-mechscope-watchdog.service >/dev/null 2>&1 || true
  exec "$CORE" "$MODE"
fi

last_rc=1
for attempt in 1 2 3; do
  log "sustained Gaming Mode launch attempt=$attempt"
  if "$CORE" gaming; then
    last_rc=0
  else
    last_rc=$?
    log "core runtime returned rc=$last_rc attempt=$attempt"
  fi

  # HF28 accepted a process after roughly three seconds. A number of generated
  # owners survive that probe and then immediately close. Require a longer
  # sustained window before telling the mode launcher that Gaming Mode is up.
  if [ "$last_rc" -eq 0 ]; then
    healthy=1
    for _ in $(seq 1 16); do
      sleep 0.5
      if ! mechscope_running; then healthy=0; break; fi
    done
    if [ "$healthy" -eq 1 ]; then
      log "MechScope sustained health verified for 8 seconds"
      if [ -x "$WATCHDOG" ]; then
        systemctl --user stop mechos-vm-mechscope-watchdog.service >/dev/null 2>&1 || true
        if command -v systemd-run >/dev/null 2>&1; then
          systemd-run --user --quiet --collect --unit=mechos-vm-mechscope-watchdog \
            "$WATCHDOG" >/dev/null 2>&1 || \
            nohup "$WATCHDOG" >/dev/null 2>&1 </dev/null &
        else
          nohup "$WATCHDOG" >/dev/null 2>&1 </dev/null &
        fi
      fi
      exit 0
    fi
    log "MechScope vanished after initial health probe attempt=$attempt"
  fi
  sleep "$attempt"
done

log "MechScope failed sustained VMware health after three attempts"
exit "${last_rc:-1}"
