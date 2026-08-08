#!/usr/bin/env bash
# AGENTS.md-only project-memory helper tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ENSURE="$ROOT/bin/fm-ensure-agents-md.sh"
TMP_ROOT=$(fm_test_tmproot fm-ensure-agents)

expect_fail() {
  local want=$1
  shift
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "expected failure: $*"
  printf '%s' "$out" | grep -Fq "$want" || fail "failure did not contain '$want': $out"
}

test_creates_agents_only() {
  local repo="$TMP_ROOT/create"
  mkdir -p "$repo"
  "$ENSURE" "$repo" >/dev/null
  assert_present "$repo/AGENTS.md" "AGENTS.md was not created"
  assert_grep '## Maintaining this file' "$repo/AGENTS.md" "maintenance section was not created"
  [ "$(find "$repo" -mindepth 1 -maxdepth 1 | wc -l | tr -d '[:space:]')" = 1 ] || fail "helper created an unexpected compatibility artifact"
  pass "project memory helper creates only AGENTS.md"
}

test_existing_agents_is_idempotent() {
  local repo="$TMP_ROOT/existing"
  mkdir -p "$repo"
  printf '# Existing\n' > "$repo/AGENTS.md"
  "$ENSURE" "$repo" >/dev/null
  "$ENSURE" "$repo" >/dev/null
  [ "$(grep -Fc '## Maintaining this file' "$repo/AGENTS.md")" -eq 1 ] || fail "maintenance section was not idempotent"
  pass "project memory helper updates existing AGENTS.md idempotently"
}

test_unsafe_forms_refuse() {
  local symlink_repo="$TMP_ROOT/symlink" case_repo="$TMP_ROOT/case"
  mkdir -p "$symlink_repo" "$case_repo"
  ln -s target "$symlink_repo/AGENTS.md"
  expect_fail 'AGENTS.md is a symlink' "$ENSURE" "$symlink_repo"
  printf '# lower case\n' > "$case_repo/agents.md"
  expect_fail 'convention is AGENTS.md' "$ENSURE" "$case_repo"
  pass "project memory helper refuses unsafe and case-variant memory files"
}

test_creates_agents_only
test_existing_agents_is_idempotent
test_unsafe_forms_refuse
