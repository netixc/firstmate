#!/usr/bin/env bash
# Plain Pi process identity and per-home session-lock ownership.

fm_harness_path_name() {
  local path=${1:-}
  [ -n "$path" ] || return 1
  [ "$(basename -- "$path")" = pi ] || return 1
  printf 'pi'
}

fm_harness_process_matches() {
  local comm=$1 args=${2:-} base argv0
  base=$(basename -- "$comm")
  [ "$base" = pi ] && return 0
  argv0=${args%% *}
  fm_harness_path_name "$comm" >/dev/null || fm_harness_path_name "$argv0" >/dev/null
}

fm_harness_ancestry_pids() {
  local pid=$$ comm args printed=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    args=$(ps -o args= -p "$pid" 2>/dev/null || true)
    if fm_harness_process_matches "$comm" "$args"; then
      printf '%s\n' "$pid"
      printed=1
      break
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pid" ] && [ "$pid" -gt 1 ] || break
  done
  [ "$printed" -eq 1 ]
}

fm_harness_ancestry_pid() {
  fm_harness_ancestry_pids | head -1
}

fm_harness_pid_alive() {
  local pid=$1 comm args
  kill -0 "$pid" 2>/dev/null || return 1
  comm=$(ps -o comm= -p "$pid" 2>/dev/null) || return 1
  args=$(ps -o args= -p "$pid" 2>/dev/null || true)
  fm_harness_process_matches "$comm" "$args"
}

fm_session_lock_owned_by_self() {
  local state=$1 lock_pid pids pid
  lock_pid=$(cat "$state/.lock" 2>/dev/null || true)
  case "$lock_pid" in ''|*[!0-9]*) return 1 ;; esac
  pids=$(fm_harness_ancestry_pids) || return 1
  while IFS= read -r pid; do [ "$pid" = "$lock_pid" ] && return 0; done <<EOF
$pids
EOF
  return 1
}
