#!/usr/bin/env bash
# Shared session-lock harness identity.
#
# ONE owner of the "which verified-harness process holds this home's session
# lock, and does the current process descend from that same harness?" decision.
# bin/fm-lock.sh uses it to acquire and inspect state/.lock.
# This file is sourced by scripts and has no side effects on source.

# Cursor identity is structural rather than a safe command-name pattern, so its
# dedicated owner handles that adapter.
# shellcheck source=bin/fm-cursor-lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/fm-cursor-lib.sh"

FM_HARNESS_RE='codex|opencode|grok|kimi|^pi$|^pi-signed$'
FM_HARNESS_NAMES=(codex opencode grok kimi pi-signed pi)

fm_harness_path_name() {  # <path>
  local path=$1 name
  [ -n "$path" ] || return 1
  for name in "${FM_HARNESS_NAMES[@]}"; do
    case "/$path/" in
      */"$name"/*) printf '%s' "$name"; return 0 ;;
    esac
  done
  return 1
}

# True when the process described by command name $1 and full argument string $2
# is a verified harness. Evidence is the command basename, an exact harness path
# component in the command or argv[0], a bare interpreter running a harness
# script, or Cursor's structural identity.
fm_harness_process_matches() {  # <comm> <args>
  local comm=$1 args=$2 base argv0 name
  base=$(basename -- "$comm")
  if printf '%s' "$base" | grep -qE "$FM_HARNESS_RE"; then
    return 0
  fi
  argv0=${args%% *}
  if name=$(fm_harness_path_name "$comm") || name=$(fm_harness_path_name "$argv0"); then
    [ -n "$name" ]
    return
  fi
  case "$comm" in
    *node*|*python*)
      printf '%s' "$args" | grep -qE "$FM_HARNESS_RE" && return 0
      ;;
  esac
  fm_cursor_process_matches "$comm" "$args" "$argv0"
}

# Walk up to 16 parents and print the innermost verified harness process.
# The walk stops at the first match so it cannot cross into an unrelated harness
# further up the process tree.
fm_harness_ancestry_pids() {
  local pid=$$ comm args
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    args=$(ps -o args= -p "$pid" 2>/dev/null)
    if fm_harness_process_matches "$comm" "$args"; then
      printf '%s\n' "$pid"
      return 0
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pid" ] && [ "$pid" -gt 1 ] || break
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
  args=$(ps -o args= -p "$pid" 2>/dev/null)
  fm_harness_process_matches "$comm" "$args"
}

# True when the current session's verified harness process owns the home lock.
fm_session_lock_owned_by_self() {
  local state=$1 lock_pid ancestry_pid
  lock_pid=$(cat "$state/.lock" 2>/dev/null || true)
  case "$lock_pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  ancestry_pid=$(fm_harness_ancestry_pid) || return 1
  [ "$ancestry_pid" = "$lock_pid" ]
}
