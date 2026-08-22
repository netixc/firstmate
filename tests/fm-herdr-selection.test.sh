#!/usr/bin/env bash
# Herdr-only selection and retired metadata behavior through public executables.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-herdr-selection)

runtime_check() { # <config-dir> [env assignments through caller]
  local config=$1 home=$1.home
  mkdir -p "$home/state" "$home/data" "$config"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  FM_HOME=$home FM_CONFIG_OVERRIDE=$config FM_ROOT_OVERRIDE=$ROOT \
    "$ROOT/bin/fm-fleet-snapshot.sh" --json >/dev/null
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
  printf 'h e r d r\n' > "$config/backend"
  out=$(unset FM_BACKEND TMUX TMUX_PANE; runtime_check "$config" 2>&1) \
    && fail "internally spaced runtime configuration must be refused"
  assert_contains "$out" "unsupported session selection 'h e r d r'" \
    "internal whitespace must not be silently reinterpreted"
  printf '  herdr  \n' > "$config/backend"
  (unset FM_BACKEND TMUX TMUX_PANE; runtime_check "$config") \
    || fail "leading and trailing configuration whitespace should be harmless"
  pass "runtime selection: tmux and unknown choices stop without fallback"
}

test_afk_start_refuses_tmux_before_mutation() {
  local home=$TMP_ROOT/afk-start out
  mkdir -p "$home/state" "$home/config"
  printf 'buffered escalation\n' > "$home/state/.subsuper-escalations"
  out=$(TMUX=fake FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    "$ROOT/bin/fm-afk-start.sh" 2>&1) \
    && fail "fm-afk-start accepted a tmux execution environment"
  assert_contains "$out" "leave the tmux environment" \
    "fm-afk-start did not reject tmux before away-mode mutation"
  [ ! -e "$home/state/.afk" ] || fail "retired environment created the away-mode flag"
  [ "$(cat "$home/state/.subsuper-escalations")" = 'buffered escalation' ] \
    || fail "retired environment deleted prior escalation state"
  pass "away-mode start rejects tmux before state mutation"
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
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/account"
  for spec in \
    'fm-afk-launch.sh reconcile' \
    'fm-herdr-session-cleanup.sh' \
    'fm-remote-secondmate-control.sh state task-a' \
    'fm-crew-state.sh task-a' \
    'fm-fleet-snapshot.sh --json' \
    'fm-config-push.sh' \
    'fm-remote-doctor.sh --fix' \
    'fm-stow-cascade.sh' \
    'fm-watch.sh'; do
    read -r -a command <<< "$spec"
    path=${command[0]}
    out=$(TMUX=fake HOME="$home/account" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
      "$ROOT/bin/$path" "${command[@]:1}" 2>&1) \
      && fail "$path accepted a tmux execution environment"
    assert_contains "$out" "leave the tmux environment" \
      "$path did not reject the retired environment before Herdr access"
  done
  [ ! -e "$home/state/.afk-launch.lock" ] \
    || fail "retired environment acquired the away launcher lock"
  [ ! -e "$home/state/.watch.lock" ] \
    || fail "retired environment acquired the watcher lock"
  [ -z "$(find "$home/account" -mindepth 1 -print -quit)" ] \
    || fail "retired environment let remote doctor mutate its account"
  pass "direct Herdr entrypoints reject tmux before reads or mutations"
}

test_default_and_explicit_herdr
test_retired_and_unknown_selection_refused
test_afk_start_refuses_tmux_before_mutation
test_retired_cli_selection_refused
test_public_control_paths_refuse_tmux_environment
test_direct_herdr_entrypoints_refuse_tmux_environment

echo "All Herdr selection tests passed."
