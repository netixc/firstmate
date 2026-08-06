#!/usr/bin/env bash
# fm-backend.sh - runtime-backend selection, metadata helpers, selector
# resolution, and operation dispatch.
#
# Herdr is the automatic and default runtime backend.
# Orca is supported only when selected explicitly through --backend,
# FM_BACKEND, or config/backend.
# Unknown or stale values are rejected; no runtime environment is detected and
# no fallback backend is consulted.

FM_BACKEND_SCRIPT=${BASH_SOURCE[0]:-$0}
FM_BACKEND_LIB_DIR="$(cd "$(dirname "$FM_BACKEND_SCRIPT")" && pwd)"
unset FM_BACKEND_SCRIPT
FM_BACKEND_DEFAULT_ROOT="$(cd "$FM_BACKEND_LIB_DIR/.." && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-${FM_ROOT:-$FM_BACKEND_DEFAULT_ROOT}}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
FM_BACKEND_CONFIG_DIR="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"

FM_BACKEND_KNOWN="herdr orca"
FM_BACKEND_SPAWN="herdr orca"

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
  fm_backend_list_contains "$FM_BACKEND_KNOWN" "$1"
}

# Resolve the backend for a new spawn when no per-task --backend flag was
# supplied by the caller.
# Precedence is FM_BACKEND, config/backend, then Herdr.
# Orca is therefore explicit-only and is never detected or selected as a
# fallback.
fm_backend_name() {
  local line value
  if [ -n "${FM_BACKEND:-}" ]; then
    printf '%s' "$FM_BACKEND"
    return 0
  fi
  if [ -f "$FM_BACKEND_CONFIG_DIR/backend" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      value=$(printf '%s' "$line" | tr -d '[:space:]')
      if [ -n "$value" ]; then
        printf '%s' "$value"
        return 0
      fi
    done < "$FM_BACKEND_CONFIG_DIR/backend"
  fi
  printf 'herdr'
}

fm_backend_validate() {  # <name>
  local name=$1
  if ! fm_backend_is_known "$name"; then
    echo "error: unsupported backend '$name' (supported: $FM_BACKEND_KNOWN)" >&2
    return 1
  fi
  return 0
}

fm_backend_validate_spawn() {  # <name>
  local name=$1
  fm_backend_validate "$name" || return 1
  fm_backend_list_contains "$FM_BACKEND_SPAWN" "$name" && return 0
  echo "error: backend '$name' does not support task spawning (spawn-supported: $FM_BACKEND_SPAWN)" >&2
  return 1
}

# Backend-specific dependencies beyond the universal toolchain.
# Herdr provides sessions and Treehouse provides worktrees.
# Orca owns both task worktrees and terminal endpoints.
fm_backend_required_tools() {  # <backend>
  case "$1" in
    herdr) printf '%s' 'herdr jq treehouse' ;;
    orca) printf '%s' 'orca' ;;
    *) return 1 ;;
  esac
}

fm_backend_required_tool_available() {  # <backend> <tool>
  local backend=$1 tool=$2 required
  required=$(fm_backend_required_tools "$backend") || return 1
  fm_backend_list_contains "$required" "$tool" || return 1
  command -v "$tool" >/dev/null 2>&1
}

