#!/usr/bin/env bash
# Pi primary working-directory guard tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-cd-pi)
fm_git_identity fmtest fmtest@example.invalid

make_primary() {
  local dir=$1
  mkdir -p "$dir/bin"
  git init -q "$dir"
  git -C "$dir" commit -q --allow-empty -m initial
  : > "$dir/AGENTS.md"
  cp "$ROOT/bin/fm-cd-pretool-check.sh" "$ROOT/bin/fm-cd-command-policy.mjs" \
    "$ROOT/bin/fm-arm-command-policy.mjs" "$dir/bin/"
  chmod +x "$dir/bin/fm-cd-pretool-check.sh"
}

run_check() {
  local root=$1 command=$2
  FM_ROOT_OVERRIDE="$root" "$root/bin/fm-cd-pretool-check.sh" --command "$command" 2>&1
}

expect_deny() {
  local root=$1 command=$2 expected=$3 out rc=0
  out=$(run_check "$root" "$command") || rc=$?
  [ "$rc" -eq 2 ] || fail "expected Pi cwd denial for '$command', got $rc: $out"
  printf '%s' "$out" | grep -Fq "$expected" || fail "cwd denial missing '$expected': $out"
}

test_pi_cwd_guard() {
  local primary="$TMP_ROOT/primary"
  make_primary "$primary"
  run_check "$primary" 'pwd' >/dev/null || fail "Pi guard rejected unrelated command"
  run_check "$primary" '(cd /tmp && pwd)' >/dev/null || fail "Pi guard rejected a scoped directory change"
  expect_deny "$primary" 'cd /tmp' '[persistent-cd]'
  expect_deny "$primary" 'pushd /tmp' '[persistent-cd]'
  pass "Pi primary cwd guard rejects persistent directory changes only"
}

test_retired_transport_flag_rejected() {
  local primary="$TMP_ROOT/flags" out rc=0
  make_primary "$primary"
  out=$(FM_ROOT_OVERRIDE="$primary" "$primary/bin/fm-cd-pretool-check.sh" --unsupported-runtime --command 'pwd' 2>&1) || rc=$?
  [ "$rc" -eq 2 ] || fail "retired cwd transport flag unexpectedly succeeded"
  printf '%s' "$out" | grep -Fq 'Usage:' || fail "retired cwd transport flag did not show usage"
  pass "Pi cwd guard rejects retired transport flags"
}

test_pi_cwd_guard
test_retired_transport_flag_rejected
