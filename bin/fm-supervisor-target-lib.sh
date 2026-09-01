#!/usr/bin/env bash
# fm-supervisor-target-lib.sh - Herdr supervisor-pane discovery.
#
# Away mode must target Firstmate's exact Herdr pane. There is no terminal
# provider inference or fallback: explicit values must name Herdr, otherwise the
# process must carry Herdr's injected pane identity.

# An explicit target is accepted only with an explicit or implicit Herdr
# provider. Ambient discovery requires both Herdr's environment marker and pane
# id, then composes the exact named-session endpoint.
discover_supervisor_target() {
  if [ -n "${FM_SUPERVISOR_TARGET:-}" ]; then
    [ "${FM_SUPERVISOR_BACKEND:-herdr}" = herdr ] || {
      echo "error: supervisor provider '${FM_SUPERVISOR_BACKEND:-}' is unsupported; Herdr is required" >&2
      return 1
    }
    printf '%s' "$FM_SUPERVISOR_TARGET"
    return 0
  fi
  if [ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_PANE_ID:-}" ]; then
    printf '%s:%s' "${HERDR_SESSION:-default}" "$HERDR_PANE_ID"
    return 0
  fi
  echo "error: cannot prove the supervisor's Herdr pane identity; set FM_SUPERVISOR_TARGET or run inside Herdr" >&2
  return 1
}

discover_supervisor_backend() {
  if [ -n "${FM_SUPERVISOR_BACKEND:-}" ] && [ "$FM_SUPERVISOR_BACKEND" != herdr ]; then
    echo "error: supervisor provider '$FM_SUPERVISOR_BACKEND' is unsupported; Herdr is required" >&2
    return 1
  fi
  if [ -n "${FM_SUPERVISOR_TARGET:-}" ] || { [ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_PANE_ID:-}" ]; }; then
    printf 'herdr'
    return 0
  fi
  echo "error: supervisor provider is not provably Herdr; no fallback is available" >&2
  return 1
}
