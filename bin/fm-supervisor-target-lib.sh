#!/usr/bin/env bash
# fm-supervisor-target-lib.sh - the single owner of supervisor-pane discovery.
#
# The away-mode daemon and its launcher must identify the Herdr pane running
# Firstmate so escalation injection never targets the daemon's own pane.
# An explicit override wins, then the Herdr identity injected into the running
# Firstmate process.
# No guessed target or alternate transport fallback is permitted.

# discover_supervisor_target: print the exact Herdr target or return 1 when no
# authoritative target is available.
discover_supervisor_target() {
  if [ -n "${FM_SUPERVISOR_TARGET:-}" ]; then
    printf '%s' "$FM_SUPERVISOR_TARGET"
    return 0
  fi
  if [ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_PANE_ID:-}" ]; then
    printf '%s:%s' "${HERDR_SESSION:-default}" "$HERDR_PANE_ID"
    return 0
  fi
  return 1
}
