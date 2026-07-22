#!/usr/bin/env bash
# fm-backend.sh - Herdr-only session-provider operations for Firstmate.
#
# Herdr owns every task endpoint.
# Treehouse remains the worktree provider for crewmates and scouts.
# This file keeps the endpoint abstraction shared by send, peek, supervision,
# recovery, fleet snapshots, and cleanup while deliberately exposing no
# provider selection or provider dispatch surface.

FM_BACKEND_SCRIPT=${BASH_SOURCE[0]:-$0}
FM_BACKEND_LIB_DIR="$(cd "$(dirname "$FM_BACKEND_SCRIPT")" && pwd)"
unset FM_BACKEND_SCRIPT
FM_BACKEND_DEFAULT_ROOT="$(cd "$FM_BACKEND_LIB_DIR/.." && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-${FM_ROOT:-$FM_BACKEND_DEFAULT_ROOT}}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"

# shellcheck source=bin/backends/herdr.sh
. "$FM_BACKEND_LIB_DIR/backends/herdr.sh"

# Harness busy footers used only to corroborate Herdr's semantic agent state
# while a foreground tool call is still rendering an active TUI.
# shellcheck disable=SC2034 # Sourced consumers read this shared default.
FM_BACKEND_BUSY_REGEX_DEFAULT='esc (to )?interrupt|Working\.\.\.|Ctrl\+c:cancel'

fm_backend_legacy_setting_reason() {  # [config-dir]
  local config=${1:-$FM_HOME/config}
  if [ "${FM_BACKEND+x}" = x ]; then
    printf '%s' "FM_BACKEND is obsolete; unset it because Herdr is Firstmate's only session provider"
    return 0
  fi
  if [ -e "$config/backend" ] || [ -L "$config/backend" ]; then
    printf '%s' "config/backend is obsolete; remove it because Herdr is Firstmate's only session provider"
    return 0
  fi
  return 1
}

fm_backend_refuse_legacy_setting() {  # [config-dir]
  local reason
  reason=$(fm_backend_legacy_setting_reason "${1:-$FM_HOME/config}") || return 0
  echo "error: $reason" >&2
  return 1
}

FM_BACKEND_LOAD_MODE=${1:-operational}
case "$FM_BACKEND_LOAD_MODE" in
  operational) fm_backend_refuse_legacy_setting || exit 1 ;;
  diagnostic|afk-recovery) ;;
  *) echo "error: invalid backend load mode" >&2; exit 2 ;;
esac
unset FM_BACKEND_LOAD_MODE

# Herdr's CLI and JSON parser provide the endpoint, while Treehouse provides
# isolated task worktrees.
fm_backend_required_tools() {
  printf '%s' 'herdr jq treehouse'
}

fm_backend_required_tool_available() {  # <tool>
  command -v "$1" >/dev/null 2>&1
}

# The LAST value of `key=` in <meta-file>, or empty when absent.
fm_meta_get() {  # <meta-file> <key>
  local meta=$1 key=$2
  [ -f "$meta" ] || return 0
  grep "^$key=" "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

# New metadata has no provider field because there is nothing to select.
# A legacy Herdr marker is harmless, but any other legacy provider marker must
# fail closed rather than letting Herdr interpret a foreign endpoint string.
fm_backend_meta_is_herdr() {  # <meta-file>
  local legacy
  legacy=$(fm_meta_get "$1" backend)
  case "$legacy" in
    ''|herdr) return 0 ;;
    *)
      echo "error: $1 records a removed session provider; retire or migrate that task before operating it with this Firstmate version" >&2
      return 1
      ;;
  esac
}

fm_backend_target_of_meta() {  # <meta-file>
  local meta=$1 window
  fm_backend_meta_is_herdr "$meta" || return 1
  window=$(fm_meta_get "$meta" window)
  [ -n "$window" ] && printf '%s' "$window"
}

