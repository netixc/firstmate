#!/usr/bin/env bash
# Shared session-lock Pi identity.
#
# ONE owner of the "which Pi process holds this home's session lock, and does
# the current process descend from that same Pi process?" decision.
# bin/fm-lock.sh uses it to acquire and inspect state/.lock.
# This file is sourced by scripts and has no side effects on source.

fm_pi_canonical_path() {  # <path>
  local path=$1 link dir
  [ -n "$path" ] || return 1
  case "$path" in
    */*) ;;
    *) path=$(command -v -- "$path" 2>/dev/null) || return 1 ;;
  esac
  case "$path" in
    /*) ;;
    *) path="$PWD/$path" ;;
  esac
  while [ -L "$path" ]; do
    link=$(readlink "$path") || return 1
    case "$link" in
      /*) path=$link ;;
      *) path="$(dirname "$path")/$link" ;;
    esac
  done
  dir=$(CDPATH='' cd -P -- "$(dirname "$path")" 2>/dev/null && pwd) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

fm_pi_process_executable() {  # <pid> <comm>
  local pid=$1 comm=$2 path
  path=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
  if [ -n "$path" ]; then
    printf '%s\n' "$path"
    return 0
  fi
  case "$comm" in
    /*)
      printf '%s\n' "$comm"
      return 0
      ;;
  esac
  command -v lsof >/dev/null 2>&1 || return 1
  path=$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | sed -n '1p')
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

fm_pi_process_matches() {  # <pid> <comm> <args>
  local pid=$1 comm=$2 args=$3 base script pi_path candidate
  base=$(basename -- "$comm")
  if [ "$base" = pi ]; then
    pi_path=$(command -v pi 2>/dev/null) || return 1
    pi_path=$(fm_pi_canonical_path "$pi_path") || return 1
    candidate=$(fm_pi_process_executable "$pid" "$comm") || return 1
    candidate=$(fm_pi_canonical_path "$candidate") || return 1
    [ "$candidate" = "$pi_path" ]
    return
  fi
  case "$base" in
    node|nodejs|python|python[0-9]|python[0-9].[0-9])
      script=${args#* }
      [ "$script" != "$args" ] || return 1
      script=${script%% *}
      pi_path=$(command -v pi 2>/dev/null) || return 1
      pi_path=$(fm_pi_canonical_path "$pi_path") || return 1
      candidate=$(fm_pi_canonical_path "$script") || return 1
      [ "$candidate" = "$pi_path" ]
      return
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
    if fm_pi_process_matches "$pid" "$comm" "$args"; then
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
  fm_pi_process_matches "$pid" "$comm" "$args"
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
