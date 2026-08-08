#!/usr/bin/env bash
# Pi-only supervision instruction renderer tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-supervision-pi)
RENDER="$ROOT/bin/fm-supervision-instructions.sh"

expect_fail() {
  local want=$1
  shift
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "expected command to fail: $*"
  printf '%s' "$out" | grep -Fq -- "$want" || fail "failure did not contain '$want': $out"
}

test_pi_block() {
  local home="$TMP_ROOT/home" out
  mkdir -p "$home/state" "$home/config"
  out=$(FM_HOME="$home" "$RENDER")
  assert_contains "$out" 'primary runtime: pi' "Pi supervision heading missing"
  assert_contains "$out" 'Pi extension owns watcher continuity' "Pi continuity instruction missing"
  assert_contains "$out" 'fm_watch_arm_pi' "Pi first-cycle instruction missing"
  assert_not_contains "$out" '__FM_PI_EXT__' "renderer leaked Pi extension placeholder"
  pass "renderer emits Pi's sole supervision block"
}

test_pi_conditions_and_repair() {
  local home="$TMP_ROOT/conditions" out
  mkdir -p "$home/state" "$home/config"
  : > "$home/config/x-mode.env"
  out=$(FM_HOME="$home" "$RENDER" --read-only 1 --afk 1 --x-mode 1)
  assert_contains "$out" 'Lock: read-only' "read-only state missing"
  assert_contains "$out" 'Away mode: active' "away state missing"
  assert_contains "$out" 'Relay mode: active' "Relay state missing"
  out=$(FM_HOME="$home" "$RENDER" --queue-pending 1 --repair-line)
  assert_contains "$out" 'After draining queued wakes' "repair did not mention queue drain"
  assert_contains "$out" 'fm_watch_arm_pi' "repair did not name Pi arm tool"
  out=$(FM_HOME="$home" "$RENDER" --afk 1 --repair-line)
  assert_contains "$out" 'Away mode owns Pi watcher supervision' "away repair did not defer to away mode"
  pass "Pi renderer handles repair and conditional state"
}

test_runtime_choice_is_not_an_interface() {
  expect_fail 'unknown argument' "$RENDER" --unsupported-runtime
  pass "renderer exposes no runtime-choice argument"
}

test_pi_block
test_pi_conditions_and_repair
test_runtime_choice_is_not_an_interface
