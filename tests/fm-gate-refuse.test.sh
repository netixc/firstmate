#!/usr/bin/env bash
# no-mistakes gate-agent context cannot mutate Firstmate fleet lifecycle.
set -u
# shellcheck disable=SC2016 # $1/$2 expand in the inner bash processes.

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-gate-refuse-lib.sh
. "$ROOT/bin/fm-gate-refuse-lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-gate-refuse)

expect_refusal() { # <label> <command...>
  local label=$1 out rc
  shift
  out=$(FM_GATE_REFUSE_BYPASS=0 NO_MISTAKES_GATE=1 "$@" 2>&1); rc=$?
  [ "$rc" -ne 0 ] || fail "$label accepted gate-agent lifecycle access"
  assert_contains "$out" 'no-mistakes gate agent' "$label did not name the authority boundary"
}

test_helper_markers() {
  local out
  out=$(FM_GATE_REFUSE_BYPASS=0 NO_MISTAKES_GATE=1 bash -c '. "$1/bin/fm-gate-refuse-lib.sh"; fm_refuse_if_gate_agent' _ "$ROOT" 2>&1) \
    && fail "gate env marker should refuse"
  assert_contains "$out" 'no-mistakes gate agent' "env-marker refusal missing"
  # shellcheck disable=SC2016 # $1 expands in the inner bash process.
  out=$(env -u NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS=0 \
    bash -c '. "$1/bin/fm-gate-refuse-lib.sh"; fm_refuse_if_gate_agent; printf admitted' _ "$ROOT") \
    || fail "normal context should not refuse"
  [ "$out" = admitted ] || fail "normal context changed execution"
  pass "gate authority helper refuses the marker and admits a normal context"
}

test_lifecycle_entrypoints_refuse_before_resolution() {
  local home=$TMP_ROOT/home
  mkdir -p "$home/state" "$home/data" "$home/config"
  expect_refusal spawn env FM_HOME="$home" "$ROOT/bin/fm-spawn.sh" invalid
  expect_refusal send env FM_HOME="$home" "$ROOT/bin/fm-send.sh" missing hello
  expect_refusal control env FM_HOME="$home" "$ROOT/bin/fm-control.sh" missing exit
  expect_refusal teardown env FM_HOME="$home" "$ROOT/bin/fm-teardown.sh" missing
  [ -z "$(find "$home/state" -mindepth 1 -maxdepth 1 -print -quit)" ] \
    || fail "gate refusals mutated fleet state"
  pass "spawn, send, control, and cleanup refuse gate agents before task resolution"
}

test_path_backstop() {
  local gate_root=$TMP_ROOT/.no-mistakes/repos/gate.git home=$TMP_ROOT/path-home out
  mkdir -p "$(dirname "$gate_root")" "$home/state"
  git init -q --bare "$gate_root"
  # shellcheck disable=SC2016 # $1/$2 expand in the inner bash process.
  out=$(env -u NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS=0 NO_MISTAKES_GATE_REPO="$gate_root" FM_HOME="$home" \
    bash -c 'cd "$1"; . "$2/bin/fm-gate-refuse-lib.sh"; fm_refuse_if_gate_agent' _ "$gate_root" "$ROOT" 2>&1) \
    && fail "gate-repo path backstop should refuse"
  assert_contains "$out" 'no-mistakes gate worktree' "path-backstop refusal missing"
  pass "gate repository path remains a defense-in-depth authority backstop"
}

test_helper_markers
test_lifecycle_entrypoints_refuse_before_resolution
test_path_backstop
