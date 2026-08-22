#!/usr/bin/env bash
# Shared session-lock Pi identity.
#
# ONE owner of the "which Pi process holds this home's session lock, and does
# the current process descend from that same Pi process?" decision.
# bin/fm-lock.sh uses it to acquire and inspect state/.lock.
# This file is sourced by scripts and has no side effects on source.

fm_pi_path() {  # <path>
  local path=$1
  [ -n "$path" ] || return 1
  case "/$path/" in
    */pi/*) return 0 ;;
  esac
  return 1
}

# True when the process described by command name $1 and full argument string $2
# is Pi. Evidence is the command basename, an exact Pi path component in the
# command or argv[0], or a bare interpreter running Pi
# script.
fm_pi_process_matches() {  # <comm> <args>
  local comm=$1 args=$2 base argv0
  base=$(basename -- "$comm")
  [ "$base" != pi ] || return 0
  argv0=${args%% *}
  if fm_pi_path "$comm" || fm_pi_path "$argv0"; then
    return 0
  fi
  case "$comm" in
    *node*|*python*)
      case "$args" in *' pi '*|*/pi|*/pi\ *) return 0 ;; esac
      ;;
  esac
  return 1
}

# Walk up to 16 parents and print the innermost Pi process.
# The walk stops at the first match so it cannot cross into an unrelated Pi
# further up the process tree.
fm_pi_ancestry_pid() {
  local pid=$$ comm args
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    args=$(ps -o args= -p "$pid" 2>/dev/null)
    if fm_pi_process_matches "$comm" "$args"; then
      printf '%s\n' "$pid"
      return 0
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pid" ] && [ "$pid" -gt 1 ] || break
  done
  return 1
}

fm_pi_pid_alive() {
  local pid=$1 comm args
  kill -0 "$pid" 2>/dev/null || return 1
  comm=$(ps -o comm= -p "$pid" 2>/dev/null) || return 1
  args=$(ps -o args= -p "$pid" 2>/dev/null)
  fm_pi_process_matches "$comm" "$args"
}

# True when the current session's Pi process owns the home lock.
fm_session_lock_owned_by_self() {
  local state=$1 lock_pid ancestry_pid
  lock_pid=$(cat "$state/.lock" 2>/dev/null || true)
  case "$lock_pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  ancestry_pid=$(fm_pi_ancestry_pid) || return 1
  [ "$ancestry_pid" = "$lock_pid" ]
}
