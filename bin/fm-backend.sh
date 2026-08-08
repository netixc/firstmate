#!/usr/bin/env bash
# fm-backend.sh - Herdr workspace metadata, selector resolution, and operation helpers.
#
# Herdr is Firstmate's sole terminal workspace layer.
# Backend metadata names Herdr explicitly so cleanup refuses stale or malformed
# endpoint records rather than reinterpreting them.

FM_BACKEND_SCRIPT=${BASH_SOURCE[0]:-$0}
FM_BACKEND_LIB_DIR="$(cd "$(dirname "$FM_BACKEND_SCRIPT")" && pwd)"
unset FM_BACKEND_SCRIPT
FM_BACKEND_DEFAULT_ROOT="$(cd "$FM_BACKEND_LIB_DIR/.." && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-${FM_ROOT:-$FM_BACKEND_DEFAULT_ROOT}}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"

fm_backend_list_contains() {  # <list> <name>
  local list=$1 name=$2
  case "$name" in
    *[[:space:]]*) return 1 ;;
  esac
  case " $list " in
    *" $name "*) return 0 ;;
  esac
  return 1
}

fm_backend_is_known() {  # <name>
  [ "$1" = herdr ]
}

fm_backend_validate() {  # <name>
  [ "$1" = herdr ] && return 0
  echo "error: unsupported task workspace backend '$1' (Firstmate requires Herdr)" >&2
  return 1
}

fm_backend_required_tools() {  # <runtime>
  fm_backend_validate "$1" >/dev/null 2>&1 || return 1
  printf '%s' 'herdr jq treehouse'
}

fm_backend_required_tool_available() {  # <runtime> <tool>
  local runtime=$1 tool=$2 required
  required=$(fm_backend_required_tools "$runtime") || return 1
  fm_backend_list_contains "$required" "$tool" || return 1
  command -v "$tool" >/dev/null 2>&1
}

fm_meta_get() {  # <meta-file> <key>
  local meta=$1 key=$2
  [ -f "$meta" ] || return 0
  grep "^$key=" "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

# Backend metadata remains explicit so endpoint cleanup cannot adopt a stale
# record created by an unknown implementation.
fm_backend_of_meta() {  # <meta-file>
  fm_meta_get "$1" backend
}

fm_backend_target_of_meta() {  # <meta-file>
  fm_meta_get "$1" window
}

fm_backend_meta_exact_value() {  # <meta-file> <key>
  local meta=$1 key=$2 count value
  count=$(grep -c "^$key=" "$meta" 2>/dev/null || true)
  [ "$count" -eq 1 ] || return 1
  value=$(grep "^$key=" "$meta" | cut -d= -f2-)
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

fm_backend_endpoint_atom_valid() {  # <value>
  case "$1" in
    ''|*[!A-Za-z0-9._@%+-]*) return 1 ;;
  esac
}

# Validate cleanup identity entirely from durable task metadata before any
# workspace command or cleanup mutation.
fm_backend_validate_task_endpoint() {  # <meta-file> <task-id>
  local meta=$1 id=$2 backend_count backend window worktree project
  local binding_count binding recorded_session workspace tab pane
  FM_BACKEND_VALIDATED_BACKEND=
  FM_BACKEND_VALIDATED_TARGET=
  [ -f "$meta" ] && [ ! -L "$meta" ] || {
    echo "REFUSED: task $id has no regular endpoint metadata at $meta; preserving task state." >&2
    return 1
  }
  case "$id" in
    ''|*[!A-Za-z0-9._-]*)
      echo "REFUSED: task endpoint identity has an invalid task id; preserving task state." >&2
      return 1
      ;;
  esac
  window=$(fm_backend_meta_exact_value "$meta" window) || {
    echo "REFUSED: task $id has a missing, empty, or ambiguous window endpoint; preserving task state." >&2
    return 1
  }
  worktree=$(fm_backend_meta_exact_value "$meta" worktree) || {
    echo "REFUSED: task $id has a missing, empty, or ambiguous worktree identity; preserving task state." >&2
    return 1
  }
  project=$(fm_backend_meta_exact_value "$meta" project) || {
    echo "REFUSED: task $id has a missing, empty, or ambiguous project identity; preserving task state." >&2
    return 1
  }
  case "$worktree$project$window" in
    *$'\n'*|*$'\r'*|*$'\t'*)
      echo "REFUSED: task $id has malformed endpoint metadata; preserving task state." >&2
      return 1
      ;;
  esac
  backend_count=$(grep -c '^backend=' "$meta" 2>/dev/null || true)
  [ "$backend_count" -eq 1 ] || {
    echo "REFUSED: task $id has a missing or ambiguous workspace backend identity; preserving task state." >&2
    return 1
  }
  backend=$(fm_backend_meta_exact_value "$meta" backend) || backend=
  [ "$backend" = herdr ] || {
    echo "REFUSED: task $id does not identify the Herdr workspace backend; preserving task state." >&2
    return 1
  }
  binding_count=$(grep -c '^endpoint_task_id=' "$meta" 2>/dev/null || true)
  [ "$binding_count" -eq 1 ] || {
    echo "REFUSED: task $id has a missing or ambiguous endpoint task binding; preserving task state." >&2
    return 1
  }
  binding=$(fm_backend_meta_exact_value "$meta" endpoint_task_id) || {
    echo "REFUSED: task $id has an empty endpoint task binding; preserving task state." >&2
    return 1
  }
  [ "$binding" = "$id" ] || {
    echo "REFUSED: endpoint metadata belongs to task $binding, not $id; preserving task state." >&2
    return 1
  }
  recorded_session=$(fm_backend_meta_exact_value "$meta" herdr_session) || recorded_session=
  workspace=$(fm_backend_meta_exact_value "$meta" herdr_workspace_id) || workspace=
  tab=$(fm_backend_meta_exact_value "$meta" herdr_tab_id) || tab=
  pane=$(fm_backend_meta_exact_value "$meta" herdr_pane_id) || pane=
  if [ -z "$recorded_session" ] || [ -z "$workspace" ] || [ -z "$tab" ] || [ -z "$pane" ] \
    || [ "$window" != "$recorded_session:$pane" ] \
    || ! fm_backend_endpoint_atom_valid "$recorded_session" \
    || ! fm_backend_endpoint_atom_valid "$workspace" \
    || ! fm_backend_endpoint_atom_valid "${tab//:/_}" \
    || ! fm_backend_endpoint_atom_valid "${pane//:/_}"; then
    echo "REFUSED: Herdr endpoint metadata for task $id is malformed or inconsistent; preserving task state." >&2
    return 1
  fi
  # shellcheck disable=SC2034 # Output globals are consumed by sourcing callers.
  FM_BACKEND_VALIDATED_BACKEND=herdr
  # shellcheck disable=SC2034 # Output globals are consumed by sourcing callers.
  FM_BACKEND_VALIDATED_TARGET=$window
  return 0
}

