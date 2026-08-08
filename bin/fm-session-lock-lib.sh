#!/usr/bin/env bash
# Shared Pi session-lock identity helpers.
#
# The lock names the long-lived Pi process rather than a short-lived shell child.
# This file is sourced by lock and session-start helpers and has no source-time side effects.

fm_pi_process_matches() { # <comm> <args>
  local comm=$1 args=$2 base
  base=$(basename -- "$comm")
  [ "$base" = pi ] && return 0
  case "$comm $args" in
    *'/pi-coding-agent/'*|*'/pi.js '*|*'/pi '*|*' pi '*) return 0 ;;
  esac
  return 1
}

# Print the nearest Pi process in this process ancestry.
fm_harness_ancestry_pids() {
  local pid=$$ comm args
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    args=$(ps -o args= -p "$pid" 2>/dev/null || true)
    if fm_pi_process_matches "$comm" "$args"; then
      printf '%s\n' "$pid"
      return 0
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$pid" in ''|*[!0-9]*) break ;; esac
    [ "$pid" -gt 1 ] || break
  done
  return 1
}

fm_harness_ancestry_pid() {
  fm_harness_ancestry_pids
}

fm_harness_pid_alive() {
  local pid=$1 comm args
  kill -0 "$pid" 2>/dev/null || return 1
  comm=$(ps -o comm= -p "$pid" 2>/dev/null) || return 1
  args=$(ps -o args= -p "$pid" 2>/dev/null || true)
  fm_pi_process_matches "$comm" "$args"
}

# True when this process descends from the Pi process recorded in <state>/.lock.
fm_session_lock_owned_by_self() {
  local state=$1 lock_pid pid=$$ comm args
  lock_pid=$(cat "$state/.lock" 2>/dev/null || true)
  case "$lock_pid" in ''|*[!0-9]*) return 1 ;; esac
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    [ "$pid" = "$lock_pid" ] && return 0
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    args=$(ps -o args= -p "$pid" 2>/dev/null || true)
    fm_pi_process_matches "$comm" "$args" || :
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$pid" in ''|*[!0-9]*) break ;; esac
    [ "$pid" -gt 1 ] || break
  done
  return 1
}
