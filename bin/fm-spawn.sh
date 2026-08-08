#!/usr/bin/env bash
# Spawn Pi workers in isolated Treehouse worktrees or persistent Firstmate homes.
# Usage: fm-spawn.sh <task-id> <project-dir> --mode <no-mistakes|direct-PR|local-only> --yolo <on|off> [--model <name>] [--effort <level>]
#        fm-spawn.sh <task-id> <project-dir> --scout [--model <name>] [--effort <level>]
#        fm-spawn.sh <task-id> [<firstmate-home>] [--model <name>] [--effort <level>] --secondmate
#
# Pi is Firstmate's sole worker runtime.
# --model and --effort select Pi's model and --thinking values.
# Ship spawns require an explicit delivery mode and yolo posture.
# Scouts and secondmates refuse delivery-mode flags.
# Herdr is the sole task workspace layer and Treehouse supplies isolated task worktrees.
# A spawn refuses a task path that is not an isolated worktree distinct from the project checkout.
# Each task records fixed harness=pi metadata plus complete Herdr endpoint identity.
# Secondmate profile resolution is owned by fm-harness.sh and is repeated on recovery.
# config/crew-dispatch.json requires the selected Pi --model so dispatch consultation is explicit.
# Batch dispatch accepts id=repo pairs and applies shared model, effort, and delivery flags.
# The named Herdr presentation and endpoint-safety contract remains in the implementation below.
# --traceparent is accepted only for a secondmate route that supplies a validated carrier.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  # The whole leading comment block, ending at the first line that is not a
  # comment. Derived rather than a fixed line range, which silently truncated
  # this help mid-sentence every time the header above grew.
  sed -n '2,${/^#/!q;p;}' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"