fm_meta_get() {  # <meta-file> <key>
  local meta=$1 key=$2
  [ -f "$meta" ] || return 0
  grep "^$key=" "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

# Runtime metadata is authoritative and must name its backend explicitly.
# A missing value remains missing so callers reject stale records rather than
# silently reinterpreting them as a current endpoint.
fm_backend_of_meta() {  # <meta-file>
  fm_meta_get "$1" backend
}

fm_backend_target_of_meta() {  # <meta-file>
  local meta=$1 backend terminal window
  backend=$(fm_backend_of_meta "$meta")
  if [ "$backend" = orca ]; then
    terminal=$(fm_meta_get "$meta" terminal)
    [ -n "$terminal" ] && { printf '%s' "$terminal"; return 0; }
  fi
  window=$(fm_meta_get "$meta" window)
  [ -n "$window" ] && printf '%s' "$window"
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
# runtime command or cleanup mutation.
fm_backend_validate_task_endpoint() {  # <meta-file> <task-id>
  local meta=$1 id=$2 backend_count backend window worktree project
  local binding_count binding recorded_session workspace tab pane terminal worktree_id
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
  case "$backend_count" in
    1) backend=$(fm_backend_meta_exact_value "$meta" backend) || backend= ;;
    *) backend= ;;
  esac
  if [ -z "$backend" ] || ! fm_backend_is_known "$backend"; then
    echo "REFUSED: task $id has an unsupported backend identity (supported: $FM_BACKEND_KNOWN); preserving task state." >&2
    return 1
  fi
  binding_count=$(grep -c '^endpoint_task_id=' "$meta" 2>/dev/null || true)
  case "$binding_count" in
    0) binding= ;;
    1)
      binding=$(fm_backend_meta_exact_value "$meta" endpoint_task_id) || {
        echo "REFUSED: task $id has an empty endpoint task binding; preserving task state." >&2
        return 1
      }
      ;;
    *)
      echo "REFUSED: task $id has an ambiguous endpoint task binding; preserving task state." >&2
      return 1
      ;;
  esac
  if [ -n "$binding" ] && [ "$binding" != "$id" ]; then
    echo "REFUSED: endpoint metadata belongs to task $binding, not $id; preserving task state." >&2
    return 1
  fi

  case "$backend" in
    herdr)
      [ "$binding" = "$id" ] || {
        echo "REFUSED: Herdr endpoint metadata for task $id lacks an exact task binding; preserving task state." >&2
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
      ;;
    orca)
      [ "$binding" = "$id" ] || {
        echo "REFUSED: Orca endpoint metadata for task $id lacks an exact task binding; preserving task state." >&2
        return 1
      }
      terminal=$(fm_backend_meta_exact_value "$meta" terminal) || terminal=
      worktree_id=$(fm_backend_meta_exact_value "$meta" orca_worktree_id) || worktree_id=
      [ -n "$terminal" ] || {
        echo "REFUSED: missing terminal in $meta; cannot close Orca endpoint; preserving task state." >&2
        return 1
      }
      [ -n "$worktree_id" ] || {
        echo "REFUSED: missing orca_worktree_id in $meta; cannot remove Orca worktree; preserving task state." >&2
        return 1
      }
      if [ "$window" != "fm-$id" ] \
        || ! fm_backend_endpoint_atom_valid "$terminal" \
        || ! fm_backend_endpoint_atom_valid "$worktree_id"; then
        echo "REFUSED: Orca endpoint metadata for task $id is malformed or inconsistent; preserving task state." >&2
        return 1
      fi
      window=$terminal
      ;;
  esac
  # shellcheck disable=SC2034 # Output globals are consumed by sourcing callers.
  FM_BACKEND_VALIDATED_BACKEND=$backend
  # shellcheck disable=SC2034 # Output globals are consumed by sourcing callers.
  FM_BACKEND_VALIDATED_TARGET=$window
  return 0
}

