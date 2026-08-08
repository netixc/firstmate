#!/usr/bin/env bash
# Session-open entry point for harnesses that RUN the digest instead of asking
# the agent to.
# It is the one command those harnesses' session-open adapters invoke, and it
# decides, from the session-open source, whether this open needs the full
# digest, a context re-emit, or nothing at all.
#
# Why running beats nudging: bin/fm-sessionstart-nudge.sh can only ASK the
# agent to take the helm, and an agent can defer that, including when a
# first-command skill has its own read-only path.
# When the harness injects hook stdout into model context, running the digest
# here removes that discretion - the helm is taken before the model's first
# turn, whatever the first turn is.
#
# Usage: fm-sessionstart-run.sh [--source <source>]
#   --source  The harness's own session-open source.
#             Pi passes this source directly from its session lifecycle event.
#             An unreadable or unrecognized source is treated as `startup`,
#             because taking the helm redundantly is cheap and idempotent while
#             not taking it is the whole bug.
#
# Source routing (see docs/sessionstart-nudge.md for Pi lifecycle names):
#   startup, new            full digest - this process has not taken the helm
#   clear, compact          `--reemit` digest only when this lock owner recorded
#                           a completed full startup; otherwise a full digest,
#                           so a startup killed mid-sweep is finished first
#   resume, reload, fork    delegate to the nudge wrapper.
#                           Prior context is restored on these, so re-running
#                           is redundant when this process still holds the lock
#                           (the nudge stays silent) and a plain instruction is
#                           enough when a new process resumed an old session
#                           (the nudge fires).
#
# Every path exits 0 so Pi can surface startup diagnostics as digest text
# rather than turning a recoverable bootstrap problem into a session refusal.
# A lock another live session holds, broken GitHub auth, and a truncated digest
# are all reported inside the digest for exactly that reason.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
COMPLETION_FILE="$STATE/.session-start-complete"

# shellcheck source=bin/fm-gate-refuse-lib.sh
. "$SCRIPT_DIR/fm-gate-refuse-lib.sh"
# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"
# shellcheck source=bin/fm-session-lock-lib.sh
. "$SCRIPT_DIR/fm-session-lock-lib.sh"

SOURCE=
while [ $# -gt 0 ]; do
  case "$1" in
    --source)
      SOURCE=${2:-}
      # A bare trailing --source leaves the source empty rather than aborting,
      # so a malformed call still falls through to taking the helm.
      if [ $# -ge 2 ]; then shift 2; else shift; fi
      ;;
    --source=*) SOURCE=${1#--source=}; shift ;;
    *) shift ;;
  esac
done

# The same two eligibility owners the nudge wrapper uses, so a no-mistakes gate
# agent and an unmarked task worktree can never run a session start for a home
# they do not own.
fm_is_gate_agent "$FM_ROOT" && exit 0
fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0

session_start_completed() {
  local lock_pid completion_pid
  [ -f "$STATE/.lock" ] && [ ! -L "$STATE/.lock" ] || return 1
  [ -f "$COMPLETION_FILE" ] && [ ! -L "$COMPLETION_FILE" ] || return 1
  fm_session_lock_owned_by_self "$STATE" || return 1
  lock_pid=$(cat "$STATE/.lock" 2>/dev/null) || return 1
  completion_pid=$(cat "$COMPLETION_FILE" 2>/dev/null) || return 1
  case "$lock_pid" in ''|*[!0-9]*) return 1 ;; esac
  [ "$completion_pid" = "$lock_pid" ]
}


case "$SOURCE" in
  resume|reload|fork)
    exec "$SCRIPT_DIR/fm-sessionstart-nudge.sh"
    ;;
  clear|compact)
    if session_start_completed; then
      "$SCRIPT_DIR/fm-session-start.sh" --reemit || true
    else
      "$SCRIPT_DIR/fm-session-start.sh" || true
    fi
    ;;
  *)
    "$SCRIPT_DIR/fm-session-start.sh" || true
    ;;
esac
exit 0
