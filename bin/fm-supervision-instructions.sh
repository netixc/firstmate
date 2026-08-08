#!/usr/bin/env bash
# Render Pi's session-start supervision instructions and repair line.
# Usage: fm-supervision-instructions.sh [--read-only 0|1] [--afk 0|1] [--x-mode 0|1] [--repair-line] [--queue-pending 0|1]
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$REPO_ROOT}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
READ_ONLY=0
AFK=0
X_MODE=0
REPAIR_LINE=0
QUEUE_PENDING=0

bool_value() {
  case "$1" in 1|true|TRUE|yes|YES) printf '1\n' ;; *) printf '0\n' ;; esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --read-only) READ_ONLY=$(bool_value "${2:-}"); shift 2 ;;
    --afk) AFK=$(bool_value "${2:-}"); shift 2 ;;
    --x-mode) X_MODE=$(bool_value "${2:-}"); shift 2 ;;
    --queue-pending) QUEUE_PENDING=$(bool_value "${2:-}"); shift 2 ;;
    --repair-line) REPAIR_LINE=1; shift ;;
    -h|--help|help)
      sed -n '2,/^set -eu$/p' "$0" | sed 's/^# \{0,1\}//; $d'
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

PI_EXT="$FM_ROOT/.pi/extensions/fm-primary-pi-watch.ts"
PI_TURNEND_EXT="$FM_ROOT/.pi/extensions/fm-primary-turnend-guard.ts"
X_MODE_ENV="$CONFIG/x-mode.env"
[ "$X_MODE" -eq 1 ] || [ ! -f "$X_MODE_ENV" ] || X_MODE=1

if [ "$REPAIR_LINE" -eq 1 ]; then
  if [ "$READ_ONLY" -eq 1 ]; then
    printf '%s\n' 'Watcher repair belongs to the session holding the fleet lock; do not drain, arm, or repair from this read-only session.'
  elif [ "$AFK" -eq 1 ]; then
    printf '%s\n' 'Away mode owns Pi watcher supervision; load /afk and ensure its daemon is running instead of starting normal supervision directly.'
  else
    prefix=
    [ "$QUEUE_PENDING" -eq 0 ] || prefix='After draining queued wakes, '
    [ "$X_MODE" -eq 0 ] || prefix="${prefix}source '$X_MODE_ENV' first, then "
    printf '%srepair a missing or failed watcher cycle with fm_watch_arm_pi, or restart Pi with -e %s -e %s if the tracked extensions are not loaded.\n' "$prefix" "$PI_TURNEND_EXT" "$PI_EXT"
  fi
  exit 0
fi

rule='================================================================================'
printf '%s\n' "$rule"
printf 'SUPERVISION OPERATING INSTRUCTIONS - primary runtime: pi\n'
printf '%s\n' "$rule"
printf 'Current state:\n'
if [ "$READ_ONLY" -eq 1 ]; then
  printf '%s\n' '- Lock: read-only; do not drain, arm, spawn, steer, merge, or repair fleet state here.'
else
  printf '%s\n' '- Lock: held by this session; this session owns normal supervision unless away mode says otherwise.'
fi
if [ "$AFK" -eq 1 ]; then
  printf '%s\n' '- Away mode: active; load /afk and keep normal Pi supervision paused while the daemon owns the watcher.'
else
  printf '%s\n' '- Away mode: inactive.'
fi
if [ "$X_MODE" -eq 1 ]; then
  printf '%s\n' "- Relay mode: active; source $X_MODE_ENV before launching a watcher process."
else
  printf '%s\n' '- Relay mode: inactive; use the default watcher cadence.'
fi
printf '%s\n\n' '- Ordinary wake: the Pi extension owns watcher continuity; do not arm another cycle.'
while IFS= read -r line || [ -n "$line" ]; do
  line=${line//__FM_PI_EXT__/$PI_EXT}
  line=${line//__FM_PI_TURNEND_EXT__/$PI_TURNEND_EXT}
  printf '%s\n' "$line"
done < "$REPO_ROOT/docs/supervision-protocols/pi.md"
printf '\n'
