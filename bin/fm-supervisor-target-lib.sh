#!/usr/bin/env bash
# fm-supervisor-target-lib.sh - the single owner of Herdr supervisor-pane discovery.
#
# The away-mode daemon injects captain-relevant escalations into the pane that
# runs Firstmate. The separate non-visible daemon launcher must resolve that
# pane before creating its own Herdr pane, then pass the exact target through
# FM_SUPERVISOR_TARGET so the daemon cannot discover itself.

# Resolve the pane running Firstmate. An explicit override wins; otherwise a
# process launched inside Herdr composes the target from the injected session
# and pane markers. No guessed fallback is safe.
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
