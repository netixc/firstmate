#!/usr/bin/env bash
# Plain Pi process identity and per-home session-lock ownership.

FM_HARNESS_IDENTITY_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bin/fm-harness-identity-lib.sh
. "$FM_HARNESS_IDENTITY_LIB_DIR/fm-harness-identity-lib.sh"

fm_harness_process_matches() {
  [ "$(fm_harness_process_identity "$1" "${2:-}" || true)" = pi ]
}

fm_harness_ancestry_pids() {
  local pid=$$ comm args identity pi_pid=
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    args=$(ps -o args= -p "$pid" 2>/dev/null || true)
    identity=$(fm_harness_process_identity "$comm" "$args" || true)
    fm_harness_identity_excluded "$identity" && return 1
    if [ "$identity" = pi ] && [ -z "$pi_pid" ]; then
      pi_pid=$pid
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pid" ] && [ "$pid" -gt 1 ] || break
  done
  [ -n "$pi_pid" ] || return 1
  printf '%s\n' "$pi_pid"
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
