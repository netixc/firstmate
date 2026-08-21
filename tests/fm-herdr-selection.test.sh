#!/usr/bin/env bash
# Herdr-only selection and retired metadata behavior through public helpers.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-herdr-selection)

runtime_check() { # <config-dir> [env assignments through caller]
  FM_CONFIG_OVERRIDE=$1 FM_ROOT_OVERRIDE=$ROOT bash -c \
    '. "$FM_ROOT_OVERRIDE/bin/fm-herdr.sh"; fm_herdr_require_runtime'
}

test_default_and_explicit_herdr() {
  local config=$TMP_ROOT/default-config
  mkdir -p "$config"
  (unset FM_BACKEND TMUX TMUX_PANE; runtime_check "$config") \
    || fail "absent runtime configuration must resolve directly to Herdr"
  printf 'herdr\n' > "$config/backend"
  (unset FM_BACKEND TMUX TMUX_PANE; runtime_check "$config") \
    || fail "legacy explicit config/backend=herdr should remain harmless"
  (unset TMUX TMUX_PANE; FM_BACKEND=herdr runtime_check "$config") \
    || fail "legacy explicit FM_BACKEND=herdr should remain harmless"
  pass "runtime selection: absent or explicit Herdr uses the sole path"
}

test_retired_and_unknown_selection_refused() {
  local config=$TMP_ROOT/refused-config out
  mkdir -p "$config"
  printf 'tmux\n' > "$config/backend"
  out=$(unset FM_BACKEND TMUX TMUX_PANE; runtime_check "$config" 2>&1) \
    && fail "config/backend=tmux must be refused"
  assert_contains "$out" "tmux session support is retired" "tmux config refusal should be actionable"
  rm -f "$config/backend"
  out=$(unset TMUX TMUX_PANE; FM_BACKEND=tmux runtime_check "$config" 2>&1) \
    && fail "FM_BACKEND=tmux must be refused"
  assert_contains "$out" "FM_BACKEND cannot select tmux" "tmux env refusal should name its source"
  out=$(unset FM_BACKEND TMUX_PANE; TMUX=fake runtime_check "$config" 2>&1) \
    && fail "a tmux execution environment must not be reinterpreted as Herdr"
  assert_contains "$out" "leave the tmux environment" "tmux nesting refusal should be actionable"
  printf 'future-provider\n' > "$config/backend"
  out=$(unset FM_BACKEND TMUX TMUX_PANE; runtime_check "$config" 2>&1) \
    && fail "unknown runtime configuration must be refused"
  assert_contains "$out" "Herdr is the only supported" "unknown selection should name the sole path"
  printf 'herdr\ntmux\n' > "$config/backend"
  out=$(unset FM_BACKEND TMUX TMUX_PANE; runtime_check "$config" 2>&1) \
    && fail "multiple runtime selections must be refused"
  assert_contains "$out" "multiple session selections" "multiline config refusal should name the ambiguity"
  assert_contains "$out" "tmux is retired" "multiline config refusal should not hide retired tmux evidence"
  pass "runtime selection: tmux and unknown choices stop without fallback"
}

test_metadata_classification_and_identity() {
  local state=$TMP_ROOT/state meta out before
  mkdir -p "$state"
  meta=$state/legacy.meta
  fm_write_meta "$meta" "window=firstmate:fm-legacy" "worktree=/tmp/legacy"
  before=$(shasum -a 256 "$meta" | awk '{print $1}')
  # shellcheck source=/dev/null
  . "$ROOT/bin/fm-herdr.sh"
  [ "$(fm_herdr_meta_kind "$meta")" = retired-tmux ] \
    || fail "fieldless metadata must classify as retired tmux evidence"
  out=$(fm_herdr_require_meta "$meta" legacy 2>&1) \
    && fail "fieldless metadata must not authorize Herdr control"
  assert_contains "$out" "preserving its records for manual reconciliation" \
    "legacy refusal should state the preservation requirement"
  [ "$(shasum -a 256 "$meta" | awk '{print $1}')" = "$before" ] \
    || fail "legacy refusal must not rewrite metadata"

  fm_write_meta "$state/current.meta" \
    "backend=herdr" "window=lab:w1:p1" "endpoint_task_id=current" \
    "herdr_session=lab" "herdr_workspace_id=w1" "herdr_tab_id=t1" \
    "herdr_pane_id=w1:p1" "worktree=/tmp/current" "project=/tmp/project"
  fm_herdr_validate_task_endpoint "$state/current.meta" current \
    || fail "exact current Herdr metadata should validate"
  [ "$FM_HERDR_VALIDATED_TARGET" = lab:w1:p1 ] \
    || fail "validation must preserve exact endpoint identity"
  pass "metadata: current Herdr validates; legacy evidence is preserved"
}

