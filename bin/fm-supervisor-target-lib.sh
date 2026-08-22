#!/usr/bin/env bash
# fm-supervisor-target-lib.sh - the single owner of Firstmate-pane discovery.
#
# The away-mode daemon must inject into the pane running Firstmate, not into the
# daemon pane that bin/fm-afk-launch.sh creates. Both callers therefore resolve
# the same exact Herdr target here before launching or validating anything.

# discover_supervisor_target: print the exact Herdr target for Firstmate.
# An explicit target is accepted for guarded launch/testing. Otherwise Herdr's
# pane environment is required; there is no guessed target or session fallback.
discover_supervisor_target() {
  if [ -n "${FM_SUPERVISOR_BACKEND:-}" ]; then
    if [ "$FM_SUPERVISOR_BACKEND" = tmux ]; then
      echo "error: tmux supervision is retired; remove FM_SUPERVISOR_BACKEND and run Firstmate in Herdr" >&2
    else
      echo "error: FM_SUPERVISOR_BACKEND is retired because Herdr is the sole session path; remove it" >&2
    fi
    return 1
  fi
  if [ -n "${TMUX:-}" ] || [ -n "${TMUX_PANE:-}" ]; then
    echo "error: tmux supervision is retired; leave the tmux environment and run Firstmate in Herdr" >&2
    return 1
  fi
  if [ -n "${FM_SUPERVISOR_TARGET:-}" ]; then
    case "$FM_SUPERVISOR_TARGET" in
      *:*:*) printf '%s' "$FM_SUPERVISOR_TARGET"; return 0 ;;
      *)
        echo "error: FM_SUPERVISOR_TARGET must be an exact Herdr <session>:<pane-id> target" >&2
        return 1
        ;;
    esac
  fi
  if [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ]; then
    printf '%s:%s' "${HERDR_SESSION:-default}" "$HERDR_PANE_ID"
    return 0
  fi
  echo "error: Firstmate must run inside a reachable Herdr pane; no supervisor target was available" >&2
  return 1
}
