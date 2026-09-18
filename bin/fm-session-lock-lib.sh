#!/usr/bin/env bash
# Shared session-lock harness identity.
#
# ONE owner of the "which exact Pi process holds this home's session lock,
# and does the current process descend from that same Pi process?" decision.
# bin/fm-lock.sh uses it to acquire and inspect state/.lock.
# This file is sourced by scripts and has no side effects on source.

# The only supported worker-runtime command name.
FM_HARNESS_RE='^pi$'

# Print `pi` only when executable path $1 itself has the exact basename `pi`.
# Parent directory names and arguments are never process identity evidence.
fm_harness_path_name() {  # <path>
  local path=$1 base
  [ -n "$path" ] || return 1
  base=${path##*/}
  base=${base#-}
  [ "$base" = pi ] || return 1
  printf '%s' pi
}

# True only when the process's command or argv[0] has the exact executable
# basename `pi`. Generic Node/Python processes, parent directory names, and
# later arguments never count as Pi identity.
fm_harness_process_matches() {  # <comm> <args>
  local comm=$1 args=$2 base argv0
  base=$(basename -- "$comm")
  if printf '%s' "$base" | grep -qE "$FM_HARNESS_RE"; then
    return 0
  fi
  argv0=${args%% *}
  if fm_harness_path_name "$comm" || fm_harness_path_name "$argv0"; then
    return 0
  fi
  return 1
}

# Walk the current process ancestry (up to 16 hops) and print this session's
# exact Pi pid.
#
# The walk climbs freely until the first harness match, because the caller is
# normally an ordinary shell several levels below its session. After that first
# match it stops at the first non-harness ancestor, so it can never cross a gap
# into an unrelated harness further up the real process tree - for example the
# live session that launched a test as its own subprocess.
#
# The innermost match is the Pi session that owns the lock.
fm_harness_ancestry_pids() {
  local pid=$$ comm args printed=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    args=$(ps -o args= -p "$pid" 2>/dev/null)
    if fm_harness_process_matches "$comm" "$args"; then
      printf '%s\n' "$pid"
      printed=1
      break
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    # Examine the top of the chain before stopping. Inside a PID namespace the
    # harness itself is pid 1, so stopping as soon as the next pid is 1 hides the
    # very process this walk exists to find. A host's real pid 1 (init, systemd,
    # launchd) is not harness-shaped, so fm_harness_process_matches rejects it.
    case "$pid" in '' | *[!0-9]*) break ;; esac
    [ "$pid" -ge 1 ] || break
  done
  [ "$printed" -eq 1 ]
}

# Print the one pid that identifies this session when the session lock is being
# written.
fm_harness_ancestry_pid() {
  local pids pid outermost=''
  pids=$(fm_harness_ancestry_pids) || return 1
  while IFS= read -r pid; do
    [ -n "$pid" ] && outermost=$pid
  done <<EOF
$pids
EOF
  [ -n "$outermost" ] || return 1
  printf '%s\n' "$outermost"
}

# True if $1 is a live process with exact Pi identity.
fm_harness_pid_alive() {
  local pid=$1 comm args
  kill -0 "$pid" 2>/dev/null || return 1
  comm=$(ps -o comm= -p "$pid" 2>/dev/null) || return 1
  args=$(ps -o args= -p "$pid" 2>/dev/null)
  fm_harness_process_matches "$comm" "$args"
}

# True when state dir $1 holds a session lock whose pid is ANY harness ancestor
# of the current process: this script runs inside the session that owns the
# home's fleet lock. Membership is the honest test of that question, because the
# lock owner can sit below a harness-named launcher. A missing lock, a malformed
# lock, a lock held by a harness outside this ancestry, or an ancestry that
# cannot be resolved all fail closed.
fm_session_lock_owned_by_self() {
  local state=$1 lock_pid pids pid
  lock_pid=$(cat "$state/.lock" 2>/dev/null || true)
  case "$lock_pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  pids=$(fm_harness_ancestry_pids) || return 1
  while IFS= read -r pid; do
    [ "$pid" = "$lock_pid" ] && return 0
  done <<EOF
$pids
EOF
  return 1
}