test_remote_route_identity() {
  local state=$TMP_ROOT/remote-route-state meta
  mkdir -p "$state"
  meta=$state/ios.meta
  fm_write_meta "$meta" \
    "backend=herdr" "window=remote:ios" "endpoint_task_id=ios" \
    "worktree=/remote/home" "project=/remote/root" "home=/remote/home" \
    "remote_host=remote-mac" "remote_root=/remote/root" \
    "remote_herdr_session=fm-remote" "remote_target=fm-remote:w1:p1"
  # shellcheck source=/dev/null
  . "$ROOT/bin/fm-herdr.sh"
  fm_herdr_validate_remote_route "$meta" ios \
    || fail "complete remote Herdr route metadata should validate"
  [ "$FM_HERDR_VALIDATED_REMOTE_HOST" = remote-mac ] \
    && [ "$FM_HERDR_VALIDATED_REMOTE_TARGET" = fm-remote:w1:p1 ] \
    || fail "remote route validation changed exact host or endpoint identity"
  sed '/^backend=/d' "$meta" > "$meta.next" && mv "$meta.next" "$meta"
  fm_herdr_validate_remote_route "$meta" ios \
    || fail "the previous explicit remote Herdr record shape should remain compatible"
  sed '/^remote_target=/d' "$meta" > "$meta.next" && mv "$meta.next" "$meta"
  fm_herdr_validate_remote_route "$meta" ios >/dev/null 2>&1 \
    && fail "providerless metadata without an exact remote Herdr endpoint must remain retired evidence"
  pass "metadata: exact historical and current remote Herdr routes validate"
}

test_selector_refuses_foreign_identity() {
  local state=$TMP_ROOT/selector-state meta out
  mkdir -p "$state"
  meta=$state/current.meta
  fm_write_meta "$meta" \
    "backend=herdr" "window=lab:w1:p1" "endpoint_task_id=other" \
    "herdr_session=lab" "herdr_workspace_id=w1" "herdr_tab_id=t1" \
    "herdr_pane_id=w1:p1" "worktree=/tmp/current" "project=/tmp/project"
  # shellcheck source=/dev/null
  . "$ROOT/bin/fm-herdr.sh"
  out=$(fm_herdr_resolve_selector current "$state" 2>&1) \
    && fail "selector resolution must reject metadata bound to another task"
  assert_contains "$out" "belongs to task other, not current" \
    "selector refusal should preserve the filename-to-task binding"
  pass "selector resolution: foreign endpoint identity fails closed"
}

test_retired_cli_selection_refused() {
  local home=$TMP_ROOT/home out
  mkdir -p "$home/state" "$home/data" "$home/config"
  out=$(FM_HOME="$home" FM_SPAWN_NO_GUARD=1 \
    "$ROOT/bin/fm-spawn.sh" x "$ROOT" --scout --backend tmux 2>&1) \
    && fail "--backend tmux must be refused"
  assert_contains "$out" "--backend tmux is unsupported" \
    "retired command-line selection should be explicit"
  [ ! -e "$home/state/x.meta" ] || fail "retired selection must not publish metadata"
  pass "spawn: retired --backend tmux stops before mutation"
}

test_public_control_paths_refuse_tmux_environment() {
  local home=$TMP_ROOT/public-controls path out
  mkdir -p "$home/state" "$home/data" "$home/config"
  for path in fm-peek.sh fm-send.sh fm-control.sh fm-teardown.sh; do
    out=$(TMUX=fake FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
      "$ROOT/bin/$path" task-a interrupt 2>&1) \
      && fail "$path accepted a tmux execution environment"
    assert_contains "$out" "leave the tmux environment" \
      "$path did not reject the retired environment before control"
  done
  [ -z "$(find "$home/state" -mindepth 1 -print -quit)" ] \
    || fail "retired environment refusal mutated task state"
  pass "public Herdr control paths reject tmux execution environments"
}

test_direct_herdr_entrypoints_refuse_tmux_environment() {
  local home=$TMP_ROOT/direct-controls spec path out
  local -a command
  mkdir -p "$home/state" "$home/data" "$home/config"
  for spec in \
    'fm-afk-launch.sh reconcile' \
    'fm-herdr-session-cleanup.sh' \
    'fm-remote-secondmate-control.sh state task-a' \
    'fm-crew-state.sh task-a' \
    'fm-fleet-snapshot.sh --json' \
    'fm-stow-cascade.sh' \
    'fm-watch.sh'; do
    read -r -a command <<< "$spec"
    path=${command[0]}
    out=$(TMUX=fake FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
      "$ROOT/bin/$path" "${command[@]:1}" 2>&1) \
      && fail "$path accepted a tmux execution environment"
    assert_contains "$out" "leave the tmux environment" \
      "$path did not reject the retired environment before Herdr access"
  done
  [ ! -e "$home/state/.afk-launch.lock" ] \
    || fail "retired environment acquired the away launcher lock"
  [ ! -e "$home/state/.watch.lock" ] \
    || fail "retired environment acquired the watcher lock"
  pass "direct Herdr entrypoints reject tmux before reads or mutations"
}

test_default_and_explicit_herdr
test_retired_and_unknown_selection_refused
test_metadata_classification_and_identity
test_remote_route_identity
test_selector_refuses_foreign_identity
test_retired_cli_selection_refused
test_public_control_paths_refuse_tmux_environment
test_direct_herdr_entrypoints_refuse_tmux_environment

echo "All Herdr selection tests passed."