resolve_directory_input() {
  local name=$1 path=$2 resolved
  case "$path" in
    /*) printf '%s\n' "$path"; return 0 ;;
  esac
  resolved=$(CDPATH='' cd -- "$path" 2>/dev/null && pwd -P) || {
    echo "error: $name directory cannot be resolved: $path" >&2
    return 1
  }
  printf '%s\n' "$resolved"
}

FM_HOME=$(resolve_directory_input FM_HOME "$FM_HOME") || exit 1
if [ -n "${FM_STATE_OVERRIDE:-}" ]; then
  FM_STATE_OVERRIDE=$(resolve_directory_input FM_STATE_OVERRIDE "$FM_STATE_OVERRIDE") || exit 1
fi
if [ -n "${FM_DATA_OVERRIDE:-}" ]; then
  FM_DATA_OVERRIDE=$(resolve_directory_input FM_DATA_OVERRIDE "$FM_DATA_OVERRIDE") || exit 1
fi
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
PROJECTS="${FM_PROJECTS_OVERRIDE:-$FM_HOME/projects}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
SUB_HOME_MARKER=".fm-secondmate-home"
# shellcheck source=bin/fm-ff-lib.sh
. "$SCRIPT_DIR/fm-ff-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-secondmate-nudge-lib.sh
. "$SCRIPT_DIR/fm-secondmate-nudge-lib.sh"
# shellcheck source=bin/fm-config-inherit-lib.sh
. "$SCRIPT_DIR/fm-config-inherit-lib.sh"
# shellcheck source=bin/fm-backend.sh
. "$SCRIPT_DIR/fm-backend.sh"
# shellcheck source=bin/fm-gate-refuse-lib.sh
. "$SCRIPT_DIR/fm-gate-refuse-lib.sh"
# shellcheck source=bin/fm-busy-lib.sh
. "$SCRIPT_DIR/fm-busy-lib.sh"
# shellcheck source=bin/fm-pr-lib.sh
. "$SCRIPT_DIR/fm-pr-lib.sh"
# shellcheck source=bin/fm-trace-context-lib.sh
. "$SCRIPT_DIR/fm-trace-context-lib.sh"
# shellcheck source=bin/fm-remote-readiness-lib.sh
. "$SCRIPT_DIR/fm-remote-readiness-lib.sh"
# Fail closed before any fleet mutation: a no-mistakes gate agent must never spawn
# a direct report (see bin/fm-gate-refuse-lib.sh).
fm_refuse_if_gate_agent
# Skip the watcher guard when re-exec'd for one pair of a batch (FM_SPAWN_NO_GUARD is
# set by the batch loop below), so the guard runs once for the batch, not once per pair.
[ -n "${FM_SPAWN_NO_GUARD:-}" ] || "$FM_ROOT/bin/fm-guard.sh" || true
KIND=ship
MODEL=
EFFORT=
MODE=
YOLO=
TRACEPARENT_ARG=
MODEL_SET=0
EFFORT_SET=0
MODE_SET=0
YOLO_SET=0
TRACEPARENT_SET=0
POS=()
want_value=
for a in "$@"; do
  if [ -n "$want_value" ]; then
    case "$a" in
      --*) echo "error: --$want_value requires a value" >&2; exit 1 ;;
    esac
    case "$want_value" in
      model) MODEL=$a; MODEL_SET=1 ;;
      effort) EFFORT=$a; EFFORT_SET=1 ;;
      mode) MODE=$a; MODE_SET=1 ;;
      yolo) YOLO=$a; YOLO_SET=1 ;;
      traceparent) TRACEPARENT_ARG=$a; TRACEPARENT_SET=1 ;;
      *) echo "error: internal parser state for --$want_value" >&2; exit 1 ;;
    esac
    want_value=
    continue
  fi
  case "$a" in
    --scout) KIND=scout ;;
    --secondmate) KIND=secondmate ;;
    --model) want_value=model ;;
    --model=*) MODEL=${a#--model=}; MODEL_SET=1 ;;
    --effort) want_value=effort ;;
    --effort=*) EFFORT=${a#--effort=}; EFFORT_SET=1 ;;
    --mode) want_value=mode ;;
    --mode=*) MODE=${a#--mode=}; MODE_SET=1 ;;
    --yolo) want_value=yolo ;;
    --yolo=*) YOLO=${a#--yolo=}; YOLO_SET=1 ;;
    --traceparent) want_value=traceparent ;;
    --traceparent=*) TRACEPARENT_ARG=${a#--traceparent=}; TRACEPARENT_SET=1 ;;
    --*) echo "error: unknown option: $a" >&2; exit 1 ;;
    *) POS+=("$a") ;;
  esac
done
[ -z "$want_value" ] || { echo "error: --$want_value requires a value" >&2; exit 1; }
[ "$MODEL_SET" -eq 0 ] || [ -n "$MODEL" ] || { echo "error: --model requires a non-empty value" >&2; exit 1; }
[ "$EFFORT_SET" -eq 0 ] || [ -n "$EFFORT" ] || { echo "error: --effort requires a non-empty value" >&2; exit 1; }
[ "$MODE_SET" -eq 0 ] || [ -n "$MODE" ] || { echo "error: --mode requires a non-empty value" >&2; exit 1; }
[ "$YOLO_SET" -eq 0 ] || [ -n "$YOLO" ] || { echo "error: --yolo requires a non-empty value" >&2; exit 1; }
[ "$TRACEPARENT_SET" -eq 0 ] || [ -n "$TRACEPARENT_ARG" ] || { echo "error: --traceparent requires a non-empty value" >&2; exit 1; }
# A parent-delivered carrier replaces this home's own resolution, so it is
# refused unless it is a secondmate spawn carrying a strictly valid W3C value.
# Nothing else may reach the pane's TRACEPARENT export.
if [ "$TRACEPARENT_SET" -eq 1 ]; then
  [ "$KIND" = secondmate ] || {
    echo "error: --traceparent applies only to --secondmate spawns; every other spawn resolves its own carrier from this home's frozen trace-context decision" >&2
    exit 1
  }
  fm_trace_context_valid "$TRACEPARENT_ARG" || {
    echo "error: --traceparent is not a valid W3C traceparent" >&2
    exit 1
  }
fi
case "$EFFORT" in
  ''|low|medium|high|xhigh|max) ;;
  *) echo "error: --effort must be one of low, medium, high, xhigh, max" >&2; exit 1 ;;
esac

# Delivery contract (AGENTS.md section 7). A ship task's mode and yolo are
# firstmate's per-task decision, so they are required and closed-set validated
# here rather than resolved from the project registry. Scouts deliver a report
# and record no delivery posture; secondmate spawns hardcode theirs.
if [ "$KIND" = ship ]; then
  [ "$MODE_SET" -eq 1 ] || {
    echo "error: ship spawns require --mode <no-mistakes|direct-PR|local-only>; resolve it at intake from the captain's instruction and the project's registered posture in data/projects.md" >&2
    exit 1
  }
  [ "$YOLO_SET" -eq 1 ] || {
    echo "error: ship spawns require --yolo <on|off>; it is this task's routine approval authority, not a project lookup" >&2
    exit 1
  }
  case "$MODE" in
    no-mistakes|direct-PR|local-only) ;;
    no-mistakes-prod-only)
      echo "error: no-mistakes-prod-only is a registry policy, not a task mode; classify this task's surface and resolve it to no-mistakes or direct-PR at intake" >&2
      exit 1 ;;
    *) echo "error: --mode must be one of no-mistakes, direct-PR, local-only (got '$MODE')" >&2; exit 1 ;;
  esac
  case "$YOLO" in
    on|off) ;;
    *) echo "error: --yolo must be on or off (got '$YOLO')" >&2; exit 1 ;;
  esac
else
  [ "$MODE_SET" -eq 0 ] || {
    echo "error: --mode applies only to ship spawns; a scout delivers a report and a secondmate records its own fixed posture" >&2
    exit 1
  }
  [ "$YOLO_SET" -eq 0 ] || {
    echo "error: --yolo applies only to ship spawns; a scout delivers a report and a secondmate records its own fixed posture" >&2
    exit 1
  }
fi

# Parse the tab-separated Pi profile line emitted by fm-harness.sh without
# read's whitespace-field collapsing behavior, which would lose intentionally
# empty built-in model or thinking fields.
spawn_profile_output_parse() {
  local record=$1 remainder
  SPAWN_PROFILE_MODEL=
  SPAWN_PROFILE_EFFORT=
  SPAWN_PROFILE_SOURCE=
  case "$record" in
    *$'\t'*$'\t'*) ;;
    *) echo "error: Pi profile resolver returned malformed data" >&2; return 1 ;;
  esac
  SPAWN_PROFILE_MODEL=${record%%$'\t'*}
  remainder=${record#*$'\t'}
  SPAWN_PROFILE_EFFORT=${remainder%%$'\t'*}
  SPAWN_PROFILE_SOURCE=${remainder#*$'\t'}
  if [ -z "$SPAWN_PROFILE_SOURCE" ] || [[ "$SPAWN_PROFILE_SOURCE" == *$'\t'* ]]; then
    echo "error: Pi profile resolver returned malformed data" >&2
    return 1
  fi
}

remote_secondmate_launch_protocol() {
  local id=$1 out rc schema launch route
  if out=$("$SCRIPT_DIR/fm-on.sh" "$id" fm-remote-secondmate-control.sh capabilities < /dev/null 2>&1); then
    schema=$(printf '%s\n' "$out" | sed -n 's/^schema=//p' | tail -1)
    launch=$(printf '%s\n' "$out" | sed -n 's/^launch=//p' | tail -1)
    route=$(printf '%s\n' "$out" | sed -n 's/^route=//p' | tail -1)
    if [ "$schema" = fm-remote-secondmate-control.v3 ] \
      && [ "$launch" = launch-v2 ] \
      && [ "$route" = runtime ]; then
      printf 'versioned-launch\n'
      return 0
    fi
    if [ "$schema" = fm-remote-secondmate-control.v2 ] \
      && [ "$launch" = pi-model-effort ] \
      && [ "$route" = runtime ]; then
      printf 'compat-marker\n'
      return 0
    fi
    echo "error: remote secondmate controller returned unsupported capabilities" >&2
    return 1
  else
    rc=$?
  fi
  [ "$rc" -ne 255 ] || return 255
  if out=$("$SCRIPT_DIR/fm-on.sh" "$id" fm-remote-secondmate-control.sh help < /dev/null 2>&1); then
    rc=0
  else
    rc=$?
  fi
  [ "$rc" -ne 255 ] || return 255
  case "$out" in
    *'launch <id> <harness> <model|-> <effort|->'*) printf 'legacy-harness\n' ;;
    *'launch <id> <model|-> <effort|->'*) printf 'pi-model-effort\n' ;;
    *)
      echo "error: remote secondmate controller launch protocol is unsupported" >&2
      return 1
      ;;
  esac
}

spawn_remote_secondmate() {
  local id=$1 remote host root home model effort out rc meta tmp remote_launch_protocol remote_launch_command
  local profile_record
  local remote_target remote_runtime remote_harness remote_herdr_session registry_lock remote_lock remote_generation
  local remote_traceparent remote_recorded_traceparent
  local -a launch_args
  id=${POS[0]:-}
  fm_task_id_creation_valid "$id" || { echo "error: invalid task id" >&2; return 2; }
  mkdir -p "$STATE" || { echo "error: could not create parent state directory" >&2; return 1; }
  SPAWN_TASK_LOCK="$STATE/.spawn-$id.lock"
  if ! fm_lock_try_acquire "$SPAWN_TASK_LOCK"; then
    echo "error: another spawn is already creating task $id" >&2
    return 1
  fi
  registry_lock=$(secondmate_registry_lock_path "$STATE")
  if ! fm_lock_acquire_wait "$registry_lock"; then
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    echo "error: secondmate registry could not be locked for remote spawn" >&2
    return 1
  fi
  remote=$(secondmate_registry_field "$DATA/secondmates.md" "$id" remote 2>/dev/null || true)
  if [ "$remote" != 1 ]; then
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    return 3
  fi
  host=$(secondmate_registry_field "$DATA/secondmates.md" "$id" host)
  root=$(secondmate_registry_field "$DATA/secondmates.md" "$id" root)
  home=$(secondmate_registry_field "$DATA/secondmates.md" "$id" home)
  if [ "${#POS[@]}" -gt 1 ]; then
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    echo "error: remote secondmate spawn accepts only its id; Pi runtime selection is fixed" >&2
    return 2
  fi
  if ! profile_record=$("$FM_ROOT/bin/fm-harness.sh" secondmate-profile "$id"); then
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    return 1
  fi
  if ! spawn_profile_output_parse "$profile_record"; then
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    echo "error: Pi secondmate profile resolution failed" >&2
    return 1
  fi
  model=${MODEL:--}
  effort=${EFFORT:--}
  if [ "$MODEL_SET" -eq 0 ]; then
    model=$SPAWN_PROFILE_MODEL
    [ -n "$model" ] || model=-
  fi
  if [ "$EFFORT_SET" -eq 0 ]; then
    effort=$SPAWN_PROFILE_EFFORT
    [ -n "$effort" ] || effort=-
  fi
  # A remote second mate runs in the host's Herdr GUI session, so its endpoint
  # outlives every SSH connection that supervises it.
  # bin/fm-remote-doctor.sh gates that host on the same requirement.
  case "$effort" in
    -|low|medium|high|xhigh|max) ;;
    *)
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
      echo "error: invalid configured remote secondmate effort: $effort" >&2
      return 1
      ;;
  esac
  meta="$STATE/$id.meta"
  if [ -e "$meta" ] || [ -L "$meta" ]; then
    if [ ! -f "$meta" ] || [ -L "$meta" ] \
      || [ "$(fm_meta_get "$meta" kind)" != secondmate ] \
      || [ "$(fm_meta_get "$meta" remote_host)" != "$host" ] \
      || [ "$(fm_meta_get "$meta" remote_root)" != "$root" ] \
      || [ "$(fm_meta_get "$meta" home)" != "$home" ]; then
      fm_lock_release "$registry_lock" || true
      fm_lock_release "$SPAWN_TASK_LOCK" || true
      echo "error: existing metadata for $id does not identify this remote secondmate route" >&2
      return 1
    fi
  fi
  # Gate the host before anything is published or transferred, so a host that
  # cannot hold a durable Herdr endpoint refuses here rather than half-way
  # through a launch. This is also the readiness gate every liveness relaunch
  # passes through, because recovery respawns through this same route.
  rc=0
  fm_remote_readiness_ensure "$SCRIPT_DIR" "$id" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    # Summary first, then the doctor's own text: a caller that reports only the
    # first line, such as the startup liveness sweep, must still say something
    # actionable.
    if [ "$rc" -eq 255 ]; then
      echo "error: remote secondmate $id readiness could not be confirmed; preserved route $host:$home" >&2
    else
      echo "error: remote secondmate $id host $host is not ready for a remote second mate; launch refused" >&2
    fi
    [ -z "$FM_REMOTE_READINESS_OUT" ] || printf '%s\n' "$FM_REMOTE_READINESS_OUT" >&2
    [ "$rc" -ne 255 ] || return 255
    return 1
  fi
  if remote_launch_protocol=$(remote_secondmate_launch_protocol "$id"); then
    :
  else
    rc=$?
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    if [ "$rc" -eq 255 ]; then
      echo "error: remote secondmate $id controller protocol could not be confirmed; preserved route $host:$home" >&2
    else
      echo "error: remote secondmate $id controller protocol is unsupported; launch refused" >&2
    fi
    return "$rc"
  fi
  remote_lock=$(fm_remote_inherit_transaction_lock_path "$STATE" "$id")
  if ! fm_lock_acquire_wait "$remote_lock"; then
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    echo "error: remote secondmate $id inheritance transaction could not be locked" >&2
    return 1
  fi
  remote_generation=$(fm_remote_inherit_generation_next "$STATE" "$id" 2>/dev/null || true)
  if [ -z "$remote_generation" ]; then
    fm_lock_release "$remote_lock" || true
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    echo "error: remote secondmate $id inheritance generation could not be published" >&2
    return 1
  fi
  if "$SCRIPT_DIR/fm-remote-inherit-push.sh" "$id" "$remote_generation" >/dev/null; then
    :
  else
    rc=$?
    fm_lock_release "$remote_lock" || true
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    if [ "$rc" -eq 255 ]; then
      echo "error: remote secondmate $id inheritance completion is unknown; launch refused and route preserved for reconciliation" >&2
    else
      echo "error: remote secondmate $id inheritance failed; launch refused" >&2
    fi
    return "$rc"
  fi
  # This parent home owns the remote secondmate's task identity because it holds
  # the task metadata an observer reads, exactly as for a local spawn: the
  # carrier is resolved against THIS task's own meta (reused verbatim on
  # relaunch, freshly rooted otherwise, never adopting this process's ambient
  # TRACEPARENT) under this home's frozen decision, then handed to the remote
  # host to export into the agent's pane. Disabled resolves to empty and the
  # remote launch call stays byte-identical to the untraced one.
  remote_traceparent=
  if [ "$(fm_trace_context_session_effective "$STATE/.trace-context-effective")" = on ]; then
    remote_traceparent=$(FM_TRACE_CONTEXT=on fm_trace_context_resolve "$CONFIG" "$meta" || true)
  fi
  remote_launch_command=launch
  case "$remote_launch_protocol" in
    legacy-harness) launch_args=("$id" pi "$model" "$effort") ;;
    compat-marker) launch_args=("$id" pi "$model" "$effort") ;;
    pi-model-effort) launch_args=("$id" "$model" "$effort") ;;
    versioned-launch) remote_launch_command=launch-v2; launch_args=("$id" "$model" "$effort") ;;
  esac
  [ -z "$remote_traceparent" ] || launch_args+=("$remote_traceparent")
  if out=$("$SCRIPT_DIR/fm-on.sh" "$id" fm-remote-secondmate-control.sh "$remote_launch_command" \
    "${launch_args[@]}" < /dev/null 2>&1); then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    fm_lock_release "$remote_lock" || true
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    [ -z "$out" ] || printf '%s\n' "$out" >&2
    if [ "$rc" -eq 255 ]; then
      echo "error: remote secondmate $id is unavailable or launch completion is unknown; preserved route $host:$home" >&2
    fi
    return "$rc"
  fi
  remote_target=$(printf '%s\n' "$out" | sed -n 's/^target=//p' | tail -1)
  remote_runtime=$(printf '%s\n' "$out" | sed -n 's/^runtime=//p' | tail -1)
  remote_harness=$(printf '%s\n' "$out" | sed -n 's/^harness=//p' | tail -1)
  remote_herdr_session=$(printf '%s\n' "$out" | sed -n 's/^herdr_session=//p' | tail -1)
  if [ "$remote_runtime" = pi ]; then
    :
  elif [ -z "$remote_runtime" ] \
    && [ "$remote_launch_protocol" = legacy-harness ] \
    && [ "$remote_harness" = pi ]; then
    :
  else
    fm_lock_release "$remote_lock" || true
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    echo "error: remote launch returned malformed route metadata; preserving the remote route for reconciliation" >&2
    return 1
  fi
  [ -n "$remote_target" ] || {
    fm_lock_release "$remote_lock" || true
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    echo "error: remote launch returned malformed route metadata; preserving the remote route for reconciliation" >&2
    return 1
  }
  if [ "$remote_herdr_session" != fm-remote ] || [ "${remote_target%%:*}" != "$remote_herdr_session" ]; then
    fm_lock_release "$remote_lock" || true
    fm_lock_release "$registry_lock" || true
    fm_lock_release "$SPAWN_TASK_LOCK" || true
    echo "error: remote launch returned Herdr session '${remote_herdr_session:-missing}', expected 'fm-remote'; preserving the remote route for reconciliation" >&2
    return 1
  fi
  # Record what the remote endpoint ACTUALLY carries, read back from its own
  # launch, rather than what this side hoped to deliver. That keeps the #995
  # guarantee that the recorded carrier is the identity the child received even
  # when the remote host already had a live agent and reused its endpoint. An
  # off decision delivers no carrier, but an endpoint already holding one still
  # reports it here so the parent does not deny the agent's actual identity.
  remote_recorded_traceparent=$(printf '%s\n' "$out" | sed -n 's/^traceparent=//p' | tail -1)
  fm_trace_context_valid "$remote_recorded_traceparent" || remote_recorded_traceparent=
  tmp="$meta.tmp.$$"
  {
    echo "window=remote:$id"
    echo "endpoint_task_id=$id"
    echo "worktree=$home"
    echo "project=$root"
    echo "harness=pi"
    echo "kind=secondmate"
    echo "mode=secondmate"
    echo "yolo=off"
    echo "tasktmp="
    echo "model=${model#-}"
    echo "effort=${effort#-}"
    echo "home=$home"
    echo "projects=$(secondmate_registry_field "$DATA/secondmates.md" "$id" projects)"
    echo "remote_host=$host"
    echo "remote_root=$root"
    echo "remote_herdr_session=$remote_herdr_session"
    echo "remote_target=$remote_target"
    [ -z "$remote_recorded_traceparent" ] || echo "traceparent=$remote_recorded_traceparent"
  } > "$tmp"
  mv -f -- "$tmp" "$meta"
  fm_lock_release "$remote_lock" || true
  fm_lock_release "$registry_lock" || true
  fm_lock_release "$SPAWN_TASK_LOCK" || true
  if ! "$SCRIPT_DIR/fm-procevent-remote-reply.sh" arm "$id" >/dev/null; then
    echo "error: remote secondmate $id launched, but its reply source could not be armed; endpoint metadata is preserved" >&2
    return 1
  fi
  echo "spawned $id runtime=pi kind=secondmate mode=secondmate yolo=off window=remote:$id worktree=$home remote=$host"
  return 0
}

if [ "$KIND" = secondmate ]; then
  if spawn_remote_secondmate "${POS[0]:-}"; then
    exit 0
  else
    remote_spawn_rc=$?
  fi
  [ "$remote_spawn_rc" -eq 3 ] || exit "$remote_spawn_rc"
fi

fm_backend_source herdr || exit 1
HERDR_PROJECTION_ABORT_CLEANUP=0
HERDR_PROJECTION_ABORT_SESSION=
HERDR_PROJECTION_ABORT_TASK_PANE=
HERDR_PROJECTION_ABORT_SEEDED_PANE=
HERDR_PRESENTATION_ORDER_LOCK=
HERDR_PRESENTATION_ORDER_LOCK_HELD=0
SPAWN_TASK_LOCK=
SPAWN_TASK_LOCK_HELD=0
CONFIG_INHERIT_LOCK=
CONFIG_INHERIT_LOCK_HELD=0

spawn_abort_cleanup() {
  local status=$?
  if [ "$HERDR_PROJECTION_ABORT_CLEANUP" = 1 ] \
     && [ "$HERDR_PRESENTATION_ORDER_LOCK_HELD" != 1 ]; then
    if ! spawn_herdr_presentation_order_lock_acquire "${HERDR_PROJECTION_ABORT_SESSION:-}"; then
      echo "warning: herdr presentation focus lock unavailable; retaining the projection journal and refusing concurrent abort cleanup" >&2
      HERDR_PROJECTION_ABORT_CLEANUP=0
    fi
  fi
  if [ "$HERDR_PROJECTION_ABORT_CLEANUP" = 1 ]; then
    HERDR_PROJECTION_ABORT_CLEANUP=0
    fm_backend_herdr_projection_cleanup_exact \
      "$HERDR_PROJECTION_ABORT_SESSION" \
      "$HERDR_PROJECTION_ABORT_TASK_PANE" \
      "$HERDR_PROJECTION_ABORT_SEEDED_PANE" || true
  fi
  if [ "$HERDR_PRESENTATION_ORDER_LOCK_HELD" = 1 ]; then
    HERDR_PRESENTATION_ORDER_LOCK_HELD=0
    fm_lock_release "$HERDR_PRESENTATION_ORDER_LOCK" || true
  fi
  if [ "$SPAWN_TASK_LOCK_HELD" = 1 ]; then
    SPAWN_TASK_LOCK_HELD=0
    fm_lock_release "$SPAWN_TASK_LOCK" || true
  fi
  if [ "$CONFIG_INHERIT_LOCK_HELD" = 1 ]; then
    CONFIG_INHERIT_LOCK_HELD=0
    fm_lock_release "$CONFIG_INHERIT_LOCK" || true
  fi
  return "$status"
}
trap spawn_abort_cleanup EXIT

# One bounded lock per live Herdr session/socket, shared across all homes.
# <session> is required so secondmate and primary spawns serialize against the
# same session without writing any other home's state directory.
spawn_herdr_presentation_order_lock_acquire() {
  local session=${1:-} attempt lock_path
  [ -n "$session" ] || session=$(fm_backend_herdr_session)
  lock_path=$(fm_backend_herdr_presentation_session_lock_path "$session") || return 1
  HERDR_PRESENTATION_ORDER_LOCK="$lock_path"
  attempt=0
  while [ "$attempt" -lt 50 ]; do
    if fm_lock_try_acquire "$HERDR_PRESENTATION_ORDER_LOCK"; then
      HERDR_PRESENTATION_ORDER_LOCK_HELD=1
      return 0
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done
  return 1
}

spawn_herdr_presentation_order_lock_release() {
  [ "$HERDR_PRESENTATION_ORDER_LOCK_HELD" = 1 ] || return 0
  HERDR_PRESENTATION_ORDER_LOCK_HELD=0
  fm_lock_release "$HERDR_PRESENTATION_ORDER_LOCK" || true
}

# Batch dispatch (see header): when the first positional is an `id=repo` pair, treat every
# positional as one and spawn each by re-execing this script in single-task mode. We use
# the FM_ROOT path (not $0) so it works whatever cwd or relative path invoked us, and reuse
# the single path verbatim. A failed pair is reported and skipped; the rest still launch;
# exit is non-zero if any pair failed. Single-task invocations never carry an '=' in arg
# one (task ids are bare slugs), so they fall straight through to the logic below.
idpart=${POS[0]:-}
idpart=${idpart%%=*}
if [ "${#POS[@]}" -gt 0 ] && [ "${POS[0]}" != "$idpart" ] && case "$idpart" in */*) false ;; *) true ;; esac; then
  if [ "$KIND" != secondmate ] && [ "$MODEL_SET" -eq 0 ] && [ -f "$CONFIG/crew-dispatch.json" ]; then
    echo "error: config/crew-dispatch.json is active - pass the selected Pi --model so dispatch selection cannot be skipped." >&2
    exit 1
  fi
  rc=0
  shared_args=()
  [ -z "$MODEL" ] || shared_args+=(--model "$MODEL")
  [ -z "$EFFORT" ] || shared_args+=(--effort "$EFFORT")
  # One delivery contract applies to every pair in a batch, exactly like the shared
  # harness. Each pair still re-validates it against its own brief, so a batch
  # spanning several modes is two invocations rather than a silent mixed dispatch.
  [ "$MODE_SET" -eq 0 ] || shared_args+=(--mode "$MODE")
  [ "$YOLO_SET" -eq 0 ] || shared_args+=(--yolo "$YOLO")
  for pair in "${POS[@]}"; do
    case "$pair" in
      *=*) : ;;
      *) echo "error: batch dispatch expects every argument as id=repo; got '$pair'" >&2; rc=2; continue ;;
    esac
    if [ "$KIND" = secondmate ]; then
      echo "error: batch dispatch does not support --secondmate; spawn each secondmate explicitly" >&2
      rc=2
      continue
    elif [ "$KIND" = scout ]; then
      if FM_SPAWN_NO_GUARD=1 "$FM_ROOT/bin/fm-spawn.sh" "${pair%%=*}" "${pair#*=}" "${shared_args[@]+"${shared_args[@]}"}" --scout; then :; else echo "batch: FAILED to spawn ${pair%%=*} (${pair#*=})" >&2; rc=1; fi
    else
      if FM_SPAWN_NO_GUARD=1 "$FM_ROOT/bin/fm-spawn.sh" "${pair%%=*}" "${pair#*=}" "${shared_args[@]+"${shared_args[@]}"}"; then :; else echo "batch: FAILED to spawn ${pair%%=*} (${pair#*=})" >&2; rc=1; fi
    fi
  done
  exit "$rc"
