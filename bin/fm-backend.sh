#!/usr/bin/env bash
# fm-backend.sh - Herdr-only session-provider selection, metadata, and dispatch.
#
# Herdr is the sole supported session provider. There is no runtime detection or
# fallback. New task records must explicitly bind backend=herdr; old records with
# an absent or different backend are unsupported and must be migrated explicitly.

FM_BACKEND_SCRIPT=${BASH_SOURCE[0]:-$0}
FM_BACKEND_LIB_DIR="$(cd "$(dirname "$FM_BACKEND_SCRIPT")" && pwd)"
unset FM_BACKEND_SCRIPT
FM_BACKEND_DEFAULT_ROOT="$(cd "$FM_BACKEND_LIB_DIR/.." && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-${FM_ROOT:-$FM_BACKEND_DEFAULT_ROOT}}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
FM_BACKEND_CONFIG_DIR="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
# shellcheck disable=SC2034 # Public constants consumed by sourcing callers and tests.
FM_BACKEND_KNOWN="herdr"
# shellcheck disable=SC2034 # Public constants consumed by sourcing callers and tests.
FM_BACKEND_SPAWN="herdr"

fm_backend_list_contains() {  # <list> <name>
  local list=$1 name=$2
  case "$name" in *[[:space:]]*) return 1 ;; esac
  case " $list " in *" $name "*) return 0 ;; esac
  return 1
}

fm_backend_is_known() { [ "${1:-}" = herdr ]; }

fm_backend_name() {
  local line value=herdr
  if [ -n "${FM_BACKEND:-}" ]; then
    value=$FM_BACKEND
  elif [ -f "$FM_BACKEND_CONFIG_DIR/backend" ]; then
    value=
    while IFS= read -r line || [ -n "$line" ]; do
      line=$(printf '%s' "$line" | tr -d '[:space:]')
      if [ -n "$line" ]; then value=$line; break; fi
    done < "$FM_BACKEND_CONFIG_DIR/backend"
    [ -n "$value" ] || value=herdr
  fi
  if [ "$value" != herdr ]; then
    echo "error: unsupported session provider '$value'; this edition requires backend=herdr and never falls back" >&2
    return 1
  fi
  printf 'herdr'
}

fm_backend_validate() {
  [ "${1:-}" = herdr ] && return 0
  echo "error: unsupported session provider '${1:-absent}'; this edition supports only herdr and never falls back" >&2
  return 1
}

fm_backend_validate_spawn() { fm_backend_validate "$1"; }

fm_backend_required_tools() {
  [ "${1:-}" = herdr ] || return 1
  printf '%s' 'herdr jq treehouse'
}

fm_backend_required_tool_available() {
  local backend=$1 tool=$2 required
  required=$(fm_backend_required_tools "$backend") || return 1
  fm_backend_list_contains "$required" "$tool" || return 1
  command -v "$tool" >/dev/null 2>&1
}