fm_backend_meta_for_window() {  # <target> <state-dir>
  local target=$1 state=$2 meta window
  for meta in "$state"/*.meta; do
    [ -e "$meta" ] || continue
    fm_backend_meta_is_herdr "$meta" >/dev/null 2>&1 || continue
    window=$(fm_meta_get "$meta" window)
    [ -n "$window" ] && [ "$window" = "$target" ] || continue
    printf '%s' "$meta"
    return 0
  done
  return 1
}

fm_backend_task_id_for_selector() {  # <raw-target> <state-dir>
  local raw=$1 state=$2 id
  case "$raw" in
    *:*) return 1 ;;
  esac
  if [ -f "$state/$raw.meta" ]; then
    printf '%s' "$raw"
    return 0
  fi
  case "$raw" in
    fm-*)
      id=${raw#fm-}
      [ -f "$state/$id.meta" ] || return 1
      printf '%s' "$id"
      return 0
      ;;
  esac
  return 1
}

fm_backend_meta_for_selector() {  # <raw-target> <state-dir>
  local raw=$1 state=$2 id
  id=$(fm_backend_task_id_for_selector "$raw" "$state") || return 1
  printf '%s/%s.meta' "$state" "$id"
}

fm_backend_expected_label_of_selector() {  # <raw-target> <state-dir>
  local raw=$1 state=$2 id
  id=$(fm_backend_task_id_for_selector "$raw" "$state" 2>/dev/null || true)
  [ -n "$id" ] && printf 'fm-%s' "$id"
  return 0
}

# Resolve task ids through durable metadata, preserve an explicit
# <session>:<pane-id> target, or resolve a bare live Herdr task label.
fm_backend_resolve_selector() {  # <raw-target> <state-dir>
  local raw=$1 state=$2 meta window
  case "$raw" in
    *:*)
      printf '%s' "$raw"
      return 0
      ;;
  esac
  meta=$(fm_backend_meta_for_selector "$raw" "$state" 2>/dev/null || true)
  if [ -n "$meta" ]; then
    window=$(fm_backend_target_of_meta "$meta") || return 1
    [ -n "$window" ] || { echo "error: no Herdr target recorded in $meta" >&2; return 1; }
    printf '%s' "$window"
    return 0
  fi
  case "$raw" in
    fm-*)
      echo "error: no metadata for $raw in $state; pass <session>:<pane-id> to target a pane outside this Firstmate home" >&2
      return 1
      ;;
  esac
  meta=$(fm_backend_meta_for_window "$raw" "$state" 2>/dev/null || true)
  if [ -n "$meta" ]; then
    window=$(fm_backend_target_of_meta "$meta") || return 1
    [ -n "$window" ] || { echo "error: no Herdr target recorded in $meta" >&2; return 1; }
    printf '%s' "$window"
    return 0
  fi
  fm_backend_herdr_resolve_bare_selector "$raw"
}

# The wrappers below keep one endpoint contract for all Firstmate consumers.
fm_backend_capture() {  # <target> <lines> [expected-label]
  fm_backend_herdr_capture "$@"
}

fm_backend_send_key() {  # <target> <key> [expected-label]
  fm_backend_herdr_send_key "$@"
}

fm_backend_send_text_submit() {  # <target> <text> <retries> <enter-sleep> <settle> [expected-label]
  fm_backend_herdr_send_text_submit "$@"
}

fm_backend_kill() {  # <target>
  fm_backend_herdr_kill "$1"
}

fm_backend_busy_state() {  # <target>
  fm_backend_herdr_busy_state "$@"
}

fm_backend_composer_state() {  # <target> -> empty|pending|unknown
  fm_backend_herdr_composer_state "$@"
}

# Read-only pane presence check that never starts a Herdr server.
fm_backend_target_exists() {  # <target> [expected-label]
  local target=$1 session pane
  session=${target%%:*}
  pane=${target#*:}
  [ -n "$session" ] && [ -n "$pane" ] && [ "$pane" != "$target" ] || return 1
  fm_backend_herdr_cli "$session" pane get "$pane" >/dev/null 2>&1
}

# Confident agent-process liveness, distinct from pane presence.
fm_backend_agent_alive() {  # <target>
  fm_backend_herdr_agent_alive "$1"
}

# Herdr exposes native transition events, with the watcher's polling path as
# the fail-closed fallback when the installed protocol cannot provide them.
fm_backend_events_capable() {  # <session>
  fm_backend_herdr_events_capable "$@"
}

fm_backend_wait_transition() {  # <session> <timeout-secs> <state-dir> <pane-window...>
  fm_backend_herdr_wait_transition "$@"
}

fm_backend_commit_transition() {  # <state-dir> <session> <record>
  fm_backend_herdr_commit_transition "$@"
}

fm_backend_clear_transition() {  # <state-dir> <window>
  fm_backend_herdr_clear_transition "$@"
}