fi
ID=${POS[0]}
fm_task_id_creation_valid "$ID" || { echo "error: invalid task id" >&2; exit 2; }
SPAWN_TASK_LOCK="$STATE/.spawn-$ID.lock"
if ! fm_lock_try_acquire "$SPAWN_TASK_LOCK"; then
  echo "error: another spawn is already creating task $ID" >&2
  exit 1
fi
SPAWN_TASK_LOCK_HELD=1
PROJ=
FIRSTMATE_HOME=
if [ "$KIND" = secondmate ]; then
  [ "${#POS[@]}" -le 2 ] || {
    echo "error: secondmate spawn accepts <id> [<firstmate-home>] and always uses Pi" >&2
    exit 2
  }
  FIRSTMATE_HOME=${POS[1]:-}
else
  [ "${#POS[@]}" -le 2 ] || {
    echo "error: ship and scout spawns accept only <id> <project-dir>" >&2
    exit 2
  }
  PROJ=${POS[1]:-}
fi

# Pi is Firstmate's sole worker runtime.
# shellcheck disable=SC2016 # The command substitution expands in the worker pane.
launch_template() {
  local kind=${1:-ship}
  if [ "$kind" = secondmate ]; then
    printf '%s' 'pi __MODELFLAG____EFFORTFLAG__-e __PITURNEND__ -e __PIWATCH__ "$(__OPINPUT__ encode launch-brief < __BRIEF__)"'
  else
    printf '%s' 'pi __MODELFLAG____EFFORTFLAG__-e __PIEXT__ "$(__OPINPUT__ encode launch-brief < __BRIEF__)"'
  fi
}