fm_meta_get() {
  local meta=$1 key=$2
  [ -f "$meta" ] || return 0
  grep "^$key=" "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

fm_backend_meta_exact_value() {
  local meta=$1 key=$2 count value
  count=$(grep -c "^$key=" "$meta" 2>/dev/null || true)
  [ "$count" -eq 1 ] || return 1
  value=$(grep "^$key=" "$meta" | cut -d= -f2-)
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

# Absence and ambiguity are deliberately not reinterpreted as Herdr.
fm_backend_of_meta() {
  local value
  value=$(fm_backend_meta_exact_value "$1" backend 2>/dev/null || true)
  printf '%s' "${value:-unsupported-or-ambiguous}"
}

fm_backend_target_of_meta() {
  fm_backend_meta_exact_value "$1" window 2>/dev/null || true
}

fm_backend_endpoint_atom_valid() {
  case "$1" in ''|*[!A-Za-z0-9._@%+-]*) return 1 ;; esac
}

fm_backend_endpoint_child_valid() {
  local workspace=$1 child=$2 suffix
  case "$child" in "$workspace":*) suffix=${child#*:} ;; *) return 1 ;; esac
  fm_backend_endpoint_atom_valid "$suffix"
}

fm_backend_validate_task_endpoint() {
  local meta=$1 id=$2 backend window worktree project binding session workspace tab pane
  FM_BACKEND_VALIDATED_BACKEND=
  FM_BACKEND_VALIDATED_TARGET=
  FM_BACKEND_VALIDATED_WORKSPACE=
  FM_BACKEND_VALIDATED_TAB=
  [ -f "$meta" ] && [ ! -L "$meta" ] || {
    echo "REFUSED: task $id has no regular endpoint metadata at $meta; preserving task state." >&2
    return 1
  }
  case "$id" in ''|*[!A-Za-z0-9._-]*)
    echo "REFUSED: task endpoint identity has an invalid task id; preserving task state." >&2; return 1 ;;
  esac
  backend=$(fm_backend_meta_exact_value "$meta" backend 2>/dev/null || true)
  if [ "$backend" != herdr ]; then
    echo "REFUSED: task $id records session provider '${backend:-absent}'; explicit migration to Herdr metadata is required and no fallback will be created." >&2
    return 1
  fi
  window=$(fm_backend_meta_exact_value "$meta" window) || {
    echo "REFUSED: task $id has a missing, empty, or ambiguous Herdr endpoint; preserving task state." >&2; return 1; }
  worktree=$(fm_backend_meta_exact_value "$meta" worktree) || {
    echo "REFUSED: task $id has a missing, empty, or ambiguous worktree identity; preserving task state." >&2; return 1; }
  project=$(fm_backend_meta_exact_value "$meta" project) || {
    echo "REFUSED: task $id has a missing, empty, or ambiguous project identity; preserving task state." >&2; return 1; }
  : "$worktree" "$project"
  binding=$(fm_backend_meta_exact_value "$meta" endpoint_task_id) || {
    echo "REFUSED: Herdr endpoint metadata for task $id lacks an exact task binding; preserving task state." >&2; return 1; }
  [ "$binding" = "$id" ] || {
    echo "REFUSED: endpoint metadata belongs to task $binding, not $id; preserving task state." >&2; return 1; }
  session=$(fm_backend_meta_exact_value "$meta" herdr_session) || session=
  workspace=$(fm_backend_meta_exact_value "$meta" herdr_workspace_id) || workspace=
  tab=$(fm_backend_meta_exact_value "$meta" herdr_tab_id) || tab=
  pane=$(fm_backend_meta_exact_value "$meta" herdr_pane_id) || pane=
  if [ -z "$session" ] || [ -z "$workspace" ] || [ -z "$tab" ] || [ -z "$pane" ] \
    || [ "$window" != "$session:$pane" ] \
    || ! fm_backend_endpoint_atom_valid "$session" \
    || ! fm_backend_endpoint_atom_valid "$workspace" \
    || ! fm_backend_endpoint_child_valid "$workspace" "$tab" \
    || ! fm_backend_endpoint_child_valid "$workspace" "$pane"; then
    echo "REFUSED: Herdr endpoint metadata for task $id is malformed or inconsistent; preserving task state." >&2
    return 1
  fi
  # shellcheck disable=SC2034 # Output globals consumed by sourcing callers.
  FM_BACKEND_VALIDATED_BACKEND=herdr
  # shellcheck disable=SC2034 # Output globals consumed by sourcing callers.
  FM_BACKEND_VALIDATED_TARGET=$window
  # shellcheck disable=SC2034 # Output globals consumed by sourcing callers.
  FM_BACKEND_VALIDATED_WORKSPACE=$workspace
  # shellcheck disable=SC2034 # Output globals consumed by sourcing callers.
  FM_BACKEND_VALIDATED_TAB=$tab
}

