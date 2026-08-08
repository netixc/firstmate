#!/usr/bin/env bash
# Pi watcher-arm command guard tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK="$ROOT/bin/fm-arm-pretool-check.sh"

expect_deny() {
  local command=$1 expected=$2 out rc=0
  out=$("$CHECK" --command "$command" 2>&1) || rc=$?
  [ "$rc" -eq 2 ] || fail "expected Pi guard denial for '$command', got $rc: $out"
  printf '%s' "$out" | grep -Fq "$expected" || fail "denial missing '$expected': $out"
}

test_pi_transport_accepts_safe_arm_shape() {
  "$CHECK" --command 'exec bin/fm-watch-arm.sh' >/dev/null || fail "Pi guard rejected the owned arm shape"
  "$CHECK" --command 'echo ordinary command' >/dev/null || fail "Pi guard rejected an unrelated command"
  pass "Pi command transport accepts owned watcher arm and ordinary commands"
}

test_pi_transport_rejects_unsafe_shapes() {
  expect_deny 'bin/fm-watch-arm.sh &' '[watcher-background]'
  expect_deny 'bin/fm-watch-arm.sh | cat' '[watcher-pipeline]'
  expect_deny 'bin/fm-watch-arm.sh >/tmp/out' '[watcher-redirection]'
  expect_deny 'bin/fm-watch.sh' '[watcher-direct]'
  pass "Pi command transport rejects unsafe watcher lifecycle shapes"
}

test_retired_transport_forms_rejected() {
  local out rc=0
  printf '%s' '{"tool_name":"Bash"}' | "$CHECK" >/dev/null || fail "ignored stdin should not affect Pi transport"
  out=$("$CHECK" --unsupported-runtime --command 'echo ok' 2>&1) || rc=$?
  [ "$rc" -eq 2 ] || fail "retired transport flag unexpectedly succeeded"
  printf '%s' "$out" | grep -Fq 'Usage:' || fail "retired transport flag did not show Pi-only usage"
  pass "Pi command guard ignores stdin and rejects retired transport flags"
}

test_pi_transport_accepts_safe_arm_shape
test_pi_transport_rejects_unsafe_shapes
test_retired_transport_forms_rejected
