#!/usr/bin/env bash
# Render Pi's primary supervision operating block for session start and
# the short repair line used by guards and turn-end hooks.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$REPO_ROOT}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
DOC_DIR="$REPO_ROOT/docs/supervision-protocols"

READ_ONLY=0
AFK=0
RELAY=0
REPAIR_LINE=0
QUEUE_PENDING=0

usage() {
  cat <<'EOF'
Usage: fm-supervision-instructions.sh [--read-only 0|1] [--afk 0|1] [--relay 0|1] [--repair-line] [--queue-pending 0|1]

Print Pi's primary supervision operating instructions.
With --repair-line, print one concise repair instruction for guard and hook messages.
EOF
}

bool_value() {
  case "$1" in
    1|true|TRUE|yes|YES) printf '1\n' ;;
    *) printf '0\n' ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --read-only)
      [ "$#" -gt 1 ] || { echo "error: --read-only requires 0 or 1" >&2; exit 2; }
      READ_ONLY=$(bool_value "$2")
      shift 2
      ;;
    --afk)
      [ "$#" -gt 1 ] || { echo "error: --afk requires 0 or 1" >&2; exit 2; }
      AFK=$(bool_value "$2")
      shift 2
      ;;
    --relay)
      [ "$#" -gt 1 ] || { echo "error: --relay requires 0 or 1" >&2; exit 2; }
      RELAY=$(bool_value "$2")
      shift 2
      ;;
    --queue-pending)
      [ "$#" -gt 1 ] || { echo "error: --queue-pending requires 0 or 1" >&2; exit 2; }
      QUEUE_PENDING=$(bool_value "$2")
      shift 2
      ;;
    --repair-line)
      REPAIR_LINE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

SNIPPET="$DOC_DIR/pi.md"
[ -f "$SNIPPET" ] || { echo "error: Pi supervision protocol is missing: $SNIPPET" >&2; exit 1; }

pi_ext="$FM_ROOT/.pi/extensions/fm-primary-pi-watch.ts"
pi_turnend_ext="$FM_ROOT/.pi/extensions/fm-primary-turnend-guard.ts"
relay_env="$CONFIG/relay.env"

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

relay_env_sh=$(shell_quote "$relay_env")

if [ "$RELAY" -eq 0 ] && [ -f "$relay_env" ]; then
  RELAY=1
fi

render_snippet() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line//__FM_PI_EXT__/$pi_ext}
    line=${line//__FM_PI_TURNEND_EXT__/$pi_turnend_ext}
    line=${line//__FM_RELAY_ENV_SH__/$relay_env_sh}
    line=${line//__FM_RELAY_ENV__/$relay_env}
    printf '%s\n' "$line"
  done < "$SNIPPET"
}

repair_line() {
  if [ "$READ_ONLY" -eq 1 ]; then
    printf '%s\n' 'Watcher repair belongs to the session holding the fleet lock; do not drain, arm, or repair from this read-only session.'
    return 0
  fi
  if [ "$AFK" -eq 1 ]; then
    printf '%s\n' 'Away mode owns watcher supervision; load /afk and ensure the daemon is running instead of starting normal supervision directly.'
    return 0
  fi

  prefix=
  if [ "$QUEUE_PENDING" -eq 1 ]; then
    prefix='After draining queued wakes, '
  fi
  if [ "$RELAY" -eq 1 ]; then
    prefix="${prefix}source ${relay_env_sh} first, then "
  fi

  printf '%s%s%s%s%s%s\n' "$prefix" 'repair a missing or failed watcher cycle with the Pi tool fm_watch_arm_pi, or restart Pi with -e ' "$pi_turnend_ext" ' -e ' "$pi_ext" ' if the extensions are not loaded.'
}

ordinary_wake_line() {
  printf '%s\n' '- Ordinary wake: the Pi extension already owns watcher continuity; do not arm another cycle.'
}

if [ "$REPAIR_LINE" -eq 1 ]; then
  repair_line
  exit 0
fi

RULE='================================================================================'
printf '%s\n' "$RULE"
printf 'SUPERVISION OPERATING INSTRUCTIONS - Pi primary\n'
printf '%s\n' "$RULE"
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
if [ "$RELAY" -eq 1 ]; then
  printf '%s%s%s\n' '- Relay: active; source ' "$relay_env" ' before launching any watcher process so the 30s cadence is inherited.'
else
  printf '%s\n' '- Relay: inactive; use the default watcher cadence.'
fi
ordinary_wake_line
printf '\n'
render_snippet
printf '\n'