fm_backend_live_pane_matches_task_endpoint() {  # <meta> <task-id> <pane-json>
  local meta=$1 id=$2 live=$3 session workspace tab pane tabs label
  fm_backend_validate_task_endpoint "$meta" "$id" || return 1
  session=$(fm_backend_meta_exact_value "$meta" herdr_session)
  workspace=$FM_BACKEND_VALIDATED_WORKSPACE
  tab=$FM_BACKEND_VALIDATED_TAB
  pane=$(fm_backend_meta_exact_value "$meta" herdr_pane_id)
  label="fm-$id"
  if ! printf '%s' "$live" | jq -e --arg workspace "$workspace" --arg tab "$tab" --arg pane "$pane" \
    '.result.pane.workspace_id == $workspace and .result.pane.tab_id == $tab and .result.pane.pane_id == $pane' >/dev/null 2>&1; then
    echo "REFUSED: live Herdr pane identity is malformed or contradicts the recorded workspace, tab, or pane for task $id; no endpoint action was attempted." >&2
    return 1
  fi
  if ! tabs=$(fm_backend_herdr_cli "$session" tab list --workspace "$workspace" 2>/dev/null) \
    || ! printf '%s' "$tabs" | jq -e --arg tab "$tab" --arg label "$label" \
      '(.result.tabs | type) == "array" and ([.result.tabs[] | select(.tab_id == $tab and .label == $label)] | length) == 1' >/dev/null 2>&1; then
    echo "REFUSED: live Herdr tab identity is missing, ambiguous, or no longer bound to task $id; no endpoint action was attempted." >&2
    return 1
  fi
}

fm_backend_validate_active_task_endpoint() {
  local meta=$1 id=$2 session pane live state=0
  fm_backend_validate_task_endpoint "$meta" "$id" || return 1
  session=$(fm_backend_meta_exact_value "$meta" herdr_session)
  pane=$(fm_backend_meta_exact_value "$meta" herdr_pane_id)
  fm_backend_source herdr || return 1
  fm_backend_herdr_version_check || return 1
  fm_backend_herdr_server_running "$session" >/dev/null || state=$?
  if [ "$state" -ne 0 ]; then
    [ "$state" -ne 1 ] || echo "REFUSED: Herdr session '$session' is not running; task $id is unreachable and no endpoint action was attempted." >&2
    return 1
  fi
  if ! live=$(fm_backend_herdr_cli "$session" pane get "$pane" 2>/dev/null); then
    echo "REFUSED: Herdr pane '$pane' in session '$session' is unreachable for task $id; no endpoint action was attempted." >&2
    return 1
  fi
  fm_backend_live_pane_matches_task_endpoint "$meta" "$id" "$live"
}

