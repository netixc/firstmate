#!/usr/bin/env bash
# fm-supervisor-target-lib.sh - exact Herdr supervisor identity discovery.
#
# Away mode targets one exact supervisor hierarchy, separate from worker task
# metadata. Explicit callers carry every identity axis; ambient discovery uses
# only Herdr's complete injected hierarchy. Missing or partial identity is never
# inferred and there is no provider or default-session fallback.

discover_supervisor_identity() {
  local backend session workspace tab pane target
  if [ -n "${FM_SUPERVISOR_TARGET:-}" ] || [ -n "${FM_SUPERVISOR_BACKEND:-}" ] \
    || [ -n "${FM_SUPERVISOR_SESSION:-}" ] || [ -n "${FM_SUPERVISOR_WORKSPACE_ID:-}" ] \
    || [ -n "${FM_SUPERVISOR_TAB_ID:-}" ] || [ -n "${FM_SUPERVISOR_PANE_ID:-}" ]; then
    backend=${FM_SUPERVISOR_BACKEND:-}
    session=${FM_SUPERVISOR_SESSION:-}
    workspace=${FM_SUPERVISOR_WORKSPACE_ID:-}
    tab=${FM_SUPERVISOR_TAB_ID:-}
    pane=${FM_SUPERVISOR_PANE_ID:-}
    target=${FM_SUPERVISOR_TARGET:-}
    [ "$backend" = herdr ] || {
      echo "error: supervisor provider '${backend:-absent}' is unsupported; Herdr is required" >&2
      return 1
    }
    [ -n "$session" ] && [ -n "$workspace" ] && [ -n "$tab" ] && [ -n "$pane" ] && [ -n "$target" ] \
      && [ "$target" = "$session:$pane" ] || {
        echo "error: explicit supervisor identity must carry one consistent Herdr session/workspace/tab/pane hierarchy" >&2
        return 1
      }
  elif [ "${HERDR_ENV:-}" = "1" ]; then
    backend=herdr
    session=${HERDR_SESSION:-}
    workspace=${HERDR_WORKSPACE_ID:-}
    tab=${HERDR_TAB_ID:-}
    pane=${HERDR_PANE_ID:-}
    [ -n "$session" ] && [ -n "$workspace" ] && [ -n "$tab" ] && [ -n "$pane" ] || {
      echo "error: cannot prove the supervisor's complete Herdr session/workspace/tab/pane identity" >&2
      return 1
    }
    target="$session:$pane"
  else
    echo "error: cannot prove the supervisor's complete Herdr identity; pass the exact supervisor hierarchy or run inside Herdr" >&2
    return 1
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s' "$backend" "$session" "$workspace" "$tab" "$pane" "$target"
}

discover_supervisor_target() {
  local identity backend session workspace tab pane target
  identity=$(discover_supervisor_identity) || return 1
  IFS=$'\t' read -r backend session workspace tab pane target <<EOF
$identity
EOF
  printf '%s' "$target"
}

discover_supervisor_backend() {
  local identity backend session workspace tab pane target
  identity=$(discover_supervisor_identity) || return 1
  IFS=$'\t' read -r backend session workspace tab pane target <<EOF
$identity
EOF
  printf '%s' "$backend"
}