fm_backend_meta_for_window() {  # <target> <state-dir>
  local target=$1 state=$2 meta window terminal
  for meta in "$state"/*.meta; do
    [ -e "$meta" ] || continue
    window=$(fm_meta_get "$meta" window)
    terminal=$(fm_meta_get "$meta" terminal)
    { [ -n "$window" ] && [ "$window" = "$target" ]; } \
      || { [ -n "$terminal" ] && [ "$terminal" = "$target" ]; } \
      || continue
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
  local raw=$1 resolved=$2 state=$3 meta
  meta=$(fm_backend_meta_for_selector "$raw" "$state" 2>/dev/null || true)
  [ -n "$meta" ] && { fm_backend_of_meta "$meta"; return 0; }
  if [ -n "$resolved" ]; then
    meta=$(fm_backend_meta_for_window "$resolved" "$state" 2>/dev/null || true)
    [ -n "$meta" ] && { fm_backend_of_meta "$meta"; return 0; }
  fi
  printf 'herdr'
}

fm_backend_expected_label_of_selector() {  # <raw-target> <state-dir>
  local raw=$1 state=$2 id
  id=$(fm_backend_task_id_for_selector "$raw" "$state" 2>/dev/null || true)
  [ -n "$id" ] && printf 'fm-%s' "$id"
  return 0
}

fm_backend_source() {  # <name>
  local name=$1
  fm_backend_validate "$name" || return 1
  case "$name" in
    herdr)
      if [ -z "${_FM_BACKEND_HERDR_SOURCED:-}" ]; then
        [ -r "$FM_BACKEND_LIB_DIR/backends/herdr.sh" ] || {
          echo "error: Herdr backend adapter is unavailable" >&2
          return 1
        }
        # shellcheck source=/dev/null
        . "$FM_BACKEND_LIB_DIR/backends/herdr.sh" || return 1
        _FM_BACKEND_HERDR_SOURCED=1
      fi
      ;;
    orca)
      if [ -z "${_FM_BACKEND_ORCA_SOURCED:-}" ]; then
        [ -r "$FM_BACKEND_LIB_DIR/backends/orca.sh" ] || {
          echo "error: Orca backend adapter is unavailable" >&2
          return 1
        }
        # shellcheck source=/dev/null
        . "$FM_BACKEND_LIB_DIR/backends/orca.sh" || return 1
        _FM_BACKEND_ORCA_SOURCED=1
      fi
      ;;
  esac
}

# Resolve explicit endpoint strings, metadata-routed task selectors, and
# Herdr's bare live-label lookup.
fm_backend_resolve_selector() {  # <raw-target> <state-dir>
  local raw=$1 state=$2 meta target
  case "$raw" in
    *:*)
      printf '%s' "$raw"
      return 0
      ;;
  esac
  meta=$(fm_backend_meta_for_selector "$raw" "$state" 2>/dev/null || true)
  if [ -n "$meta" ]; then
    target=$(fm_backend_target_of_meta "$meta")
    [ -n "$target" ] || { echo "error: no backend target recorded in $meta" >&2; return 1; }
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
    [ -n "$target" ] || { echo "error: no backend target recorded in $meta" >&2; return 1; }
    printf '%s' "$target"
    return 0
  fi
  fm_backend_source herdr || return 1
  fm_backend_herdr_resolve_bare_selector "$raw"
}

fm_backend_capture() {  # <backend> <target> <lines> [expected-label]
  local backend=$1
  shift
  fm_backend_source "$backend" || return 1
  case "$backend" in
    herdr) fm_backend_herdr_capture "$@" ;;
    orca) fm_backend_orca_capture "$@" ;;
  esac
}

fm_backend_send_key() {  # <backend> <target> <key> [expected-label]
  local backend=$1
  shift
  fm_backend_source "$backend" || return 1
  case "$backend" in
    herdr) fm_backend_herdr_send_key "$@" ;;
    orca) fm_backend_orca_send_key "$@" ;;
  esac
}

fm_backend_send_text_submit() {  # <backend> <target> <text> <retries> <enter-sleep> <settle> [expected-label]
  local backend=$1
  shift
  fm_backend_source "$backend" || return 1
  case "$backend" in
    herdr) fm_backend_herdr_send_text_submit "$@" ;;
    orca) fm_backend_orca_send_text_submit "$@" ;;
  esac
}

fm_backend_kill() {  # <backend> <target>
  local backend=$1
  shift
  [ -n "${1:-}" ] || { echo "error: refusing empty backend kill target" >&2; return 1; }
  fm_backend_source "$backend" || return 1
  case "$backend" in
    herdr) fm_backend_herdr_kill "$@" ;;
    orca) fm_backend_orca_kill "$@" ;;
  esac
}

fm_backend_remove_worktree() {  # <backend> <worktree-id>
  local backend=$1
  shift
  fm_backend_source "$backend" || return 1
  case "$backend" in
    orca) fm_backend_orca_remove_worktree "$@" ;;
    *) echo "error: backend '$backend' does not own task worktrees" >&2; return 1 ;;
  esac
}

fm_backend_worktree_path() {  # <backend> <worktree-id>
  local backend=$1
  shift
  fm_backend_source "$backend" || return 1
  case "$backend" in
    orca) fm_backend_orca_worktree_path "$@" ;;
    *) echo "error: backend '$backend' does not own task worktrees" >&2; return 1 ;;
  esac
}

fm_backend_busy_state() {  # <backend> <target>
  local backend=$1
  shift
  fm_backend_source "$backend" || { printf 'unknown'; return 0; }
  case "$backend" in
    herdr) fm_backend_herdr_busy_state "$@" ;;
    *) printf 'unknown' ;;
  esac
}

fm_backend_composer_state() {  # <backend> <target>
  local backend=$1
  shift
  fm_backend_source "$backend" || { printf 'unknown'; return 0; }
  case "$backend" in
    herdr) fm_backend_herdr_composer_state "$@" ;;
    orca) fm_backend_orca_composer_state "$@" ;;
  esac
}

fm_backend_target_exists() {  # <backend> <target> [expected-label]
  local backend=$1 target=$2 session pane
  case "$backend" in
    herdr)
      fm_backend_source herdr || return 1
      session=${target%%:*}
      pane=${target#*:}
      [ -n "$session" ] && [ -n "$pane" ] && [ "$pane" != "$target" ] || return 1
      fm_backend_herdr_cli "$session" pane get "$pane" >/dev/null 2>&1
      ;;
    orca)
      fm_backend_source orca || return 1
      fm_backend_orca_capture "$target" 1 >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

# Recovery-grade state values are alive, dead, missing, ambiguous, unreadable,
# and unverified. Only dead and missing authorize recovery.
fm_backend_agent_state() {  # <backend> <target>
  local backend=$1 target=$2
  fm_backend_source "$backend" || { printf 'unverified'; return 0; }
  case "$backend" in
    herdr) fm_backend_herdr_agent_state "$target" ;;
    *) printf 'unverified' ;;
  esac
}

fm_backend_agent_alive() {  # <backend> <target>
  case "$(fm_backend_agent_state "$1" "$2")" in
    alive) printf 'alive' ;;
    dead|missing) printf 'dead' ;;
    *) printf 'unknown' ;;
  esac
}

fm_backend_has_push() {  # <backend>
  [ "$1" = herdr ]
}

fm_backend_events_capable() {  # <backend> <session>
  local backend=$1
  shift
  fm_backend_has_push "$backend" || return 1
  fm_backend_source "$backend" || return 1
  fm_backend_herdr_events_capable "$@"
}

fm_backend_wait_transition() {  # <backend> <session> <timeout-secs> <state-dir> <pane-window...>
  local backend=$1
  shift
  fm_backend_has_push "$backend" || return 2
  fm_backend_source "$backend" || return 2
  fm_backend_herdr_wait_transition "$@"
}

fm_backend_commit_transition() {  # <backend> <state-dir> <session> <record>
  local backend=$1
  shift
  fm_backend_has_push "$backend" || return 1
  fm_backend_source "$backend" || return 1
  fm_backend_herdr_commit_transition "$@"
}

fm_backend_clear_transition() {  # <backend> <state-dir> <window>
  local backend=$1
  shift
  fm_backend_has_push "$backend" || return 0
  fm_backend_source "$backend" || return 1
  fm_backend_herdr_clear_transition "$@"
}