fm_backend_meta_for_window() {
  local target=$1 state=$2 meta window match= count=0
  for meta in "$state"/*.meta; do
    [ -e "$meta" ] || continue
    window=$(fm_backend_meta_exact_value "$meta" window 2>/dev/null || true)
    [ -n "$window" ] && [ "$window" = "$target" ] || continue
    match=$meta
    count=$((count + 1))
  done
  [ "$count" -eq 1 ] || return 1
  printf '%s' "$match"
}

fm_backend_task_id_for_selector() {
  local raw=$1 state=$2 id
  case "$raw" in *:*) return 1 ;; esac
  if [ -f "$state/$raw.meta" ]; then printf '%s' "$raw"; return 0; fi
  case "$raw" in fm-*) id=${raw#fm-}; [ -f "$state/$id.meta" ] || return 1; printf '%s' "$id" ;; *) return 1 ;; esac
}

fm_backend_meta_for_selector() {
  local id
  id=$(fm_backend_task_id_for_selector "$1" "$2") || return 1
  printf '%s/%s.meta' "$2" "$id"
}

fm_backend_of_selector() {
  local raw=$1 resolved=$2 state=$3 meta
  meta=$(fm_backend_meta_for_selector "$raw" "$state" 2>/dev/null || true)
  [ -n "$meta" ] || meta=$(fm_backend_meta_for_window "$resolved" "$state" 2>/dev/null || true)
  [ -n "$meta" ] || { printf 'legacy-unrecorded'; return 0; }
  fm_backend_of_meta "$meta"
}

fm_backend_expected_label_of_selector() {
  local id
  id=$(fm_backend_task_id_for_selector "$1" "$2" 2>/dev/null || true)
  [ -n "$id" ] && printf 'fm-%s' "$id"
}

fm_backend_resolve_selector() {
  local raw=$1 state=$2 meta id
  meta=$(fm_backend_meta_for_selector "$raw" "$state" 2>/dev/null || true)
  if [ -z "$meta" ]; then
    echo "error: no task metadata for '$raw'; ad hoc or legacy endpoint selection is unsupported in the Herdr-only edition" >&2
    return 1
  fi
  id=$(basename "$meta" .meta)
  fm_backend_validate_active_task_endpoint "$meta" "$id" || return 1
  printf '%s' "$FM_BACKEND_VALIDATED_TARGET"
}

fm_backend_source() {
  fm_backend_validate "$1" || return 1
  if [ -z "${_FM_BACKEND_HERDR_SOURCED:-}" ]; then
    # shellcheck source=/dev/null
    . "$FM_BACKEND_LIB_DIR/backends/herdr.sh" || return 1
    _FM_BACKEND_HERDR_SOURCED=1
  fi
}

fm_backend_validate_supervisor_endpoint() {  # <backend> <target>
  local backend=$1 target=$2 session pane live state=0
  fm_backend_source "$backend" || return 1
  session=${target%%:*}
  pane=${target#*:}
  [ -n "$session" ] && [ -n "$pane" ] && [ "$pane" != "$target" ] \
    && fm_backend_endpoint_atom_valid "$session" \
    && fm_backend_endpoint_child_valid "${pane%%:*}" "$pane" || {
      echo "REFUSED: supervisor Herdr endpoint '$target' is malformed; no endpoint action was attempted." >&2
      return 1
    }
  fm_backend_herdr_version_check || return 1
  fm_backend_herdr_server_running "$session" >/dev/null || state=$?
  if [ "$state" -ne 0 ]; then
    [ "$state" -ne 1 ] || echo "REFUSED: supervisor Herdr session '$session' is not running; no endpoint action was attempted." >&2
    return 1
  fi
  live=$(fm_backend_herdr_cli "$session" pane get "$pane" 2>/dev/null) || {
    echo "REFUSED: supervisor Herdr pane '$pane' in session '$session' is unreachable; no endpoint action was attempted." >&2
    return 1
  }
  printf '%s' "$live" | jq -e --arg pane "$pane" \
    '.result.pane.pane_id == $pane and (.result.pane.workspace_id | type) == "string" and (.result.pane.workspace_id | length) > 0 and (.result.pane.tab_id | type) == "string" and (.result.pane.tab_id | length) > 0' >/dev/null 2>&1 || {
      echo "REFUSED: live supervisor Herdr pane identity is malformed or contradicts '$target'; no endpoint action was attempted." >&2
      return 1
    }
}

fm_backend_validate_task_operation() {  # <backend> <target> [expected-label] [explicit-meta]
  local backend=$1 target=$2 label=${3:-} explicit_meta=${4:-} id meta
  if [ -z "$label" ]; then
    fm_backend_validate_supervisor_endpoint "$backend" "$target"
    return
  fi
  fm_backend_validate "$backend" || return 1
  case "$label" in fm-?*) id=${label#fm-} ;; *) return 1 ;; esac
  if [ -n "$explicit_meta" ]; then
    meta=$explicit_meta
  else
    meta="$FM_HOME/state/$id.meta"
  fi
  fm_backend_validate_active_task_endpoint "$meta" "$id" || return 1
  if [ "$FM_BACKEND_VALIDATED_TARGET" != "$target" ]; then
    echo "REFUSED: Herdr endpoint '$target' contradicts the recorded endpoint for task $id; no endpoint action was attempted." >&2
    return 1
  fi
}

fm_backend_capture() {
  local backend=$1 target=$2 lines=${3:-} label=${4:-} explicit_meta=${5:-}
  fm_backend_validate_task_operation "$backend" "$target" "$label" "$explicit_meta" \
    && fm_backend_herdr_capture "$target" "$lines"
}
fm_backend_send_key() {
  local backend=$1 target=$2 key=$3 label=${4:-} explicit_meta=${5:-}
  fm_backend_validate_task_operation "$backend" "$target" "$label" "$explicit_meta" \
    && fm_backend_herdr_send_key "$target" "$key"
}
fm_backend_send_text_submit() {
  local backend=$1 target=$2 text=$3 retries=${4:-} sleep_s=${5:-} settle=${6:-} label=${7:-} explicit_meta=${8:-}
  fm_backend_validate_task_operation "$backend" "$target" "$label" "$explicit_meta" \
    && fm_backend_herdr_send_text_submit "$target" "$text" "$retries" "$sleep_s" "$settle"
}
fm_backend_kill() { local backend=$1; shift; [ -n "${1:-}" ] || return 1; fm_backend_source "$backend" && fm_backend_herdr_kill "$@"; }
fm_backend_busy_state() {
  local backend=$1 target=$2 label=${3:-}
  fm_backend_validate_task_operation "$backend" "$target" "$label" >/dev/null 2>&1 \
    || { printf 'unknown'; return 0; }
  fm_backend_herdr_busy_state "$target"
}
fm_backend_composer_state() {
  local backend=$1 target=$2 label=${3:-} explicit_meta=${4:-}
  fm_backend_validate_task_operation "$backend" "$target" "$label" "$explicit_meta" >/dev/null 2>&1 \
    || { printf 'unknown'; return 0; }
  fm_backend_herdr_composer_state "$target"
}

fm_backend_target_exists() {
  local backend=$1 target=$2 label=${3:-} session pane live id meta
  fm_backend_source "$backend" || return 1
  session=${target%%:*}; pane=${target#*:}
  [ -n "$session" ] && [ -n "$pane" ] && [ "$pane" != "$target" ] || return 1
  live=$(fm_backend_herdr_cli "$session" pane get "$pane" 2>/dev/null) || return 1
  [ -n "$label" ] || return 0
  id=${label#fm-}
  meta="$FM_HOME/state/$id.meta"
  fm_backend_live_pane_matches_task_endpoint "$meta" "$id" "$live" >/dev/null 2>&1
}

fm_backend_agent_state() { local backend=$1; shift; fm_backend_source "$backend" >/dev/null 2>&1 || { printf 'unverified'; return 0; }; fm_backend_herdr_agent_state "$@"; }
fm_backend_agent_alive() { case "$(fm_backend_agent_state "$1" "$2")" in alive) printf alive ;; dead|missing) printf dead ;; *) printf unknown ;; esac; }
fm_backend_has_push() { [ "${1:-}" = herdr ]; }
fm_backend_events_capable() { local backend=$1; shift; fm_backend_source "$backend" && fm_backend_herdr_events_capable "$@"; }
fm_backend_wait_transition() { local backend=$1; shift; fm_backend_source "$backend" >/dev/null 2>&1 || return 2; fm_backend_herdr_wait_transition "$@"; }
fm_backend_commit_transition() { local backend=$1; shift; fm_backend_source "$backend" && fm_backend_herdr_commit_transition "$@"; }
fm_backend_clear_transition() { local backend=$1; shift; fm_backend_source "$backend" && fm_backend_herdr_clear_transition "$@"; }

# Herdr is a session provider only; Treehouse owns task copies.
fm_backend_remove_worktree() { echo "error: Herdr does not own task worktrees" >&2; return 1; }
fm_backend_worktree_path() { echo "error: Herdr does not own task worktrees" >&2; return 1; }