HARNESS=pi
if [ "$KIND" != secondmate ]; then
  "$FM_ROOT/bin/fm-harness.sh" validate-config || exit 1
  "$FM_ROOT/bin/fm-harness.sh" validate-dispatch || exit 1
  if [ -f "$CONFIG/crew-dispatch.json" ] && [ "$MODEL_SET" -eq 0 ]; then
    echo "error: config/crew-dispatch.json is active - pass the selected Pi --model so dispatch selection cannot be skipped." >&2
    exit 1
  fi
  if [ ! -f "$CONFIG/crew-dispatch.json" ]; then
    CREW_PROFILE=$("$FM_ROOT/bin/fm-harness.sh" crew-profile) || exit 1
    spawn_profile_output_parse "$CREW_PROFILE" || exit 1
    if [ "$MODEL_SET" -eq 0 ]; then MODEL=$SPAWN_PROFILE_MODEL; fi
    if [ "$EFFORT_SET" -eq 0 ]; then EFFORT=$SPAWN_PROFILE_EFFORT; fi
  fi
fi
LAUNCH=$(launch_template "$KIND") || exit 1

secondmate_registry_value() {
  secondmate_registry_field "$DATA/secondmates.md" "$1" "$2"
}

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

model_flag_for_harness() {
  local _runtime=$1 model=$2
  [ -n "$model" ] && [ "$model" != default ] || return 0
  printf -- '--model %s ' "$(shell_quote "$model")"
}

effort_flag_for_harness() {
  local _runtime=$1 effort=$2
  [ -n "$effort" ] && [ "$effort" != default ] || return 0
  case "$effort" in
    low|medium|high|xhigh|max) printf -- '--thinking %s ' "$(shell_quote "$effort")" ;;
  esac
}

resolved_existing_dir() {
  local path=$1
  [ -d "$path" ] || { echo "error: firstmate home does not exist or is not a directory: $path" >&2; return 1; }
  cd "$path" && pwd -P
}