fm_backend_meta_for_window() {  # <target> <state-dir>
  local target=$1 state=$2 meta window
  for meta in "$state"/*.meta; do
    [ -e "$meta" ] || continue
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

fm_backend_of_selector() {  # <raw-target> <resolved-target> <state-dir>
  local raw=$1 resolved=$2 state=$3 meta runtime
  meta=$(fm_backend_meta_for_selector "$raw" "$state" 2>/dev/null || true)
  if [ -z "$meta" ] && [ -n "$resolved" ]; then
    meta=$(fm_backend_meta_for_window "$resolved" "$state" 2>/dev/null || true)
  fi
  if [ -n "$meta" ]; then
    runtime=$(fm_backend_of_meta "$meta")
    fm_backend_validate "$runtime" >/dev/null 2>&1 || return 1
  fi
  printf 'herdr'
}

fm_backend_expected_label_of_selector() {  # <raw-target> <state-dir>
  local raw=$1 state=$2 id
  id=$(fm_backend_task_id_for_selector "$raw" "$state" 2>/dev/null || true)
  [ -n "$id" ] && printf 'fm-%s' "$id"
  return 0
}

fm_backend_source() {  # <runtime>
  fm_backend_validate "$1" || return 1
  if [ -z "${_FM_BACKEND_HERDR_SOURCED:-}" ]; then
    [ -r "$FM_BACKEND_LIB_DIR/backends/herdr.sh" ] || {
      echo "error: Herdr workspace adapter is unavailable" >&2
      return 1
    }
    # shellcheck source=/dev/null
    . "$FM_BACKEND_LIB_DIR/backends/herdr.sh" || return 1
    _FM_BACKEND_HERDR_SOURCED=1
  fi
}

# Resolve explicit endpoint strings, metadata-routed task selectors, and
# Herdr's bare live-label lookup.
fm_backend_resolve_selector() {  # <raw-target> <state-dir>
  local raw=$1 state=$2 meta target
  case "$raw" in
    *:*) printf '%s' "$raw"; return 0 ;;
  esac
  meta=$(fm_backend_meta_for_selector "$raw" "$state" 2>/dev/null || true)
  if [ -n "$meta" ]; then
    target=$(fm_backend_target_of_meta "$meta")
    [ -n "$target" ] || { echo "error: no Herdr target recorded in $meta" >&2; return 1; }
    printf '%s' "$target"
    return 0
  fi
  case "$raw" in
    fm-*)
      echo "error: no metadata for $raw in $state; pass <session>:<pane-id> only for an endpoint outside this Firstmate home" >&2
      return 1
      ;;
  esac
  meta=$(fm_backend_meta_for_window "$raw" "$state" 2>/dev/null || true)
  if [ -n "$meta" ]; then
    target=$(fm_backend_target_of_meta "$meta")
    [ -n "$target" ] || { echo "error: no Herdr target recorded in $meta" >&2; return 1; }
    printf '%s' "$target"
    return 0
  fi
  fm_backend_source herdr || return 1
  fm_backend_herdr_resolve_bare_selector "$raw"
}

fm_backend_capture() {  # <runtime> <target> <lines> [expected-label]
  local runtime=$1
  shift
  fm_backend_source "$runtime" || return 1
  fm_backend_herdr_capture "$@"
}

fm_backend_send_key() {  # <runtime> <target> <key> [expected-label]
  local runtime=$1
  shift
  fm_backend_source "$runtime" || return 1
  fm_backend_herdr_send_key "$@"
}

fm_backend_send_text_submit() {  # <runtime> <target> <text> <retries> <enter-sleep> <settle> [expected-label]
  local runtime=$1
  shift
  fm_backend_source "$runtime" || return 1
  fm_backend_herdr_send_text_submit "$@"
}

fm_backend_kill() {  # <runtime> <target>
  local runtime=$1
  shift
  [ -n "${1:-}" ] || { echo "error: refusing empty Herdr kill target" >&2; return 1; }
  fm_backend_source "$runtime" || return 1
  fm_backend_herdr_kill "$@"
}

fm_backend_busy_state() {  # <runtime> <target>
  local runtime=$1
  shift
  fm_backend_source "$runtime" || { printf 'unknown'; return 0; }
  fm_backend_herdr_busy_state "$@"
}

fm_backend_composer_state() {  # <runtime> <target>
  local runtime=$1
  shift
  fm_backend_source "$runtime" || { printf 'unknown'; return 0; }
  fm_backend_herdr_composer_state "$@"
}

fm_backend_target_exists() {  # <runtime> <target> [expected-label]
  local runtime=$1 target=$2 session pane
  fm_backend_source "$runtime" || return 1
  session=${target%%:*}
  pane=${target#*:}
  [ -n "$session" ] && [ -n "$pane" ] && [ "$pane" != "$target" ] || return 1
  fm_backend_herdr_cli "$session" pane get "$pane" >/dev/null 2>&1
}

# Recovery-grade state values are alive, dead, missing, ambiguous, unreadable,
# and unverified. Only dead and missing authorize recovery.
fm_backend_agent_state() {  # <runtime> <target>
  local runtime=$1 target=$2
  fm_backend_source "$runtime" || { printf 'unverified'; return 0; }
  fm_backend_herdr_agent_state "$target"
}

fm_backend_agent_alive() {  # <runtime> <target>
  case "$(fm_backend_agent_state "$1" "$2")" in
    alive) printf 'alive' ;;
    dead|missing) printf 'dead' ;;
    *) printf 'unknown' ;;
  esac
}

fm_backend_has_push() {  # <runtime>
  fm_backend_validate "$1" >/dev/null 2>&1
}

fm_backend_events_capable() {  # <runtime> <session>
  local runtime=$1
  shift
  fm_backend_source "$runtime" || return 1
  fm_backend_herdr_events_capable "$@"
}

fm_backend_wait_transition() {  # <runtime> <session> <timeout-secs> <state-dir> <pane-window...>
  local runtime=$1
  shift
  fm_backend_source "$runtime" || return 2
  fm_backend_herdr_wait_transition "$@"
}

fm_backend_commit_transition() {  # <runtime> <state-dir> <session> <record>
  local runtime=$1
  shift
  fm_backend_source "$runtime" || return 1
  fm_backend_herdr_commit_transition "$@"
}

fm_backend_clear_transition() {  # <runtime> <state-dir> <window>
  local runtime=$1
  shift
  fm_backend_source "$runtime" || return 1
  fm_backend_herdr_clear_transition "$@"
}