resolve_project_dir_arg() {
  local path=$1
  case "$path" in
    projects/*) printf '%s/%s\n' "$PROJECTS" "${path#projects/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

path_is_ancestor_of() {
  local ancestor=$1 path=$2
  [ -n "$ancestor" ] || return 1
  [ -n "$path" ] || return 1
  [ "$ancestor" != "$path" ] || return 1
  case "$path" in
    "$ancestor"/*) return 0 ;;
  esac
  return 1
}

validate_firstmate_home_for_spawn() {
  local id=$1 home=$2 abs_home abs_active_home abs_root marker_id
  abs_home=$(resolved_existing_dir "$home") || return 1
  abs_active_home=$(resolved_existing_dir "$FM_HOME")
  abs_root=$(resolved_existing_dir "$FM_ROOT")
  if [ "$abs_home" = "/" ]; then
    echo "error: secondmate home cannot be the filesystem root: $home" >&2
    return 1
  fi
  if [ "$abs_home" = "$abs_active_home" ]; then
    echo "error: secondmate home cannot be the active firstmate home: $home" >&2
    return 1
  fi
  if [ "$abs_home" = "$abs_root" ]; then
    echo "error: secondmate home cannot be the firstmate repo: $home" >&2
    return 1
  fi
  if path_is_ancestor_of "$abs_active_home" "$abs_home"; then
    echo "error: secondmate home cannot be inside the active firstmate home: $home" >&2
    return 1
  fi
  if path_is_ancestor_of "$abs_root" "$abs_home"; then
    echo "error: secondmate home cannot be inside the firstmate repo: $home" >&2
    return 1
  fi
  if path_is_ancestor_of "$abs_home" "$abs_active_home"; then
    echo "error: secondmate home cannot be an ancestor of the active firstmate home: $home" >&2
    return 1
  fi
  if path_is_ancestor_of "$abs_home" "$abs_root"; then
    echo "error: secondmate home cannot be an ancestor of the firstmate repo: $home" >&2
    return 1
  fi
  validate_firstmate_operational_dirs "$abs_home" "$abs_active_home" "$abs_root" || return 1
  if [ ! -f "$abs_home/$SUB_HOME_MARKER" ]; then
    echo "error: firstmate home $home is not a seeded secondmate home" >&2
    return 1
  fi
  marker_id=$(cat "$abs_home/$SUB_HOME_MARKER" 2>/dev/null || true)
  if [ "$marker_id" != "$id" ]; then
    echo "error: firstmate home $home is marked for secondmate ${marker_id:-unknown}, expected $id" >&2
    return 1
  fi
  if [ ! -f "$abs_home/AGENTS.md" ]; then
    echo "error: $home is not a firstmate home (missing AGENTS.md)" >&2
    return 1
  fi
  if [ ! -d "$abs_home/bin" ]; then
    echo "error: $home is not a firstmate home (missing bin/)" >&2
    return 1
  fi
  printf '%s\n' "$abs_home"
}

validate_firstmate_operational_dirs() {
  local abs_home=$1 abs_active_home=$2 abs_root=$3 name dir abs_dir
  for name in data state config projects; do
    dir="$abs_home/$name"
    if [ -L "$dir" ] && [ ! -e "$dir" ]; then
      echo "error: secondmate $name directory must resolve inside the secondmate home: $dir" >&2
      return 1
    fi
    if [ -d "$dir" ]; then
      abs_dir=$(cd "$dir" && pwd -P)
    elif [ -e "$dir" ]; then
      echo "error: secondmate $name path is not a directory: $dir" >&2
      return 1
    else
      abs_dir="$abs_home/$name"
    fi
    if ! path_is_ancestor_of "$abs_home" "$abs_dir"; then
      echo "error: secondmate $name directory must resolve inside the secondmate home: $dir" >&2
      return 1
    fi
    if [ "$abs_dir" = "$abs_active_home" ] || path_is_ancestor_of "$abs_active_home" "$abs_dir"; then
      echo "error: secondmate $name directory cannot be inside the active firstmate home: $dir" >&2
      return 1
    fi
    if [ "$abs_dir" = "$abs_root" ] || path_is_ancestor_of "$abs_root" "$abs_dir"; then
      echo "error: secondmate $name directory cannot be inside the firstmate repo: $dir" >&2
      return 1
    fi
  done
}

if [ "$KIND" = secondmate ]; then
  if [ -z "$FIRSTMATE_HOME" ] && [ -f "$STATE/$ID.meta" ]; then
    FIRSTMATE_HOME=$(grep '^home=' "$STATE/$ID.meta" | cut -d= -f2- || true)
  fi
  if [ -z "$FIRSTMATE_HOME" ]; then
    FIRSTMATE_HOME=$(secondmate_registry_value "$ID" home || true)
  fi
fi

if [ "$KIND" = secondmate ]; then
  [ -n "$FIRSTMATE_HOME" ] || { echo "error: no firstmate home supplied or registered for $ID" >&2; exit 1; }
  PROJ_ABS=$(validate_firstmate_home_for_spawn "$ID" "$FIRSTMATE_HOME")
  if [ -e "$DATA/secondmates.md" ] || [ -L "$DATA/secondmates.md" ]; then
    if ! secondmate_registry_validate_bindings "$DATA/secondmates.md" resolve_path "$ID" "$FIRSTMATE_HOME"; then
      echo "error: $SECONDMATE_REGISTRY_ERROR" >&2
      exit 1
    fi
    SECONDMATE_PROJECTS=$SECONDMATE_REGISTRY_MATCH_PROJECTS
  fi
  WT="$PROJ_ABS"
  # Local-HEAD sync: before launch, fast-forward this secondmate's worktree to the
  # PRIMARY checkout's current default-branch commit, so a freshly spawned or
  # recovery-respawned secondmate always runs the primary's version (AGENTS.md
  # spawn section). Purely local - no fetch: the home is a worktree of this same
  # repo and already holds the commit. ff-only and guarded; a dirty, diverged, or
  # wrong-branch home is left untouched and launches as-is. The agent re-reads
  # AGENTS.md fresh on launch, so no nudge is needed here.
  if sm_primary_head=$(primary_head_commit "$FM_ROOT"); then
    sm_ff_out=$(ff_target "$PROJ_ABS" "secondmate $ID" "$sm_primary_head" yes yes 2>&1 || true)
    case "$sm_ff_out" in
      *': skipped:'*)
        sm_ff_line=$(first_line "$sm_ff_out")
        sm_ff_prefix="secondmate $ID: skipped: "
        sm_ff_reason=${sm_ff_line#"$sm_ff_prefix"}
        echo "warning: secondmate $ID sync skipped before launch: $sm_ff_reason" >&2
        ;;
    esac
  else
    echo "warning: secondmate $ID sync skipped before launch: primary default-branch commit cannot be resolved" >&2
  fi
  # The guarded local fast-forward is deliberately before profile lookup.
  # That preserves the launch safety ordering even when a later Pi profile or
  # workspace prerequisite refuses the launch.
  SECONDMATE_PROFILE=$("$FM_ROOT/bin/fm-harness.sh" secondmate-profile "$ID") || exit 1
  spawn_profile_output_parse "$SECONDMATE_PROFILE" || exit 1
  if [ "$MODEL_SET" -eq 0 ]; then
    MODEL=$SPAWN_PROFILE_MODEL
  fi
  if [ "$EFFORT_SET" -eq 0 ]; then
    EFFORT=$SPAWN_PROFILE_EFFORT
  fi
  mkdir -p "$PROJ_ABS/state" || {
    echo "error: could not create secondmate state directory for $PROJ_ABS" >&2
    exit 1
  }
  if [ "${FM_SKIP_SECONDMATE_INHERIT:-0}" != 1 ]; then
    CONFIG_INHERIT_LOCK=$(fm_config_inherit_lock_path "$PROJ_ABS") || {
      echo "error: could not resolve secondmate inheritance lock for $PROJ_ABS" >&2
      exit 1
    }
    if ! fm_lock_acquire_wait "$CONFIG_INHERIT_LOCK"; then
      echo "error: could not acquire secondmate inheritance lock for $PROJ_ABS" >&2
      exit 1
    fi
    CONFIG_INHERIT_LOCK_HELD=1
    # Inheritance propagation: push the primary-authoritative live-safe local inheritance
    # surface into this secondmate home (fm-config-inherit-lib.sh).
    FM_CONFIG_INHERIT_LIVE=1 \
      propagate_secondmate_inheritance "$FM_HOME" "$PROJ_ABS" "$CONFIG" "$DATA" \
      || echo "warning: secondmate $ID inheritance failed for $PROJ_ABS" >&2
  fi
  if [ -f "$PROJ_ABS/data/charter.md" ]; then
    BRIEF="$PROJ_ABS/data/charter.md"
  else
    BRIEF="$DATA/$ID/brief.md"
  fi
else
  PROJ_ABS="$(cd "$(resolve_project_dir_arg "$PROJ")" && pwd)"
  WT=""
  BRIEF="$DATA/$ID/brief.md"
fi
[ -f "$BRIEF" ] || { echo "error: no brief at $BRIEF" >&2; exit 1; }

delivery_rigor_rank() {  # <mode> -> 3 (most rigor) .. 1 (least); 0 = not a task mode
  case "$1" in
    no-mistakes) echo 3 ;;
    direct-PR) echo 2 ;;
    local-only) echo 1 ;;
    *) echo 0 ;;
  esac
}

# Brief/spawn delivery agreement, checked before any endpoint exists.
# fm-brief.sh records a ship brief's mode as a fixed "Delivery contract: mode=<mode>"
# line. A spawn that disagrees would launch a worker whose instructions and whose
# recorded task delivery differ, which is the exact drift this contract prevents.
if [ "$KIND" = ship ]; then
  PROJ_NAME=$(basename "$PROJ_ABS")
  BRIEF_MODE=$(sed -n 's/^Delivery contract: mode=\([^ ]*\).*$/\1/p' "$BRIEF" | head -n 1)
  if [ -z "$BRIEF_MODE" ]; then
    echo "warning: $BRIEF records no delivery contract line (scaffolded before ship briefs recorded one); launching on the explicit --mode $MODE - confirm its definition of done matches" >&2
  elif [ "$BRIEF_MODE" != "$MODE" ]; then
    echo "error: delivery mismatch for $ID: the brief says mode=$BRIEF_MODE but this spawn passed --mode $MODE; correct the flag or re-scaffold the brief so the worker's instructions and the task record agree" >&2
    exit 1
  fi
  # The registry holds the captain's standing posture, so dropping below it is
  # allowed (a current explicit captain instruction wins) but never silent. An
  # unregistered project resolves to the same no-mistakes standing default, which
  # is why the notice names the standing posture rather than the registry line. A
  # conditional policy is excluded: both of its legs are legitimate classifications.
  STANDING_MODE=$("$FM_ROOT/bin/fm-project-mode.sh" --raw "$PROJ_NAME" 2>/dev/null | cut -d' ' -f1) || STANDING_MODE=
  if [ -n "$STANDING_MODE" ] && [ "$STANDING_MODE" != no-mistakes-prod-only ] \
     && [ "$(delivery_rigor_rank "$MODE")" -lt "$(delivery_rigor_rank "$STANDING_MODE")" ]; then
    echo "notice: $ID ships mode=$MODE while the standing posture for $PROJ_NAME is $STANDING_MODE - less rigor than the captain's standing posture; proceed only on a current explicit captain instruction or an intake judgment you can state" >&2
  fi
fi

# PROJ_ABS can still carry a symlinked path component (e.g. macOS's /tmp ->
# /private/tmp) when it came from the ship/scout branch's logical `pwd` above.
# A runtime backend's current-path read can report the OS-level,
# physically-resolved cwd, so comparing it against a
# still-symlinked PROJ_ABS can misfire both ways: false-negative (the poll
# below never notices the pane left the project) or false-positive (the
# isolation guard refuses a spawn that never actually tangled). Canonicalize
# once here so every downstream comparison uses the same physical form
# (docs/herdr-backend.md "Known gaps").
PROJ_ABS_REAL=$(cd "$PROJ_ABS" 2>/dev/null && pwd -P) || PROJ_ABS_REAL="$PROJ_ABS"

real_path_or_raw() {  # <path>
  local path=$1 real
  if real=$(cd "$path" 2>/dev/null && pwd -P); then
    printf '%s\n' "$real"
  else
    printf '%s\n' "$path"
  fi
}

# Runtime container creation converges on the opaque $T target consumed by the
# shared send, capture, supervision, and cleanup paths.
validate_spawn_worktree() {  # <source> <inspect-target>
  local source=$1 inspect_target=$2 wt_real proj_real wt_top wt_top_real
  wt_real=
  if ! wt_real=$(cd "$WT" 2>/dev/null && pwd -P); then
    wt_real=
  fi
  proj_real=$PROJ_ABS_REAL
  wt_top=$(git -C "$WT" rev-parse --show-toplevel 2>/dev/null || true)
  wt_top_real=
  if ! wt_top_real=$(cd "$wt_top" 2>/dev/null && pwd -P); then
    wt_top_real=
  fi
  if [ -z "$wt_real" ] || [ -z "$wt_top_real" ] || [ "$wt_real" != "$wt_top_real" ] || [ "$wt_real" = "$proj_real" ]; then
    echo "error: $source did not yield an isolated worktree (resolved '$WT'; worktree root '${wt_top:-none}'; primary '$PROJ_ABS'); refusing to launch to avoid tangling the primary checkout. Inspect target $inspect_target" >&2
    exit 1
  fi
}

herdr_projection_meta_field_exact() {  # <meta> <key>
  local meta=$1 key=$2 count
  [ -f "$meta" ] && [ ! -L "$meta" ] || return 1
  count=$(grep -c "^${key}=" "$meta" 2>/dev/null || true)
  [ "$count" = 1 ] || return 1
  grep "^${key}=" "$meta" 2>/dev/null | cut -d= -f2-
}

# A stale presentation journal never grants launch authority.
# Under the session lock, authoritative metadata must identify one positively
# dead or agent-free endpoint before token inspection may allow flat fallback.
# Exact Herdr fields are retained for the narrower version 2 reclaim path.
herdr_projection_existing_meta_allows_flat() {  # <meta>
  local meta=$1 old_backend old_target old_session old_pane old_state target_session target_pane
  HERDR_RECOVERY_BACKEND=""
  HERDR_RECOVERY_WORKSPACE_ID=""
  HERDR_RECOVERY_TAB_ID=""
  HERDR_RECOVERY_PANE_ID=""
  old_backend=$(fm_backend_of_meta "$meta")
  old_target=$(fm_backend_target_of_meta "$meta")
  [ -n "$old_target" ] || {
    echo "error: existing metadata for $ID has no endpoint; refusing duplicate launch while its herdr presentation journal is quarantined" >&2
    return 1
  }
  HERDR_RECOVERY_BACKEND=$old_backend
  if [ "$old_backend" = herdr ]; then
    fm_backend_herdr_parse_target "$old_target" || {
      echo "error: existing herdr endpoint for $ID is malformed; refusing duplicate launch" >&2
      return 1
    }
    target_session=$FM_BACKEND_HERDR_SESSION
    target_pane=$FM_BACKEND_HERDR_PANE
    old_session=$(herdr_projection_meta_field_exact "$meta" herdr_session) || {
      echo "error: existing herdr metadata for $ID has an ambiguous session; refusing duplicate launch" >&2
      return 1
    }
    HERDR_RECOVERY_WORKSPACE_ID=$(herdr_projection_meta_field_exact "$meta" herdr_workspace_id) || {
      echo "error: existing herdr metadata for $ID has an ambiguous workspace; refusing duplicate launch" >&2
      return 1
    }
    HERDR_RECOVERY_TAB_ID=$(herdr_projection_meta_field_exact "$meta" herdr_tab_id) || {
      echo "error: existing herdr metadata for $ID has an ambiguous tab; refusing duplicate launch" >&2
      return 1
    }
    old_pane=$(herdr_projection_meta_field_exact "$meta" herdr_pane_id) || {
      echo "error: existing herdr metadata for $ID has an ambiguous pane; refusing duplicate launch" >&2
      return 1
    }
    [ "$target_session" = "$old_session" ] && [ "$target_pane" = "$old_pane" ] || {
      echo "error: existing herdr metadata for $ID has inconsistent endpoint identities; refusing duplicate launch" >&2
      return 1
    }
    HERDR_RECOVERY_PANE_ID=$old_pane
    fm_backend_herdr_server_ensure "$old_session" || {
      echo "error: existing herdr endpoint for $ID could not be inspected; refusing duplicate launch" >&2
      return 1
    }
    old_state=$(fm_backend_herdr_pane_agent_state "$old_session" "$old_pane")
    case "$old_state" in
      dead|no-agent) return 0 ;;
      live|unknown)
        echo "error: existing herdr endpoint for $ID is $old_state; refusing duplicate launch" >&2
        return 1
        ;;
    esac
  fi
  old_state=$(fm_backend_agent_alive "$old_backend" "$old_target")
  case "$old_state" in
    dead) return 0 ;;
    alive|unknown)
      echo "error: existing $old_backend endpoint for $ID is $old_state; refusing duplicate launch" >&2
      return 1
      ;;
  esac
}

W="fm-$ID"
    # fm_backend_herdr_workspace_label resolves the target workspace from
    # FM_HOME. For every KIND except secondmate, this process's own FM_HOME is
    # already the right home (the primary spawning its own crewmate/scout, or
    # a secondmate spawning ITS OWN crewmate/scout from its own process's
    # FM_HOME - the latter needs no glue at all). A --secondmate spawn is the
    # one case that does: it is the PRIMARY's own fm-spawn.sh process
    # launching a DIFFERENT home (PROJ_ABS, already validated above as the
    # secondmate's home), so FM_HOME here still names the primary. Shadow it
    # to PROJ_ABS for just these two calls (bash restores it automatically
    # after each prefixed simple-command call) so the secondmate's tab lands
    # in the secondmate's own workspace, not the primary's "firstmate" one.
    #
    # Placement, separately from labeling: a crewmate/scout belongs in the
    # EXACT herdr workspace this launching process is itself running in, which
    # only its own herdr pane identity can name (a same-labeled sibling
    # workspace must never be adopted). A --secondmate launch is the exception -
    # it stands up a DIFFERENT home's own workspace by design - so it asks for
    # the per-home container instead of inheriting this launcher's.
    HERDR_LABEL_HOME=$FM_HOME
    HERDR_LAUNCHER_RELATIONSHIP=launcher-home
    if [ "$KIND" = secondmate ]; then
      HERDR_LABEL_HOME=$PROJ_ABS
      HERDR_LAUNCHER_RELATIONSHIP=other-home
    fi
    HERDR_PRESENTATION_JOURNAL=$(fm_backend_herdr_projection_journal_path "$STATE" "$ID")
    HERDR_PROJECTED=0
    if [ "$KIND" != secondmate ] && fm_backend_herdr_presentation_enabled "$CONFIG" "$STATE"; then
      HERDR_SES=$(fm_backend_herdr_session)
      HERDR_PARENT_LABEL=$(FM_HOME="$HERDR_LABEL_HOME" fm_backend_herdr_workspace_label)
      if [ -e "$HERDR_PRESENTATION_JOURNAL" ] || [ -L "$HERDR_PRESENTATION_JOURNAL" ]; then
        fm_backend_herdr_server_ensure "$HERDR_SES" || {
          echo "error: herdr presentation recovery could not ensure its exact named session" >&2
          exit 1
        }
        spawn_herdr_presentation_order_lock_acquire "$HERDR_SES" || {
          echo "error: herdr presentation recovery could not acquire its session lock; refusing a concurrent resume" >&2
          exit 1
        }
        if [ -e "$STATE/$ID.meta" ] || [ -L "$STATE/$ID.meta" ]; then
          herdr_projection_existing_meta_allows_flat "$STATE/$ID.meta" || exit 1
        fi
        fm_backend_herdr_projection_recovery_allows_flat \
          "$HERDR_SES" "$HERDR_PRESENTATION_JOURNAL" "$ID" || exit 1
        if [ "${HERDR_RECOVERY_BACKEND:-}" = herdr ]; then
          set +e
          FM_HOME="$HERDR_LABEL_HOME" fm_backend_herdr_projection_reclaim_task \
            "$HERDR_SES" "$HERDR_PRESENTATION_JOURNAL" "$ID" "$HERDR_LABEL_HOME" \
            "$HERDR_RECOVERY_WORKSPACE_ID" "$HERDR_RECOVERY_TAB_ID" "$HERDR_RECOVERY_PANE_ID" \
            "$HERDR_PARENT_LABEL" "$W" "$PROJ_ABS"
          HERDR_RECLAIM_STATUS=$?
          set -e
          case "$HERDR_RECLAIM_STATUS" in
            0)
              HERDR_PROJECTED=1
              HERDR_WORKSPACE_ID=$HERDR_RECOVERY_WORKSPACE_ID
              HERDR_SEEDED_DEFAULT_TAB_ID=""
              HERDR_TAB_ID=$FM_BACKEND_HERDR_PROJECTION_TAB_ID
              HERDR_PANE_ID=$FM_BACKEND_HERDR_PROJECTION_PANE_ID
              HERDR_PROJECTION_ABORT_CLEANUP=1
              HERDR_PROJECTION_ABORT_SESSION=$HERDR_SES
              HERDR_PROJECTION_ABORT_TASK_PANE=$HERDR_PANE_ID
              HERDR_PROJECTION_ABORT_SEEDED_PANE=""
              ;;
            2)
              spawn_herdr_presentation_order_lock_release
              ;;
            *) exit 1 ;;
          esac
        else
          spawn_herdr_presentation_order_lock_release
        fi
      elif [ ! -e "$STATE/$ID.meta" ] && [ ! -L "$STATE/$ID.meta" ]; then
        # Session lock path resolution and exact parent binding both need a
        # live named-session socket before journal publication.
        if ! fm_backend_herdr_server_ensure "$HERDR_SES"; then
          echo "warning: herdr presentation could not ensure its session server; using the ordinary flat layout without projection" >&2
        elif [ "${FM_BACKEND_HERDR_PRESENTATION_PREFERENCE:-default}" = default ] \
          && ! fm_backend_herdr_presentation_default_supported "$STATE" "$HERDR_SES"; then
          :
        elif spawn_herdr_presentation_order_lock_acquire "$HERDR_SES"; then
          # The projected child is placed and bound UNDER this launcher's exact
          # parent workspace. Its own herdr pane identity names that workspace
          # directly; the label lookup is only the fallback for a launcher with
          # no herdr ancestry at all. A claimed-but-broken identity refuses here
          # rather than projecting under a guessed parent.
          set +e
          fm_backend_herdr_launcher_identity "$HERDR_SES"
          HERDR_LAUNCHER_STATUS=$?
          set -e
          case "$HERDR_LAUNCHER_STATUS" in
            0) HERDR_PARENT_WORKSPACE_ID=$FM_BACKEND_HERDR_LAUNCHER_WORKSPACE_ID ;;
            2) HERDR_PARENT_WORKSPACE_ID=$(fm_backend_herdr_projection_parent_workspace_exact \
                 "$HERDR_SES" "$HERDR_PARENT_LABEL" 2>/dev/null || true) ;;
            *) spawn_herdr_presentation_order_lock_release; exit 1 ;;
          esac
          if [ -z "$HERDR_PARENT_WORKSPACE_ID" ]; then
            echo "warning: herdr presentation parent is absent or ambiguous; using the ordinary flat layout without projection" >&2
            spawn_herdr_presentation_order_lock_release
          else
            HERDR_PROJECTION_ID=$(fm_backend_herdr_projection_journal_create "$STATE" "$ID") || exit 1
            HERDR_PROJECTION_LABEL=$(fm_backend_herdr_projection_workspace_label "$ID" "$HERDR_PROJECTION_ID")
            if ! FM_HOME="$HERDR_LABEL_HOME" fm_backend_herdr_projection_create_task \
              "$PROJ_ABS" "$HERDR_PROJECTION_LABEL" "$W"; then
              if [ "${FM_BACKEND_HERDR_PROJECTION_CLEANUP_SAFE:-0}" = 1 ]; then
                HERDR_PROJECTION_ABORT_CLEANUP=1
                HERDR_PROJECTION_ABORT_SESSION=$FM_BACKEND_HERDR_PROJECTION_SESSION
                HERDR_PROJECTION_ABORT_TASK_PANE=$FM_BACKEND_HERDR_PROJECTION_PANE_ID
                HERDR_PROJECTION_ABORT_SEEDED_PANE=$FM_BACKEND_HERDR_PROJECTION_SEEDED_PANE_ID
              fi
              exit 1
            fi
            HERDR_PROJECTED=1
            HERDR_SES=$FM_BACKEND_HERDR_PROJECTION_SESSION
            HERDR_WORKSPACE_ID=$FM_BACKEND_HERDR_PROJECTION_WORKSPACE_ID
            HERDR_SEEDED_DEFAULT_TAB_ID=$FM_BACKEND_HERDR_PROJECTION_SEEDED_TAB_ID
            HERDR_TAB_ID=$FM_BACKEND_HERDR_PROJECTION_TAB_ID
            HERDR_PANE_ID=$FM_BACKEND_HERDR_PROJECTION_PANE_ID
            HERDR_PROJECTION_ABORT_CLEANUP=1
            HERDR_PROJECTION_ABORT_SESSION=$HERDR_SES
            HERDR_PROJECTION_ABORT_TASK_PANE=$HERDR_PANE_ID
            HERDR_PROJECTION_ABORT_SEEDED_PANE=$FM_BACKEND_HERDR_PROJECTION_SEEDED_PANE_ID
            fm_backend_herdr_projection_order_best_effort \
              "$HERDR_SES" "$HERDR_WORKSPACE_ID" "$HERDR_PARENT_LABEL" "$HERDR_PARENT_WORKSPACE_ID"
            HERDR_HOME_ID=$(fm_backend_herdr_projection_home_identity "$HERDR_LABEL_HOME" 2>/dev/null || true)
            if [ -n "$HERDR_HOME_ID" ] \
               && fm_backend_herdr_projection_live_binding_matches \
                 "$HERDR_SES" "$HERDR_PROJECTION_ID" "$HERDR_WORKSPACE_ID" \
                 "$HERDR_TAB_ID" "$HERDR_PANE_ID" "$HERDR_PARENT_WORKSPACE_ID" \
                 "$HERDR_PARENT_LABEL" "$HERDR_PROJECTION_LABEL" "$W" \
               && fm_backend_herdr_projection_journal_bind \
                 "$HERDR_PRESENTATION_JOURNAL" "$ID" "$HERDR_HOME_ID" "$HERDR_SES" \
                 "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID" \
                 "$HERDR_PARENT_WORKSPACE_ID" "$HERDR_PARENT_LABEL" "$HERDR_PROJECTION_LABEL" "$W"; then
              :
            else
              echo "warning: herdr presentation could not publish an exact restart binding; this task will use flat fallback after a restart" >&2
            fi
          fi
        else
          echo "warning: herdr presentation focus lock unavailable; using the ordinary flat layout without projection" >&2
        fi
      fi
    fi
    if [ "$HERDR_PROJECTED" -ne 1 ]; then
      HERDR_CONTAINER_RAW=$(FM_HOME="$HERDR_LABEL_HOME" fm_backend_herdr_container_ensure "$PROJ_ABS" "$HERDR_LAUNCHER_RELATIONSHIP") || exit 1
      # fm_backend_herdr_container_ensure echoes "<session>:<workspace_id>\t<seeded_default_tab_id>"
      # (the second field empty when this call ADOPTED a pre-existing workspace
      # rather than creating a fresh one). Split on the guaranteed single tab
      # character; the seeded tab id is threaded through to create_task
      # untouched, which is the only function permitted to prune it (never
      # re-derived from labels - see docs/herdr-backend.md "Default-tab prune").
      CONTAINER=${HERDR_CONTAINER_RAW%%$'\t'*}
      HERDR_SEEDED_DEFAULT_TAB_ID=${HERDR_CONTAINER_RAW#*$'\t'}
      HERDR_SES=${CONTAINER%%:*}
      HERDR_WORKSPACE_ID=${CONTAINER#*:}
      HERDR_TASK_IDS=$(FM_HOME="$HERDR_LABEL_HOME" fm_backend_herdr_create_task "$CONTAINER" "$W" "$PROJ_ABS" "$HERDR_SEEDED_DEFAULT_TAB_ID") || exit 1
      read -r HERDR_TAB_ID HERDR_PANE_ID <<EOF
$HERDR_TASK_IDS
EOF
    fi
    if [ -z "$HERDR_TAB_ID" ] || [ -z "$HERDR_PANE_ID" ]; then
      echo "error: herdr did not return a tab/pane id for $W" >&2
      exit 1
    fi
    T="$HERDR_SES:$HERDR_PANE_ID"
if [ "$KIND" = secondmate ]; then
  FM_INHERITABLE_CONFIG=trace-context \
    propagate_inheritable_config "$CONFIG" "$PROJ_ABS/config" \
    || echo "warning: secondmate $ID trace-context inheritance failed for $PROJ_ABS" >&2
fi
WT_TARGET=$T
spawn_send_text_line() {  # <target> <text>
  fm_backend_herdr_send_text_line "$1" "$2"
}
spawn_current_path() {  # <target>
  fm_backend_herdr_current_path "$1"
}
spawn_send_literal() {  # <target> <text>
  fm_backend_herdr_send_literal "$1" "$2"
}
spawn_send_key() {  # <target> <key>
  fm_backend_herdr_send_key "$1" "$2"
}

if [ "$KIND" != secondmate ]; then
  spawn_send_text_line "$WT_TARGET" 'treehouse get'

  # Wait for the treehouse subshell: the pane's cwd moves from the project to the worktree.
  # Target the stable endpoint identity, never a mutable label, so a label change
  # cannot redirect the path read to Firstmate's own pane and tangle a hook into
  # the primary checkout.
  # Compare against PROJ_ABS_REAL (physical), not PROJ_ABS: a symlinked project
  # prefix would otherwise make the pane's OS-level cwd read differ from
  # PROJ_ABS on the very first poll, before the pane has actually moved.
  #
  # A single read that already differs from PROJ_ABS_REAL is not proof the pane
  # settled there: a brand-new endpoint's current path can lag briefly
  # transiently reports an unrelated stale path (seen live as another real git
  # checkout entirely) before the shell catches up with treehouse get's cd. That
  # stale path still passes the PROJ_ABS_REAL comparison and validate_spawn_worktree
  # below (it resolves to a real, distinct worktree top-level too), so accepting it
  # on one read alone silently records the wrong worktree= in state/<id>.meta. Require
  # two consecutive reads to agree on the same non-project path before accepting it;
  # a mismatch just becomes the new candidate rather than resetting the wait, so a
  # pane that is already settled by the first real read only costs the one existing
  # inter-poll sleep as confirmation, not a whole extra cycle on top.
  candidate=""
  for _ in $(seq 1 60); do
    p=$(spawn_current_path "$WT_TARGET" || true)
    if [ -n "$p" ]; then
      p_real=$(real_path_or_raw "$p")
      if [ "$p_real" != "$PROJ_ABS_REAL" ]; then
        if [ -n "$candidate" ] && [ "$p_real" = "$candidate" ]; then
          WT="$p"
          break
        fi
        candidate="$p_real"
      else
        candidate=""
      fi
    else
      candidate=""
    fi
    sleep 1
  done
  if [ -z "$WT" ]; then
    echo "error: treehouse get did not enter a worktree within 60s; inspect window $T" >&2
    exit 1
  fi

  validate_spawn_worktree "treehouse get" "$T"
fi

# Per-task temp root: /tmp/fm-<id>/ with Go's build temp nested at gotmp/. Go won't
# create GOTMPDIR, so mkdir before it is used; fm-teardown removes the whole root.
# Nested (not a bare /tmp/fm-<id>/gotmp) so other per-task temp can live alongside
# later, and teardown cleans one deterministic path. GOTMPDIR (not TMPDIR) is the
# targeted knob: TMPDIR is too broad (affects every program's temp, not just Go's).
TASK_TMP="/tmp/fm-$ID"
mkdir -p "$TASK_TMP/gotmp"

# The task-local Pi extension touches state/<id>.turn-ended after each settled turn.
mkdir -p "$STATE"
STATE_REAL=$(cd "$STATE" && pwd -P)
TURNEND="$STATE_REAL/$ID.turn-ended"
if [ "$KIND" != secondmate ]; then
  # The launch brief begins a Pi turn, so seed its generation-bound busy state.
  BUSY_GEN=$("$FM_ROOT/bin/fm-busy-event.sh" arm "$STATE_REAL" "$ID") || {
    echo "error: failed to arm the Pi busy-state contract for $ID" >&2
    exit 1
  }
  # Kept outside the worktree so Pi's task launch does not need project trust.
  cat > "$STATE/$ID.pi-ext.ts" <<EOF
import { execFile } from "node:child_process";
const busyEvent = (state: string, event: string) =>
  new Promise<void>((resolve) => {
    execFile("$FM_ROOT/bin/fm-busy-event.sh", [
      "apply", "$STATE_REAL", "$ID", state,
      "--gen", "$BUSY_GEN", "--source", "pi-ext", "--event", event,
    ], () => resolve());
  });
export default function (pi: any) {
  pi.on("agent_start", () => busyEvent("busy", "agent-start"));
  pi.on("agent_settled", (_event: any, ctx: any) => {
    if (ctx && typeof ctx.isIdle === "function" && !ctx.isIdle()) return;
    return busyEvent("idle", "agent-settled");
  });
  pi.on("turn_end", () => execFile("touch", ["$TURNEND"]));
}
EOF
fi

# Delivery posture recorded in meta so fm-teardown's safety check and the
# validate/merge stages can branch on it. A ship task carries the explicit
# per-task decision validated above; a secondmate's posture is fixed; a scout
# records none at all, because its deliverable is a report rather than a merge
# (fm-teardown.sh defaults an absent mode to no-mistakes, and fm-promote.sh
# requires an explicit mode when a scout is promoted to a ship task).
if [ "$KIND" = secondmate ]; then
  MODE=secondmate
  YOLO=off
  : "${SECONDMATE_PROJECTS:=}"
elif [ "$KIND" = scout ]; then
  MODE=
  YOLO=
fi

# Resolve the optional default-off W3C trace context (bin/fm-trace-context-lib.sh,
# docs/configuration.md): the one carrier both recorded in meta and injected into
# the pane, so an observer reads exactly what the child receives. Empty only when
# disabled or on entropy/validation failure. Reuses this task's already-recorded
# value on relaunch; any other spawn roots a fresh trace, never adopting this
# process's own ambient TRACEPARENT, so each routed task is its own trace
# boundary even under a persistent supervisor. Never aborts the spawn and adds
# only the cost of reading a few bytes of entropy.
#
# The session-start path owns input resolution. Spawn consumes only the frozen
# home-session state and reuses it for the carrier and Secondmate launch prefix.
#
# A remote secondmate launch is the one case where this process is not the home
# that owns the task's identity: the parent home resolved and will record the
# carrier, and this host only delivers it. The validated --traceparent value
# then IS the decision, so the enablement snapshot handed to the new Secondmate
# agrees with the carrier it receives exactly as on the local path.
if [ "$TRACEPARENT_SET" -eq 1 ]; then
  SPAWN_TRACE_EFFECTIVE=on
  SPAWN_TRACEPARENT=$TRACEPARENT_ARG
else
  SPAWN_TRACE_EFFECTIVE=$(fm_trace_context_session_effective "$STATE/.trace-context-effective")
  if [ "$SPAWN_TRACE_EFFECTIVE" = on ]; then
    SPAWN_TRACEPARENT=$(FM_TRACE_CONTEXT=on fm_trace_context_resolve "$CONFIG" "$STATE/$ID.meta" || true)
  else
    SPAWN_TRACEPARENT=
  fi
fi

META_WINDOW=$T
META_PATH="$STATE/$ID.meta"
if { [ -e "$META_PATH" ] || [ -L "$META_PATH" ]; } \
  && { [ ! -f "$META_PATH" ] || [ -L "$META_PATH" ]; }; then
  echo "error: refusing to publish task metadata over a non-regular path: $META_PATH" >&2
  exit 1
fi
META_TMP=$(umask 077; mktemp "$STATE/.${ID}.meta.XXXXXX") || {
  echo "error: could not create a private task metadata file in $STATE" >&2
  exit 1
}
if ! {
  echo "window=$META_WINDOW"
  echo "endpoint_task_id=$ID"
  echo "worktree=$WT"
  echo "project=$PROJ_ABS"
  echo "harness=$HARNESS"
  echo "kind=$KIND"
  [ -z "$MODE" ] || echo "mode=$MODE"
  [ -z "$YOLO" ] || echo "yolo=$YOLO"
  echo "tasktmp=$TASK_TMP"
  echo "model=${MODEL:-default}"
  echo "effort=${EFFORT:-default}"
  [ -z "${BUSY_GEN:-}" ] || echo "busy_gen=$BUSY_GEN"
  # Default-off writes no traceparent= line.
  echo "backend=herdr"
  echo "herdr_session=$HERDR_SES"
  echo "herdr_workspace_id=$HERDR_WORKSPACE_ID"
  echo "herdr_tab_id=$HERDR_TAB_ID"
  echo "herdr_pane_id=$HERDR_PANE_ID"
  if [ "$KIND" = secondmate ]; then
    echo "home=$PROJ_ABS"
    echo "projects=$SECONDMATE_PROJECTS"
  fi
} > "$META_TMP"; then
  rm -f -- "$META_TMP"
  echo "error: could not write task metadata for $ID" >&2
  exit 1
fi
if ! mv -f -- "$META_TMP" "$META_PATH"; then
  rm -f -- "$META_TMP"
  echo "error: could not publish task metadata for $ID" >&2
  exit 1
fi

sq_brief=$(shell_quote "$BRIEF")
sq_piext=$(shell_quote "$STATE/$ID.pi-ext.ts")
sq_piturnend=$(shell_quote "$PROJ_ABS/.pi/extensions/fm-primary-turnend-guard.ts")
sq_piwatch=$(shell_quote "$PROJ_ABS/.pi/extensions/fm-primary-pi-watch.ts")
sq_opinput=$(shell_quote "$FM_ROOT/bin/fm-operational-input.sh")
MODELFLAG=$(model_flag_for_harness "$HARNESS" "$MODEL")
EFFORTFLAG=$(effort_flag_for_harness "$HARNESS" "$EFFORT")
LAUNCH=${LAUNCH//__MODELFLAG__/$MODELFLAG}
LAUNCH=${LAUNCH//__EFFORTFLAG__/$EFFORTFLAG}
LAUNCH=${LAUNCH//__BRIEF__/$sq_brief}
LAUNCH=${LAUNCH//__PIEXT__/$sq_piext}
LAUNCH=${LAUNCH//__PITURNEND__/$sq_piturnend}
LAUNCH=${LAUNCH//__PIWATCH__/$sq_piwatch}
LAUNCH=${LAUNCH//__OPINPUT__/$sq_opinput}
if [ "$KIND" = secondmate ]; then
  sq_home=$(shell_quote "$PROJ_ABS")
  sq_primary_home=$(shell_quote "$FM_HOME")
  # Deliver the primary's EFFECTIVE trace-context decision as a normalized on/off
  # literal (never the raw FM_TRACE_CONTEXT string) so a FM_TRACE_CONTEXT override
  # on the primary reaches the secondmate's OWN workers, not just the copied
  # config/trace-context file: otherwise off would not disable them and on would
  # not enable them across the launch boundary (bin/fm-trace-context-lib.sh header).
  # Reuse the single frozen decision from the carrier resolution above so the
  # injected carrier and this on/off snapshot are guaranteed to agree.
  LAUNCH="FM_ROOT_OVERRIDE= FM_STATE_OVERRIDE= FM_DATA_OVERRIDE= FM_PROJECTS_OVERRIDE= FM_CONFIG_OVERRIDE= FM_PUBLIC_FOLLOWUP_PRIMARY_HOME=$sq_primary_home FM_HOME=$sq_home FM_TRACE_CONTEXT=$SPAWN_TRACE_EFFECTIVE $LAUNCH"
fi
# Export GOTMPDIR into the crewmate's pane shell so the agent and every child
# process (go build, go test, ...) inherit it. Sent before the launch command so
# the env is set when the agent starts; the brief sleep lets the export land.
spawn_send_text_line "$T" "export GOTMPDIR=$TASK_TMP/gotmp"
# Send through the same channel that ships GOTMPDIR for ship, scout, and secondmate launches.
# Skip it entirely when trace context is off.
if [ -n "$SPAWN_TRACEPARENT" ]; then
  if spawn_send_text_line "$T" "export TRACEPARENT=$SPAWN_TRACEPARENT"; then
    if ! echo "traceparent=$SPAWN_TRACEPARENT" >> "$STATE/$ID.meta"; then
      LAUNCH="unset TRACEPARENT; $LAUNCH"
    fi
  else
    TRACE_SEND_STATUS=$?
    if [ "$TRACE_SEND_STATUS" -eq 2 ]; then
      echo "error: trace-context input could not be cleared for $W; refusing to append the launch command" >&2
      exit 1
    fi
  fi
fi
sleep 0.3
spawn_send_literal "$T" "$LAUNCH"
sleep 0.3
if [ "${HERDR_PROJECTED:-0}" -eq 1 ]; then
  HERDR_PROJECTION_ABORT_CLEANUP=0
  spawn_herdr_presentation_order_lock_release
fi
spawn_send_key "$T" Enter
if [ "$KIND" = secondmate ] && [ "${FM_SKIP_SECONDMATE_INHERIT:-0}" != 1 ]; then
  if ! fm_config_reread_discard_pending "$PROJ_ABS" "$ID" "$FM_HOME"; then
    if fm_config_reread_quarantine_pending "$PROJ_ABS" "$ID" "$FM_HOME"; then
      echo "CONFIG_REREAD: secondmate $ID: quarantined pre-relaunch generations after cleanup failure (destination=$PROJ_ABS/state/.fm-inherited-config-reread-quarantine source=$FM_HOME/state/.fm-inherited-config-reread-quarantine)" >&2
    else
      echo "CONFIG_REREAD: secondmate $ID: cleanup failed; pre-relaunch generations were force-cleared where possible (destination=$PROJ_ABS source=$FM_HOME)" >&2
    fi
  fi
fi

SPAWN_DELIVERY=
[ -z "$MODE" ] || SPAWN_DELIVERY=" mode=$MODE yolo=$YOLO"
echo "spawned $ID runtime=pi kind=$KIND$SPAWN_DELIVERY window=$META_WINDOW worktree=$WT"
